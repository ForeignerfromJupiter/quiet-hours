import AppKit
import Metal
import QuartzCore

/// Lumen: the time drawn in a few thousand points of light.
/// Ported from the prototype's `Lumen`: particles are spring-pulled to points sampled from the time
/// rendered in a heavy font, shimmer at rest, scatter on the minute and flow into the new time.
/// Simulation runs on the CPU; trails (a persistent feedback texture) and points are drawn with Metal.
final class LumenRenderer: ClockStyle {
    private struct Palette {
        let bg: SIMD3<Float>, ink: SIMD3<Float>
        let additive: Bool, fade: Float, alpha: Float
        let label: CGColor
        /// Prototype night bg rgb(7,8,11), deepened to true black.
        static let night = Palette(bg: rgb(0, 0, 0), ink: rgb(255, 228, 186), additive: true, fade: 0.2, alpha: 0.85,
                                   label: srgb(0xffe4ba, 0.45))
        static let paper = Palette(bg: rgb(236, 232, 224), ink: rgb(26, 24, 22), additive: false, fade: 0.26, alpha: 0.38,
                                   label: srgb(0x1e1c18, 0.5))
        static func rgb(_ r: Float, _ g: Float, _ b: Float) -> SIMD3<Float> { SIMD3(r, g, b) / 255 }
    }

    private struct GPUParticle { var pos: SIMD2<Float>; var alpha: Float; var size: Float }

    private let context: StyleContext
    private var palette: Palette
    private let metalLayer = CAMetalLayer()
    private let label = CATextLayer()

    private let device: MTLDevice?
    private var queue: MTLCommandQueue?
    private var fadePipe: MTLRenderPipelineState?
    private var blitPipe: MTLRenderPipelineState?
    private var additivePipe: MTLRenderPipelineState?
    private var alphaPipe: MTLRenderPipelineState?
    private var trail: MTLTexture?
    private var buffers: [MTLBuffer] = []
    private var bufferIndex = 0
    private let inFlight = DispatchSemaphore(value: 3)
    private var needsClear = true

    // Simulation (points, y down), prototype names.
    private var count = 0
    private var px: [Float] = [], py: [Float] = [], vx: [Float] = [], vy: [Float] = []
    private var tx: [Float] = [], ty: [Float] = [], ph: [Float] = []
    private var key: String?
    private var lastT: Double?
    private var releaseUntil: Double = 0
    private var bounds = CGRect.zero, scale: CGFloat = 2
    private var labelText = ""

    init(context: StyleContext) {
        self.context = context
        self.palette = context.appearance == .dark ? .night : .paper
        device = MTLCreateSystemDefaultDevice()
        guard let device else { return }
        queue = device.makeCommandQueue()
        do {
            let lib = try device.makeLibrary(source: Self.shaderSource, options: nil)
            func pipe(_ v: String, _ f: String, blend: (MTLRenderPipelineColorAttachmentDescriptor) -> Void) throws -> MTLRenderPipelineState {
                let d = MTLRenderPipelineDescriptor()
                d.vertexFunction = lib.makeFunction(name: v)
                d.fragmentFunction = lib.makeFunction(name: f)
                d.colorAttachments[0].pixelFormat = .bgra8Unorm
                blend(d.colorAttachments[0])
                return try device.makeRenderPipelineState(descriptor: d)
            }
            let sourceOver: (MTLRenderPipelineColorAttachmentDescriptor) -> Void = { c in
                c.isBlendingEnabled = true
                c.sourceRGBBlendFactor = .sourceAlpha; c.destinationRGBBlendFactor = .oneMinusSourceAlpha
                c.sourceAlphaBlendFactor = .zero; c.destinationAlphaBlendFactor = .one
            }
            fadePipe = try pipe("fullscreen_v", "solid_f", blend: sourceOver)
            blitPipe = try pipe("fullscreen_v", "blit_f") { _ in }
            alphaPipe = try pipe("point_v", "point_f", blend: sourceOver)
            additivePipe = try pipe("point_v", "point_f") { c in   // canvas 'lighter'
                c.isBlendingEnabled = true
                c.sourceRGBBlendFactor = .sourceAlpha; c.destinationRGBBlendFactor = .one
                c.sourceAlphaBlendFactor = .zero; c.destinationAlphaBlendFactor = .one
            }
        } catch {
            NSLog("QuietHours Lumen: Metal setup failed: \(error)")
        }
    }

    func start(in root: CALayer) {
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        metalLayer.isOpaque = true
        metalLayer.maximumDrawableCount = 3
        root.addSublayer(metalLayer)
        label.alignmentMode = .right
        root.addSublayer(label)
    }

    func layout(bounds: CGRect, scale: CGFloat) {
        self.bounds = bounds
        self.scale = scale
        metalLayer.frame = bounds
        metalLayer.contentsScale = scale
        let pw = max(1, Int(bounds.width * scale)), ph = max(1, Int(bounds.height * scale))
        metalLayer.drawableSize = CGSize(width: pw, height: ph)
        if let device {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: pw, height: ph, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .private
            trail = device.makeTexture(descriptor: d)
            needsClear = true
        }
        let W = Float(bounds.width), H = Float(bounds.height)
        var n = Int(min(max((W * H / 170).rounded(), 1800), 6000))
        if context.isPreview { n = min(n, 1500) }
        allocate(n, W, H)
        key = nil

        let u = bounds.width / 100
        label.contentsScale = scale
        label.frame = CGRect(x: 0, y: bounds.height - 2.8 * u - 1.6 * u, width: bounds.width - 3.2 * u, height: 1.8 * u)
        updateLabel()
    }

    private func allocate(_ n: Int, _ W: Float, _ H: Float) {
        count = n
        px = (0..<n).map { _ in Float.random(in: 0..<W) }
        py = (0..<n).map { _ in Float.random(in: 0..<H) }
        vx = Array(repeating: 0, count: n); vy = vx
        tx = px; ty = py
        ph = (0..<n).map { _ in Float.random(in: 0..<6.2832) }
        buffers = (0..<3).compactMap { _ in device?.makeBuffer(length: max(1, n) * MemoryLayout<GPUParticle>.stride, options: .storageModeShared) }
    }

    /// Renders the time in Anybody 800 into a third-resolution bitmap and samples opaque pixels.
    private func retarget(_ text: String) -> Bool {
        let W = bounds.width, H = bounds.height
        let sw = max(80, Int((W / 3).rounded())), sh = max(50, Int((H / 3).rounded()))
        guard let ctx = CGContext(data: nil, width: sw, height: sh, bitsPerComponent: 8, bytesPerRow: sw * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        var fs = CGFloat(sh) * 0.6
        func line(_ size: CGFloat) -> (CTLine, CTFont) {
            let font = Fonts.anybody(size: size, weight: 800, width: 100)
            let attr = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.white])
            return (CTLineCreateWithAttributedString(attr), font)
        }
        var (ln, font) = line(fs)
        let tw = CTLineGetTypographicBounds(ln, nil, nil, nil)
        if tw > Double(sw) * 0.82 { fs *= CGFloat(Double(sw) * 0.82 / tw); (ln, font) = line(fs) }
        let width = CGFloat(CTLineGetTypographicBounds(ln, nil, nil, nil))
        // textBaseline 'middle', y = sh/2 + fs*.03 (canvas, y down) → CG y up.
        let a = CTFontGetAscent(font), d = CTFontGetDescent(font)
        let middleDown = CGFloat(sh) / 2 + fs * 0.03
        let baselineDown = middleDown + (a - d) / 2
        ctx.textPosition = CGPoint(x: (CGFloat(sw) - width) / 2, y: CGFloat(sh) - baselineDown)
        CTLineDraw(ln, ctx)
        guard let data = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return false }
        var pts: [Int32] = []
        pts.reserveCapacity(sw * sh / 4)
        for y in 0..<sh {
            for x in 0..<sw where data[(y * sw + x) * 4 + 3] > 140 { pts.append(Int32(x)); pts.append(Int32(y)) }
        }
        let m = pts.count / 2
        guard m > 0 else { return false }
        let kx = Float(W) / Float(sw), ky = Float(H) / Float(sh)
        for i in 0..<count {
            let k = Int.random(in: 0..<m)
            tx[i] = (Float(pts[2 * k]) + Float.random(in: 0..<1)) * kx
            ty[i] = (Float(pts[2 * k + 1]) + Float.random(in: 0..<1)) * ky
        }
        return true
    }

    func render(time: ClockTime, frameTime: CFTimeInterval) {
        guard count > 0, bounds.width > 0 else { return }
        let reduce = context.reduceMotion
        let t = frameTime * 1000 / max(context.timeScale, 0.01)   // ms, prototype time base
        let W = Float(bounds.width)

        let digits = time.digits.map { $0.map(String.init) ?? "" }
        let text = digits[0] + digits[1] + ":" + digits[2] + digits[3]
        if text != key, retarget(text) {
            let first = key == nil
            key = text
            if !first && !reduce {
                releaseUntil = t + 750
                let sc = W / 1000
                for i in 0..<count {
                    let a = Float.random(in: 0..<6.2832), s = (1 + Float.random(in: 0..<4)) * sc
                    vx[i] += cos(a) * s * 4
                    vy[i] += sin(a) * s * 4 - sc * 2
                }
            }
        }

        let dt = Float(min(50, t - (lastT ?? t)))
        lastT = t
        let f = dt / 16.67
        let k: Float = reduce ? 1 : (t < releaseUntil ? 0.0016 : 0.011)
        let damp = pow(Float(0.89), f), nz = reduce ? 0 : W / 15000
        let tf = Float(t.truncatingRemainder(dividingBy: 1_000_000))
        for i in 0..<count {
            if reduce { px[i] = tx[i]; py[i] = ty[i]; continue }
            let n1 = sin(py[i] * 0.013 + tf * 0.0007 + ph[i]), n2 = cos(px[i] * 0.011 - tf * 0.0006 + ph[i])
            vx[i] = (vx[i] + ((tx[i] - px[i]) * k + n1 * nz) * f) * damp
            vy[i] = (vy[i] + ((ty[i] - py[i]) * k + n2 * nz) * f) * damp
            px[i] += vx[i] * f
            py[i] += vy[i] * f
        }
        draw(tf: tf, frameFactor: f)

        let label = [context.showSeconds ? String(time.secondDigits) : nil, time.meridiem].compactMap { $0 }.joined(separator: "   ")
        if label != labelText { labelText = label; updateLabel() }
    }

    private func draw(tf: Float, frameFactor f: Float) {
        guard let queue, let trail, let fadePipe, let blitPipe, let alphaPipe, let additivePipe,
              !buffers.isEmpty, inFlight.wait(timeout: .now()) == .success else { return }
        guard let drawable = metalLayer.nextDrawable(), let cmd = queue.makeCommandBuffer() else {
            inFlight.signal(); return
        }
        let sem = inFlight
        cmd.addCompletedHandler { _ in sem.signal() }

        // Upload particles (pixels).
        bufferIndex = (bufferIndex + 1) % buffers.count
        let buf = buffers[bufferIndex]
        let p = buf.contents().bindMemory(to: GPUParticle.self, capacity: count)
        let s = Float(scale), size = max(1.2, Float(bounds.width) / 720) * s
        for i in 0..<count {
            let a = palette.alpha * (0.55 + 0.45 * sin(tf * 0.0021 + ph[i] * 3))
            p[i] = GPUParticle(pos: SIMD2(px[i] * s, py[i] * s), alpha: a, size: size)
        }

        // Pass 1: fade the trail toward the background, then add this frame's points.
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = trail
        pass.colorAttachments[0].storeAction = .store
        let bg = palette.bg
        if needsClear {
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = MTLClearColor(red: Double(bg.x), green: Double(bg.y), blue: Double(bg.z), alpha: 1)
            needsClear = false
        } else {
            pass.colorAttachments[0].loadAction = .load
        }
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { cmd.commit(); return }
        // Fade per frame was tuned at 60 fps; keep trail length the same at other rates.
        let fade = context.reduceMotion ? 1 : 1 - pow(1 - palette.fade, max(f, 0.01))
        var fadeColor = SIMD4<Float>(bg.x, bg.y, bg.z, fade)
        enc.setRenderPipelineState(fadePipe)
        enc.setFragmentBytes(&fadeColor, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.setRenderPipelineState(palette.additive ? additivePipe : alphaPipe)
        enc.setVertexBuffer(buf, offset: 0, index: 0)
        var viewport = SIMD2<Float>(Float(trail.width), Float(trail.height))
        enc.setVertexBytes(&viewport, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
        var ink = SIMD4<Float>(palette.ink.x, palette.ink.y, palette.ink.z, 1)
        enc.setFragmentBytes(&ink, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: count)
        enc.endEncoding()

        // Pass 2: show the trail texture.
        let out = MTLRenderPassDescriptor()
        out.colorAttachments[0].texture = drawable.texture
        out.colorAttachments[0].loadAction = .dontCare
        out.colorAttachments[0].storeAction = .store
        guard let enc2 = cmd.makeRenderCommandEncoder(descriptor: out) else { cmd.commit(); return }
        enc2.setRenderPipelineState(blitPipe)
        enc2.setFragmentTexture(trail, index: 0)
        enc2.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc2.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    func appearanceDidChange(_ appearance: Appearance) {
        palette = appearance == .dark ? .night : .paper
        needsClear = true
        updateLabel()
    }

    func stop() {
        metalLayer.removeFromSuperlayer()
        label.removeFromSuperlayer()
        trail = nil
        buffers = []
    }

    private func updateLabel() {
        let size = 1.4 * bounds.width / 100
        label.string = NSAttributedString(string: labelText, attributes: [
            .font: Fonts.label(size: max(size, 1)), .kern: 0.24 * size,
            .foregroundColor: NSColor(cgColor: palette.label) ?? .gray,
        ])
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VOut { float4 pos [[position]]; float2 uv; float alpha; float size [[point_size]]; };
    struct Particle { float2 pos; float alpha; float size; };

    vertex VOut fullscreen_v(uint vid [[vertex_id]]) {
        float2 p = float2((vid << 1) & 2, vid & 2);
        VOut o; o.pos = float4(p * 2.0 - 1.0, 0, 1); o.uv = float2(p.x, 1.0 - p.y); o.alpha = 1; o.size = 1;
        return o;
    }
    fragment float4 solid_f(VOut in [[stage_in]], constant float4 &color [[buffer(0)]]) { return color; }
    fragment float4 blit_f(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]]) {
        constexpr sampler s(filter::nearest);
        return float4(tex.sample(s, in.uv).rgb, 1);
    }
    vertex VOut point_v(uint vid [[vertex_id]], const device Particle *ps [[buffer(0)]], constant float2 &viewport [[buffer(1)]]) {
        Particle p = ps[vid];
        float2 ndc = p.pos / viewport * 2.0 - 1.0; ndc.y = -ndc.y;
        VOut o; o.pos = float4(ndc, 0, 1); o.uv = float2(0); o.alpha = p.alpha; o.size = p.size;
        return o;
    }
    fragment float4 point_f(VOut in [[stage_in]], constant float4 &ink [[buffer(0)]]) { return float4(ink.rgb, in.alpha); }
    """
}

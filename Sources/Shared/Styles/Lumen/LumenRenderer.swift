import AppKit
import Metal
import QuartzCore

/// Lumen: the time drawn in a few thousand points of light.
///
/// Prototype behaviour: particles are spring-pulled to points sampled from the time rendered in a
/// heavy font, shimmer at rest, scatter on the minute and flow into the new time, with trails.
///
/// Native build, pushed further (PRD): particles live at three depths (size, brightness and
/// softness), a sparse field of stray particles drifts around the digits on a slow flow field, and
/// during the scatter particles curve along that flow instead of flying straight.
///
/// Everything per frame runs on the GPU: a compute kernel steps the simulation in place in one
/// shared buffer, the point shader reads it directly, and trails accumulate in a feedback texture
/// capped at ~4 MP (big panels upscale it). The CPU only samples new targets once a minute.
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

    /// Matches `Particle` in the shader (40 bytes).
    private struct Particle {
        var pos: SIMD2<Float>, vel: SIMD2<Float>, target: SIMD2<Float>
        var phase: Float, depth: Float, kind: Float, pad: Float
    }

    /// Matches `Uniforms` in the shader.
    private struct Uniforms {
        var size: SIMD2<Float>          // simulation space (points)
        var t: Float, f: Float, k: Float, damp: Float, noise: Float, impulse: Float
        var seed: UInt32, count: UInt32
        var flow: Float, pxPerPt: Float, pointSize: Float, alpha: Float, reduce: Float, pad: Float
    }

    /// Fraction of extra particles that never join the digits.
    static let strayFraction = 0.12
    /// Trails render into at most this many pixels and are upscaled (they are motion blur anyway);
    /// the current frame's points are then drawn again, crisp, at full resolution on top.
    /// Measured on 5K/100 Hz (QH_LUMEN_GPU=1): ~2 ms of GPU per frame either way.
    static let maxTrailPixels = 1_200_000.0
    /// Opacity of the crisp full-resolution pass relative to the trail's own copy of the points.
    static let crispPass: Float = 0.75

    private let context: StyleContext
    private var palette: Palette
    private let metalLayer = CAMetalLayer()
    private let label = CATextLayer()

    private let device: MTLDevice?
    private var queue: MTLCommandQueue?
    private var stepPipe: MTLComputePipelineState?
    private var fadePipe: MTLRenderPipelineState?
    private var blitPipe: MTLRenderPipelineState?
    private var additivePipe: MTLRenderPipelineState?
    private var alphaPipe: MTLRenderPipelineState?
    private var trail: MTLTexture?
    private var particles: MTLBuffer?
    private let inFlight = DispatchSemaphore(value: 3)
    private var needsClear = true

    private var digitCount = 0, total = 0
    private var key: String?
    private var lastT: Double?
    private var releaseUntil: Double = 0
    private var pendingImpulse = false
    private var bounds = CGRect.zero, scale: CGFloat = 2
    private var trailScale: Float = 1
    private var labelText = ""

    init(context: StyleContext) {
        self.context = context
        self.palette = context.appearance == .dark ? .night : .paper
        device = MTLCreateSystemDefaultDevice()
        guard let device else { return }
        queue = device.makeCommandQueue()
        do {
            let lib = try device.makeLibrary(source: Self.shaderSource, options: nil)
            if let step = lib.makeFunction(name: "step") { stepPipe = try device.makeComputePipelineState(function: step) }
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

    /// Particles never hold still, so no burn-in shift (it would also expose the Metal layer's edge).
    var allowsBurnInShift: Bool { false }

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
        trailScale = Float(min(1, (Self.maxTrailPixels / Double(pw * ph)).squareRoot()))
        if let device {
            let tw = max(1, Int(Float(pw) * trailScale)), th = max(1, Int(Float(ph) * trailScale))
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: tw, height: th, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .private
            trail = device.makeTexture(descriptor: d)
            needsClear = true
        }
        let W = Float(bounds.width), H = Float(bounds.height)
        var n = Int(min(max((W * H / 170).rounded(), 1800), 6000))
        if context.isPreview { n = min(n, 1500) }
        allocate(digits: n, W, H)
        key = nil

        let u = bounds.width / 100
        label.contentsScale = scale
        label.frame = CGRect(x: 0, y: bounds.height - 2.8 * u - 1.6 * u, width: bounds.width - 3.2 * u, height: 1.8 * u)
        updateLabel()
    }

    /// Digit particles start scattered; strays (kind 1) are spread across the screen at the far depth.
    private func allocate(digits n: Int, _ W: Float, _ H: Float) {
        digitCount = n
        total = n + Int(Double(n) * Self.strayFraction)
        guard let device, let buf = device.makeBuffer(length: max(1, total) * MemoryLayout<Particle>.stride,
                                                       options: .storageModeShared) else { return }
        let p = buf.contents().bindMemory(to: Particle.self, capacity: total)
        for i in 0..<total {
            let pos = SIMD2(Float.random(in: 0..<W), Float.random(in: 0..<H))
            let stray = i >= n
            // Depth: mostly mid, some near (bigger, brighter), some far (smaller, softer).
            let r = Float.random(in: 0..<1)
            let depth: Float = stray ? 0 : (r < 0.18 ? 1 : (r < 0.72 ? 0.5 : 0))
            p[i] = Particle(pos: pos, vel: .zero, target: pos, phase: Float.random(in: 0..<6.2832),
                            depth: depth, kind: stray ? 1 : 0, pad: 0)
        }
        particles = buf
    }

    /// Renders the time in Anybody 800 into a third-resolution bitmap and samples opaque pixels as
    /// the digit particles' new targets (CPU, once per change).
    private func retarget(_ text: String) -> Bool {
        guard let particles else { return false }
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
        let a = CTFontGetAscent(font), d = CTFontGetDescent(font)
        let baselineDown = CGFloat(sh) / 2 + fs * 0.03 + (a - d) / 2
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
        let p = particles.contents().bindMemory(to: Particle.self, capacity: total)
        for i in 0..<digitCount {   // a stale read of a target mid-frame is harmless
            let k = Int.random(in: 0..<m)
            p[i].target = SIMD2((Float(pts[2 * k]) + Float.random(in: 0..<1)) * kx,
                                (Float(pts[2 * k + 1]) + Float.random(in: 0..<1)) * ky)
        }
        return true
    }

    func render(time: ClockTime, frameTime: CFTimeInterval) {
        guard total > 0, bounds.width > 0 else { return }
        let reduce = context.reduceMotion
        let t = frameTime * 1000 / max(context.timeScale, 0.01)   // ms, prototype time base

        let digits = time.digits.map { $0.map(String.init) ?? "" }
        let text = digits[0] + digits[1] + ":" + digits[2] + digits[3]
        if text != key, retarget(text) {
            let first = key == nil
            key = text
            if !first && !reduce { releaseUntil = t + 750; pendingImpulse = true }
        }

        let dt = Float(min(50, t - (lastT ?? t)))
        lastT = t
        let f = dt / 16.67
        let W = Float(bounds.width)
        let releasing = t < releaseUntil
        var u = Uniforms(size: SIMD2(W, Float(bounds.height)),
                         t: Float(t.truncatingRemainder(dividingBy: 1_000_000)), f: f,
                         k: reduce ? 1 : (releasing ? 0.0016 : 0.011),
                         damp: pow(0.89, f), noise: reduce ? 0 : W / 15000,
                         impulse: pendingImpulse ? 1 : 0, seed: UInt32.random(in: 0...UInt32.max),
                         count: UInt32(total),
                         flow: reduce ? 0 : (releasing ? W / 2200 : W / 26000),
                         pxPerPt: Float(scale) * trailScale,
                         pointSize: max(1.2, W / 720) * Float(scale) * trailScale,
                         alpha: palette.alpha, reduce: reduce ? 1 : 0, pad: 0)
        if draw(&u, frameFactor: f) { pendingImpulse = false }

        let label = R3Chrome.labelText(time, showSeconds: context.showSeconds)
        if label != labelText { labelText = label; updateLabel() }
    }

    /// One frame: step the simulation, fade the trail, add this frame's points, show the trail.
    /// Returns false when the frame was skipped (GPU still busy with three frames).
    @discardableResult
    private func draw(_ u: inout Uniforms, frameFactor f: Float) -> Bool {
        guard let queue, let trail, let particles, let stepPipe, let fadePipe, let blitPipe,
              let alphaPipe, let additivePipe, inFlight.wait(timeout: .now()) == .success else { return false }
        guard let drawable = metalLayer.nextDrawable(), let cmd = queue.makeCommandBuffer() else {
            inFlight.signal(); return false
        }
        let sem = inFlight
        let probe = Self.gpuProbe
        cmd.addCompletedHandler { c in
            sem.signal()
            probe?.add(c.gpuEndTime - c.gpuStartTime)
        }

        if let c = cmd.makeComputeCommandEncoder() {
            c.setComputePipelineState(stepPipe)
            c.setBuffer(particles, offset: 0, index: 0)
            c.setBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
            let w = stepPipe.threadExecutionWidth
            c.dispatchThreadgroups(MTLSize(width: (total + w - 1) / w, height: 1, depth: 1),
                                   threadsPerThreadgroup: MTLSize(width: w, height: 1, depth: 1))
            c.endEncoding()
        }

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
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { cmd.commit(); return true }
        // Fade per frame was tuned at 60 fps; keep trail length the same at any refresh rate.
        let fade = context.reduceMotion ? 1 : 1 - pow(1 - palette.fade, max(f, 0.01))
        var fadeColor = SIMD4<Float>(bg.x, bg.y, bg.z, fade)
        enc.setRenderPipelineState(fadePipe)
        enc.setFragmentBytes(&fadeColor, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.setRenderPipelineState(palette.additive ? additivePipe : alphaPipe)
        enc.setVertexBuffer(particles, offset: 0, index: 0)
        enc.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
        var viewport = SIMD2<Float>(Float(trail.width), Float(trail.height))
        enc.setVertexBytes(&viewport, length: MemoryLayout<SIMD2<Float>>.stride, index: 2)
        var ink = SIMD4<Float>(palette.ink.x, palette.ink.y, palette.ink.z, 1)
        enc.setFragmentBytes(&ink, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: total)
        enc.endEncoding()

        let out = MTLRenderPassDescriptor()
        out.colorAttachments[0].texture = drawable.texture
        out.colorAttachments[0].loadAction = .dontCare
        out.colorAttachments[0].storeAction = .store
        guard let enc2 = cmd.makeRenderCommandEncoder(descriptor: out) else { cmd.commit(); return true }
        enc2.setRenderPipelineState(blitPipe)
        enc2.setFragmentTexture(trail, index: 0)
        enc2.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        if trailScale < 0.999 {
            // Crisp points at full resolution over the upscaled trail.
            var full = u
            full.pxPerPt = Float(scale)
            full.pointSize = u.pointSize / trailScale
            full.alpha = u.alpha * Self.crispPass
            var fullViewport = SIMD2<Float>(Float(drawable.texture.width), Float(drawable.texture.height))
            enc2.setRenderPipelineState(palette.additive ? additivePipe : alphaPipe)
            enc2.setVertexBuffer(particles, offset: 0, index: 0)
            enc2.setVertexBytes(&full, length: MemoryLayout<Uniforms>.stride, index: 1)
            enc2.setVertexBytes(&fullViewport, length: MemoryLayout<SIMD2<Float>>.stride, index: 2)
            enc2.setFragmentBytes(&ink, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
            enc2.drawPrimitives(type: .point, vertexStart: 0, vertexCount: total)
        }
        enc2.endEncoding()
        cmd.present(drawable)
        cmd.commit()
        return true
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
        particles = nil
    }

    private func updateLabel() {
        let size = 1.4 * bounds.width / 100
        label.string = NSAttributedString(string: labelText, attributes: [
            .font: Fonts.label(size: max(size, 1)), .kern: 0.24 * size,
            .foregroundColor: NSColor(cgColor: palette.label) ?? .gray,
        ])
    }

    /// Debug: QH_LUMEN_GPU=1 logs average GPU time per frame every 300 frames.
    private final class GPUProbe {
        private let lock = NSLock(); private var sum = 0.0; private var n = 0
        func add(_ t: Double) {
            lock.lock(); sum += t; n += 1
            if n == 300 { NSLog("Lumen GPU %.2f ms/frame", sum / 300 * 1000); sum = 0; n = 0 }
            lock.unlock()
        }
    }
    private static let gpuProbe: GPUProbe? = ProcessInfo.processInfo.environment["QH_LUMEN_GPU"] != nil ? GPUProbe() : nil

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Particle { float2 pos; float2 vel; float2 target; float phase; float depth; float kind; float pad; };
    struct Uniforms {
        float2 size; float t; float f; float k; float damp; float noise; float impulse;
        uint seed; uint count; float flow; float pxPerPt; float pointSize; float alpha; float reduce; float pad;
    };

    static float hash(uint x) {
        x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16;
        return float(x) / 4294967295.0;
    }

    // Divergence-free swirl: the curl of a slowly moving stream function.
    static float2 flowField(float2 p, float t) {
        float a = 0.0042, b = 0.00011;
        float2 q = p * a;
        return float2( cos(q.y * 1.3 + t * b) * sin(q.x + t * b * 0.7),
                      -sin(q.x * 1.1 - t * b) * cos(q.y * 0.9 + t * b * 1.3));
    }

    kernel void step(device Particle *ps [[buffer(0)]], constant Uniforms &u [[buffer(1)]],
                     uint id [[thread_position_in_grid]]) {
        if (id >= u.count) return;
        Particle p = ps[id];
        bool stray = p.kind > 0.5;
        if (u.reduce > 0.5) {
            if (!stray) { p.pos = p.target; p.vel = 0; }
            ps[id] = p; return;
        }
        float sc = u.size.x / 1000.0;
        if (u.impulse > 0.5 && !stray) {                       // scatter on the minute
            float a = hash(id * 2u + u.seed) * 6.2832;
            float s = (1.0 + hash(id * 2u + 1u + u.seed) * 4.0) * sc;
            p.vel += float2(cos(a), sin(a)) * s * 4.0;
            p.vel.y -= sc * 2.0;
        }
        float2 n = float2(sin(p.pos.y * 0.013 + u.t * 0.0007 + p.phase),
                          cos(p.pos.x * 0.011 - u.t * 0.0006 + p.phase));
        float2 swirl = flowField(p.pos, u.t);
        if (stray) {
            // Strays wander the flow field slowly and wrap around the screen.
            p.vel = (p.vel + (swirl * u.size.x / 9000.0 + n * u.noise * 0.6) * u.f) * pow(0.96, u.f);
            p.pos += p.vel * u.f;
            p.pos = fmod(p.pos + u.size, u.size);
        } else {
            p.vel = (p.vel + ((p.target - p.pos) * u.k + n * u.noise + swirl * u.flow) * u.f) * u.damp;
            p.pos += p.vel * u.f;
        }
        ps[id] = p;
    }

    struct VOut { float4 pos [[position]]; float2 uv; float alpha; float size [[point_size]]; float soft; };

    vertex VOut fullscreen_v(uint vid [[vertex_id]]) {
        float2 p = float2((vid << 1) & 2, vid & 2);
        VOut o; o.pos = float4(p * 2.0 - 1.0, 0, 1); o.uv = float2(p.x, 1.0 - p.y); o.alpha = 1; o.size = 1; o.soft = 0;
        return o;
    }
    fragment float4 solid_f(VOut in [[stage_in]], constant float4 &color [[buffer(0)]]) { return color; }
    fragment float4 blit_f(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]]) {
        constexpr sampler s(filter::linear);
        return float4(tex.sample(s, in.uv).rgb, 1);
    }

    vertex VOut point_v(uint vid [[vertex_id]], const device Particle *ps [[buffer(0)]],
                        constant Uniforms &u [[buffer(1)]], constant float2 &viewport [[buffer(2)]]) {
        Particle p = ps[vid];
        bool stray = p.kind > 0.5;
        float2 px = p.pos * u.pxPerPt;
        float2 ndc = px / viewport * 2.0 - 1.0; ndc.y = -ndc.y;
        float twinkle = 0.55 + 0.45 * sin(u.t * 0.0021 + p.phase * 3.0);
        // depth 0 far, 0.5 mid, 1 near: size, brightness and edge softness.
        float size = u.pointSize * mix(1.1, 2.4, p.depth);
        float bright = mix(0.55, 1.15, p.depth) * (stray ? 0.45 : 1.0);
        VOut o; o.pos = float4(ndc, 0, 1); o.uv = 0;
        o.alpha = clamp(u.alpha * twinkle * bright, 0.0, 1.0);
        o.size = max(1.0, size);
        o.soft = mix(0.15, 0.6, p.depth);   // far points are softer, near points crisper
        return o;
    }
    fragment float4 point_f(VOut in [[stage_in]], float2 pc [[point_coord]], constant float4 &ink [[buffer(0)]]) {
        float r = length(pc - 0.5) * 2.0;
        float a = in.alpha * (1.0 - smoothstep(in.soft, 1.0, r));
        if (a <= 0.002) discard_fragment();
        return float4(ink.rgb, a);
    }
    """
}

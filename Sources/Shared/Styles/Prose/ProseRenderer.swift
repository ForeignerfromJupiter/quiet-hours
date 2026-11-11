import Accelerate
import AppKit
import QuartzCore

/// Prose: the time as one sentence, set large like a page of a book.
/// Ported from the prototype's `Prose`. One layer per glyph so each letter animates on its own.
final class ProseRenderer: ClockStyle {
    private struct Palette {
        let roomCenter, roomEdge, ink, muted: CGColor
        /// Prototype night --bgA #16161a, --bgB #09090b; deepened (owner's call) to true black at the edges.
        static let night = Palette(roomCenter: srgb(0x0e0e11), roomEdge: srgb(0x000000),
                                   ink: srgb(0xefebe2), muted: srgb(0xefebe2, 0.42))
        static let paper = Palette(roomCenter: srgb(0xf4f1ea), roomEdge: srgb(0xe4dfd4),
                                   ink: srgb(0x171614), muted: srgb(0x171614, 0.5))
    }

    /// One letter: a crisp vector glyph and a pre-blurred bitmap that cross-fades in for the blur.
    private final class GlyphView {
        let container = CALayer()
        let sharp = CAShapeLayer()
        let soft = CALayer()
        var stagger = 0
        init() {
            container.anchorPoint = .zero
            container.bounds = .zero
            container.allowsGroupOpacity = true
            sharp.anchorPoint = .zero
            soft.opacity = 0
            container.addSublayer(soft)
            container.addSublayer(sharp)
        }
    }

    private final class WordView {
        let shape: ProseWordShape
        let layer = CALayer()
        var glyphs: [GlyphView] = []
        /// Placed at least once; a placed word glides when the lines reflow.
        var placed = false
        var from: CGPoint?
        var to = CGPoint.zero
        var line = -1
        /// Changing line: fade out where it was and back in where it goes, instead of sliding
        /// across the other words.
        var hops = false
        init(shape: ProseWordShape) {
            self.shape = shape
            layer.anchorPoint = .zero
            layer.bounds = .zero
        }
    }

    // Prototype timings (seconds) and curves.
    private static let outDuration = 0.38, outStagger = 0.014, outRise: CGFloat = 0.22, outBlur = 0.06
    private static let inDuration = 0.80, inStagger = 0.030, inDrop: CGFloat = 0.28, inBlur = 0.08
    private static let softSigma = 0.07   // em; one pre-blurred image serves both blurs
    private static let outCurve = CubicBezier(0.5, 0, 0.75, 0)
    private static let inCurve = CubicBezier(0.2, 0.8, 0.2, 1)
    /// Words that stay glide to their new place when the lines reflow (the prototype jumped).
    private static let glideDuration = 0.6
    private static let glideCurve = CubicBezier(0.65, 0, 0.35, 1)

    private let context: StyleContext
    private var appearance: Appearance
    private var palette: Palette
    private let background = CAGradientLayer()
    private let textRoot = CALayer()
    private let caret = CALayer()
    private let rule = CALayer()
    private let caption = CATextLayer()

    private var bounds = CGRect.zero
    private var scale: CGFloat = 2
    private var unit: CGFloat = 1
    private var fontSize: CGFloat = 10

    private var tokens: [ProseToken]?
    private var words: [WordView] = []
    private var outgoing: [WordView] = []
    private var outStart: CFTimeInterval = 0
    private var outTotal: Double = 0
    private var pending: (tokens: [ProseToken], prefix: Int, suffix: Int)?
    private var incoming: [WordView] = []
    private var inStart: CFTimeInterval = 0
    private var inTotal: Double = 0
    /// A reflow glide in progress: its start, and the rule and caption's vertical travel.
    private var glideStart: CFTimeInterval?
    private var ruleY: (from: CGFloat, to: CGFloat) = (0, 0)
    private var captionY: (from: CGFloat, to: CGFloat) = (0, 0)

    private var softCache: [String: (CGImage, CGRect)] = [:]
    private var captionText = ""

    private var speed: Double { max(context.timeScale, 0.01) }

    init(context: StyleContext) {
        self.context = context
        self.palette = context.appearance == .dark ? .night : .paper
        self.appearance = context.appearance
    }

    /// Idle between rewrites: the view stops the display link (the caret blinks on the render server).
    var wantsContinuousFrames: Bool { !outgoing.isEmpty || pending != nil || !incoming.isEmpty || glideStart != nil }

    // MARK: Lifecycle

    func start(in root: CALayer) {
        // radial-gradient(ellipse 85% 75% at 40% 45%, --bgA, --bgB)
        background.type = .radial
        background.startPoint = CGPoint(x: 0.40, y: 0.45)
        background.endPoint = CGPoint(x: 1.25, y: 1.20)
        root.addSublayer(background)
        root.addSublayer(textRoot)
        root.addSublayer(caret)
        root.addSublayer(rule)
        caption.alignmentMode = .left
        root.addSublayer(caption)
        applyPalette()
        startCaretBlink()
    }

    func layout(bounds: CGRect, scale: CGFloat) {
        snap()
        self.bounds = bounds
        self.scale = scale
        // Width-driven like the prototype (cqw); capped by height so a 3-line sentence always fits.
        unit = max(0.5, min(bounds.width / 100, bounds.height / 56))
        fontSize = ProseLayout.fontSizeUnits * unit
        softCache.removeAll()
        background.frame = Room.frame(bounds)
        textRoot.frame = bounds
        for l in [background, caret, rule, caption] { l.contentsScale = scale }
        if let tokens { rebuild(tokens) }
    }

    func stop() {
        for l in [background, textRoot, caret, rule, caption] { l.removeAllAnimations(); l.removeFromSuperlayer() }
        words = []; outgoing = []; incoming = []; pending = nil
        softCache.removeAll()
    }

    func appearanceDidChange(_ appearance: Appearance) {
        self.appearance = appearance
        palette = appearance == .dark ? .night : .paper
        softCache.removeAll()
        applyPalette()
        for w in words + outgoing + incoming { paint(w) }
    }

    // MARK: Frame

    func render(time: ClockTime, frameTime t: CFTimeInterval) {
        advance(t)
        let next = ProseSentence.tokens(hour: time.hour24, minute: time.minute)
        if next != tokens { rewrite(to: next, at: t) }

        var text = time.uses24Hour ? String(format: "%02d", time.hour24) : String(time.displayHour)
        text += String(format: ":%02d", time.minute)
        if context.showSeconds { text += String(format: ":%02d", time.second) }
        if let m = time.meridiem { text += " " + m }
        if text != captionText { captionText = text; updateCaption() }
    }

    // MARK: Rewrite

    private func rewrite(to next: [ProseToken], at t: CFTimeInterval) {
        guard let old = tokens, !words.isEmpty, !context.reduceMotion else {
            snap()
            tokens = next
            rebuild(next)
            return
        }
        snap()   // a rewrite still running jumps to its end first
        let (a, b) = ProseDiff.sharedEnds(old, next)
        tokens = next
        let oldMiddle = Array(words[a..<(words.count - b)])
        guard !oldMiddle.isEmpty else { swapIn(next, prefix: a, suffix: b, start: t, glide: true); return }

        var n = 0
        for w in oldMiddle { for g in w.glyphs { g.stagger = n; n += 1 } }
        outgoing = oldMiddle
        outStart = t
        outTotal = Self.outDuration + Double(n) * Self.outStagger   // prototype: 380 + n·14 ms
        pending = (next, a, b)
    }

    /// Replaces the changed middle with new words (hidden, ready to rise) and reflows the lines.
    private func swapIn(_ next: [ProseToken], prefix a: Int, suffix b: Int, start: CFTimeInterval, glide: Bool) {
        let middle = next[a..<(next.count - b)].map(makeWord)
        var k = 0
        for w in middle {
            for g in w.glyphs { g.stagger = k; k += 1; set(g, opacity: 0, rise: Self.inDrop * fontSize, blur: 1) }
            textRoot.addSublayer(w.layer)
        }
        words = Array(words.prefix(a)) + middle + Array(words.suffix(b))
        place(glideFrom: glide ? start : nil)
        incoming = middle
        inStart = start
        inTotal = Double(max(k - 1, 0)) * Self.inStagger + Self.inDuration
    }

    private func advance(_ t: CFTimeInterval) {
        if !outgoing.isEmpty {
            let e = (t - outStart) / speed
            for w in outgoing {
                for g in w.glyphs {
                    let p = Self.outCurve(min(max((e - Double(g.stagger) * Self.outStagger) / Self.outDuration, 0), 1))
                    set(g, opacity: 1 - p, rise: -Self.outRise * fontSize * CGFloat(p), blur: p * Self.outBlur / Self.softSigma)
                }
            }
            if e >= outTotal {
                for w in outgoing { w.layer.removeFromSuperlayer() }
                outgoing = []
                if let p = pending {
                    pending = nil
                    swapIn(p.tokens, prefix: p.prefix, suffix: p.suffix, start: outStart + outTotal * speed, glide: true)
                }
            }
        }
        if !incoming.isEmpty {
            let e = (t - inStart) / speed
            for w in incoming {
                for g in w.glyphs {
                    let k = Self.inCurve(min(max((e - Double(g.stagger) * Self.inStagger) / Self.inDuration, 0), 1))
                    set(g, opacity: k, rise: Self.inDrop * fontSize * CGFloat(1 - k), blur: min(1, (1 - k) * Self.inBlur / Self.softSigma))
                }
            }
            if e >= inTotal { finishIncoming() }
        }
        if let g = glideStart {
            let k = min(max((t - g) / speed / Self.glideDuration, 0), 1)
            if k >= 1 { finishGlide(); return }
            let e = CGFloat(Self.glideCurve(k))
            for w in words {
                guard let f = w.from else { continue }
                if w.hops {
                    w.layer.position = k < 0.5 ? f : w.to
                    w.layer.opacity = Float(k < 0.5 ? 1 - Self.glideCurve(k * 2) : Self.glideCurve(k * 2 - 1))
                } else {
                    w.layer.position = CGPoint(x: f.x + (w.to.x - f.x) * e, y: f.y + (w.to.y - f.y) * e)
                }
            }
            placeCaret()
            rule.frame.origin.y = ruleY.from + (ruleY.to - ruleY.from) * e
            caption.frame.origin.y = captionY.from + (captionY.to - captionY.from) * e
        }
    }

    /// Puts every gliding word, the caret, rule and caption where the reflow ends.
    private func finishGlide() {
        guard glideStart != nil else { return }
        glideStart = nil
        for w in words where w.from != nil { w.layer.position = w.to; w.layer.opacity = 1; w.from = nil }
        placeCaret()
        rule.frame.origin.y = ruleY.to
        caption.frame.origin.y = captionY.to
    }

    /// Ends any running rewrite immediately, leaving the final sentence in place.
    private func snap() {
        if !outgoing.isEmpty {
            for w in outgoing { w.layer.removeFromSuperlayer() }
            outgoing = []
        }
        if let p = pending {
            pending = nil
            swapIn(p.tokens, prefix: p.prefix, suffix: p.suffix, start: 0, glide: false)
        }
        finishIncoming()
        finishGlide()
    }

    private func finishIncoming() {
        for w in incoming { for g in w.glyphs { set(g, opacity: 1, rise: 0, blur: 0) } }
        incoming = []
    }

    private func set(_ g: GlyphView, opacity: Double, rise: CGFloat, blur: Double) {
        let b = Float(min(max(blur, 0), 1))
        g.container.opacity = Float(opacity)
        g.container.transform = rise == 0 ? CATransform3DIdentity : CATransform3DMakeTranslation(0, rise, 0)
        g.sharp.opacity = 1 - b
        g.soft.opacity = b
    }

    // MARK: Building and placing

    private func rebuild(_ next: [ProseToken]) {
        for w in words { w.layer.removeFromSuperlayer() }
        words = next.map(makeWord)
        for w in words { textRoot.addSublayer(w.layer) }
        place()
    }

    private func makeWord(_ token: ProseToken) -> WordView {
        let w = WordView(shape: ProseLayout.shape(token, fontSize: fontSize))
        for glyph in w.shape.glyphs {
            let g = GlyphView()
            g.container.position = CGPoint(x: glyph.x, y: 0)
            var flip = CGAffineTransform(scaleX: 1, y: -1)   // glyph space is y-up; ours is y-down
            var id = glyph.glyph
            g.sharp.path = CTFontCreatePathForGlyph(glyph.font, id, &flip)
            g.sharp.contentsScale = scale
            if let (img, rect) = softImage(glyph.font, &id) {
                g.soft.contents = img
                g.soft.frame = rect
            }
            w.glyphs.append(g)
            w.layer.addSublayer(g.container)
        }
        paint(w)
        return w
    }

    private func paint(_ w: WordView) {
        for (i, g) in w.glyphs.enumerated() {
            g.sharp.fillColor = palette.ink
            var id = w.shape.glyphs[i].glyph
            if let (img, rect) = softImage(w.shape.glyphs[i].font, &id) { g.soft.contents = img; g.soft.frame = rect }
        }
    }

    /// Lays the words out in balanced lines, left aligned at the 9% inset, block centered vertically.
    /// With `glideFrom`, words already on screen (and the rule and caption) glide to their new
    /// places from that time instead of jumping; new words are placed directly.
    private func place(glideFrom start: CFTimeInterval? = nil) {
        guard !words.isEmpty else { return }
        let fs = fontSize, stage = Room.stage(bounds), W = stage.width, H = bounds.height
        let space = ProseLayout.spaceWidth(fontSize: fs)
        var widths = words.map(\.shape.width)
        widths[widths.count - 1] += (ProseLayout.caretGap + ProseLayout.caretWidth) * fs   // caret rides on the last word
        let maxWidth = min(ProseLayout.maxWidthUnits * unit, W * (1 - 2 * ProseLayout.insetFraction))
        let lines = ProseLayout.balanced(widths, space: space, maxWidth: maxWidth)

        let regular = Fonts.instrumentSerif(size: fs, italic: false)
        let ascent = CTFontGetAscent(regular), descent = CTFontGetDescent(regular)
        let lineBox = ProseLayout.lineHeight * fs
        let blockHeight = CGFloat(lines.count) * lineBox + (ProseLayout.captionGapUnits + ProseLayout.captionSizeUnits) * unit
        let top = (H - blockHeight) / 2
        let left = stage.minX + W * ProseLayout.insetFraction

        for (li, line) in lines.enumerated() {
            let baseline = top + CGFloat(li) * lineBox + (lineBox - (ascent + descent)) / 2 + ascent
            var x = left
            for i in line {
                let w = words[i], p = CGPoint(x: x, y: baseline)
                if start != nil, w.placed, w.layer.position != p {
                    w.from = w.layer.position
                    w.to = p
                    w.hops = w.line != li
                } else {
                    w.layer.position = p
                    w.layer.opacity = 1
                    w.from = nil
                }
                w.placed = true
                w.line = li
                x += w.shape.width + space
            }
        }

        // Caption: a 3.2-unit rule, 1.4-unit gap, then the exact time in small mono.
        let capTop = top + CGFloat(lines.count) * lineBox + ProseLayout.captionGapUnits * unit
        let capSize = ProseLayout.captionSizeUnits * unit
        let ruleFrame = CGRect(x: left, y: capTop + capSize / 2 - 0.5 / scale, width: ProseLayout.ruleUnits * unit, height: max(1 / scale, 1))
        let captionFrame = CGRect(x: left + (ProseLayout.ruleUnits + 1.4) * unit, y: capTop - 0.1 * capSize,
                                  width: W / 2, height: capSize * 1.4)
        let moving = words.contains { $0.from != nil }
        if let start, moving || ruleFrame.minY != rule.frame.minY {
            glideStart = start
            ruleY = (rule.frame.minY, ruleFrame.minY)
            captionY = (caption.frame.minY, captionFrame.minY)
            rule.frame = CGRect(x: ruleFrame.minX, y: rule.frame.minY, width: ruleFrame.width, height: ruleFrame.height)
            caption.frame = CGRect(x: captionFrame.minX, y: caption.frame.minY, width: captionFrame.width, height: captionFrame.height)
        } else {
            glideStart = nil
            rule.frame = ruleFrame
            caption.frame = captionFrame
        }
        placeCaret()
    }

    /// Caret: .05em × .78em, .1em after the period, bottom .04em below the baseline; it rides on
    /// the last word, wherever that word is right now.
    private func placeCaret() {
        guard let last = words.last else { return }
        let fs = fontSize, p = last.layer.position
        caret.frame = CGRect(x: p.x + last.shape.width + ProseLayout.caretGap * fs,
                             y: p.y + (ProseLayout.caretDrop - ProseLayout.caretHeight) * fs,
                             width: ProseLayout.caretWidth * fs, height: ProseLayout.caretHeight * fs)
    }

    /// Pre-blurred glyph at quarter resolution (it is blurry anyway), cached per glyph and palette.
    /// Returns the image and its frame relative to the glyph's pen position on the baseline (y down).
    private func softImage(_ font: CTFont, _ glyph: inout CGGlyph) -> (CGImage, CGRect)? {
        let key = "\(CTFontCopyPostScriptName(font))-\(glyph)"
        if let hit = softCache[key] { return hit }
        var box = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(font, .horizontal, &glyph, &box, 1)
        guard box.width > 0, box.height > 0 else { return nil }
        let sigma = Self.softSigma * fontSize
        let rect = box.insetBy(dx: -3 * sigma, dy: -3 * sigma)                  // y-up glyph space
        let s = max(scale * 0.25, 0.25)
        let w = Int(ceil(rect.width * s)), h = Int(ceil(rect.height * s))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: s, y: s)
        ctx.translateBy(x: -rect.minX, y: -rect.minY)
        ctx.setFillColor(palette.ink)
        var origin = CGPoint.zero
        CTFontDrawGlyphs(font, &glyph, &origin, 1, ctx)
        // Blurred on the CPU (Accelerate): Core Image sets up ~70 MB of graphics buffers for every
        // new Prose instance, even with its software renderer, for a few tiny images.
        guard let image = Self.gaussianBlurred(ctx, sigma: Double(sigma * s)) else { return nil }
        let frame = CGRect(x: rect.minX, y: -rect.maxY, width: rect.width, height: rect.height)
        softCache[key] = (image, frame)
        return (image, frame)
    }

    /// Gaussian blur of a bitmap context's pixels as three box passes (sizes from the standard
    /// box-for-Gaussian fit), edges extended (the glyph images are padded with 3σ of transparency).
    static func gaussianBlurred(_ ctx: CGContext, sigma: Double) -> CGImage? {
        guard sigma > 0.2 else { return ctx.makeImage() }
        guard let data = ctx.data,
              let out = CGContext(data: nil, width: ctx.width, height: ctx.height, bitsPerComponent: 8,
                                  bytesPerRow: ctx.bytesPerRow, space: ctx.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: ctx.bitmapInfo.rawValue),
              let outData = out.data else { return nil }
        var a = vImage_Buffer(data: data, height: vImagePixelCount(ctx.height), width: vImagePixelCount(ctx.width), rowBytes: ctx.bytesPerRow)
        var b = vImage_Buffer(data: outData, height: a.height, width: a.width, rowBytes: ctx.bytesPerRow)
        let sizes = boxSizes(sigma: sigma, passes: 3)
        for (i, k) in sizes.enumerated() {
            let n = UInt32(k)
            let err = i % 2 == 0
                ? vImageBoxConvolve_ARGB8888(&a, &b, nil, 0, 0, n, n, nil, vImage_Flags(kvImageEdgeExtend))
                : vImageBoxConvolve_ARGB8888(&b, &a, nil, 0, 0, n, n, nil, vImage_Flags(kvImageEdgeExtend))
            guard err == kvImageNoError else { return nil }
        }
        return sizes.count % 2 == 1 ? out.makeImage() : ctx.makeImage()
    }

    /// Odd box widths whose repeated application approximates a Gaussian of `sigma` pixels.
    static func boxSizes(sigma: Double, passes n: Int) -> [Int] {
        let ideal = (12 * sigma * sigma / Double(n) + 1).squareRoot()
        var lower = Int(ideal.rounded(.down))
        if lower % 2 == 0 { lower -= 1 }
        lower = max(lower, 1)
        let upper = lower + 2
        let l = Double(lower)
        let m = Int(((12 * sigma * sigma - Double(n) * l * l - 4 * Double(n) * l - 3 * Double(n)) / (-4 * l - 4)).rounded())
        return (0..<n).map { $0 < m ? lower : upper }
    }

    // MARK: Chrome

    private func applyPalette() {
        background.colors = Room.colors(center: palette.roomCenter, edge: palette.roomEdge,
                                        appearance: appearance, pureBlack: context.pureBlack)
        caret.backgroundColor = palette.ink
        rule.backgroundColor = palette.muted
        updateCaption()
    }

    private func updateCaption() {
        let size = ProseLayout.captionSizeUnits * unit
        caption.string = NSAttributedString(string: captionText, attributes: [
            .font: Fonts.label(size: max(size, 1)), .kern: 0.22 * size,
            .foregroundColor: NSColor(cgColor: palette.muted) ?? .gray,
        ])
    }

    /// @keyframes psBlink { 0%,45% { opacity: .9 } 55%,100% { opacity: 0 } }, 1.2 s ease-in-out.
    /// Runs on the render server, so blinking costs this process nothing between rewrites.
    private func startCaretBlink() {
        caret.opacity = 0.9
        guard !context.reduceMotion else { return }
        let a = CAKeyframeAnimation(keyPath: "opacity")
        a.values = [0.9, 0.9, 0.0, 0.0]
        a.keyTimes = [0, 0.45, 0.55, 1]
        a.timingFunctions = [CAMediaTimingFunction(name: .linear),
                             CAMediaTimingFunction(name: .easeInEaseOut),
                             CAMediaTimingFunction(name: .linear)]
        a.duration = 1.2 * speed
        a.repeatCount = .infinity
        a.isRemovedOnCompletion = false
        caret.add(a, forKey: "blink")
    }
}

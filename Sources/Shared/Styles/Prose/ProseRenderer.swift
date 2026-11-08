import AppKit
import CoreImage
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

    private var softCache: [String: (CGImage, CGRect)] = [:]
    private lazy var ciContext = CIContext(options: [.cacheIntermediates: false])
    private var captionText = ""

    private var speed: Double { max(context.timeScale, 0.01) }

    init(context: StyleContext) {
        self.context = context
        self.palette = context.appearance == .dark ? .night : .paper
        self.appearance = context.appearance
    }

    /// Idle between rewrites: the view stops the display link (the caret blinks on the render server).
    var wantsContinuousFrames: Bool { !outgoing.isEmpty || pending != nil || !incoming.isEmpty }

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
        guard !oldMiddle.isEmpty else { swapIn(next, prefix: a, suffix: b, start: t); return }

        var n = 0
        for w in oldMiddle { for g in w.glyphs { g.stagger = n; n += 1 } }
        outgoing = oldMiddle
        outStart = t
        outTotal = Self.outDuration + Double(n) * Self.outStagger   // prototype: 380 + n·14 ms
        pending = (next, a, b)
    }

    /// Replaces the changed middle with new words (hidden, ready to rise) and reflows the lines.
    private func swapIn(_ next: [ProseToken], prefix a: Int, suffix b: Int, start: CFTimeInterval) {
        let middle = next[a..<(next.count - b)].map(makeWord)
        var k = 0
        for w in middle {
            for g in w.glyphs { g.stagger = k; k += 1; set(g, opacity: 0, rise: Self.inDrop * fontSize, blur: 1) }
            textRoot.addSublayer(w.layer)
        }
        words = Array(words.prefix(a)) + middle + Array(words.suffix(b))
        place()
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
                    swapIn(p.tokens, prefix: p.prefix, suffix: p.suffix, start: outStart + outTotal * speed)
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
    }

    /// Ends any running rewrite immediately, leaving the final sentence in place.
    private func snap() {
        if !outgoing.isEmpty {
            for w in outgoing { w.layer.removeFromSuperlayer() }
            outgoing = []
        }
        if let p = pending {
            pending = nil
            swapIn(p.tokens, prefix: p.prefix, suffix: p.suffix, start: 0)
        }
        finishIncoming()
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
    private func place() {
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
                words[i].layer.position = CGPoint(x: x, y: baseline)
                x += words[i].shape.width + space
            }
        }

        // Caret: .05em × .78em, .1em after the period, bottom .04em below the baseline.
        if let last = words.last {
            let p = last.layer.position
            caret.frame = CGRect(x: p.x + last.shape.width + ProseLayout.caretGap * fs,
                                 y: p.y + (ProseLayout.caretDrop - ProseLayout.caretHeight) * fs,
                                 width: ProseLayout.caretWidth * fs, height: ProseLayout.caretHeight * fs)
        }

        // Caption: a 3.2-unit rule, 1.4-unit gap, then the exact time in small mono.
        let capTop = top + CGFloat(lines.count) * lineBox + ProseLayout.captionGapUnits * unit
        let capSize = ProseLayout.captionSizeUnits * unit
        rule.frame = CGRect(x: left, y: capTop + capSize / 2 - 0.5 / scale, width: ProseLayout.ruleUnits * unit, height: max(1 / scale, 1))
        caption.frame = CGRect(x: left + (ProseLayout.ruleUnits + 1.4) * unit, y: capTop - 0.1 * capSize,
                               width: W / 2, height: capSize * 1.4)
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
        guard let sharp = ctx.makeImage() else { return nil }
        let input = CIImage(cgImage: sharp)
        let blurred = input.applyingGaussianBlur(sigma: Double(sigma * s)).cropped(to: input.extent)
        guard let image = ciContext.createCGImage(blurred, from: input.extent) else { return nil }
        let frame = CGRect(x: rect.minX, y: -rect.maxY, width: rect.width, height: rect.height)
        softCache[key] = (image, frame)
        return (image, frame)
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

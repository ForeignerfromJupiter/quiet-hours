import AppKit
import QuartzCore

// MARK: - Text (pure)

/// The strings Ticker shows (prototype `Ticker.frame`: `timeTxt`, `dateTxt`, `band`).
enum TickerText {
    /// `trimTime(p) + (secs ? ':' + p.sec : '')`: "10:09", "9:09" in 12h mode, "21:09:55" with seconds.
    static func time(_ t: ClockTime, showSeconds: Bool) -> String {
        let d = t.digits.compactMap { $0 }
        var s = String(d.dropLast(2)) + ":" + String(d.suffix(2))
        if showSeconds { s += ":" + String(t.secondDigits) }
        return s
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEEE dd MMM"
        return f
    }()

    /// `toLocaleDateString('en-GB', {weekday: 'long', day: '2-digit', month: 'short'})`, upper-cased,
    /// comma removed: "SUNDAY 08 NOV". Uses the formatter's (current) time zone.
    static func date(_ date: Date, timeZone: TimeZone = .current) -> String {
        dateFormatter.timeZone = timeZone
        return dateFormatter.string(from: date).uppercased(with: Locale(identifier: "en_GB"))
            .replacingOccurrences(of: ",", with: "")
    }

    /// The side tickers' text, one repeat of the band:
    /// `('QUIET HOURS  /  ' + date + '  /  ' + time + (h24 ? '' : ' ' + AM/PM) + '  /  ').split('').join(' ') + '   '`.
    static func band(date: String, time: String, meridiem: String?) -> String {
        let raw = "QUIET HOURS  /  " + date + "  /  " + time + (meridiem.map { " " + $0 } ?? "") + "  /  "
        return raw.map(String.init).joined(separator: " ") + "   "
    }
}

// MARK: - Stream model (pure)

/// The main line as a list of items laid end to end (prototype `items`). Positions are kept in
/// stream coordinates (`start`, never changes) and the whole line moves by one `scroll` value, so
/// every item moves by exactly the same sub-pixel amount and neighbours can never open a seam.
/// An item's text is fixed when it is appended, which only happens off the right edge.
struct TickerStream {
    enum Kind: Equatable { case time, sep, date }

    struct Item: Equatable {
        let id: Int
        let kind: Kind
        let text: String
        let start: Double    // left edge in stream coordinates
        let width: Double
        var end: Double { start + width }
    }

    /// `seq = ['time', 'sep', 'date', 'sep']`
    static let sequence: [Kind] = [.time, .sep, .date, .sep]

    private(set) var items: [Item] = []
    /// How far the line has moved left since it was built (points).
    private(set) var scroll: Double = 0
    private var seqIndex = 0
    private var nextID = 0

    /// Screen x of an item's left edge.
    func x(_ item: Item) -> Double { item.start - scroll }

    mutating func advance(by dx: Double) { scroll += dx }

    /// Drops items that have left on the left (`x + w < -W * .05`). Returns them.
    mutating func prune(screenWidth W: Double) -> [Item] {
        var gone: [Item] = []
        while let first = items.first, first.end - scroll < -W * 0.05 {
            gone.append(items.removeFirst())
        }
        return gone
    }

    /// Appends items until the line reaches `1.4 W` (the first one starts at `0.06 W`). `text` gives
    /// the current text for a kind; `width` measures an item. Returns the new items.
    mutating func fill(screenWidth W: Double, text: (Kind) -> String, width: (Kind, String) -> Double) -> [Item] {
        var added: [Item] = []
        var end = items.last?.end ?? (scroll + W * 0.06)
        while end - scroll < W * 1.4 {
            let kind = Self.sequence[seqIndex % Self.sequence.count]
            seqIndex += 1
            let s = kind == .sep ? "" : text(kind)
            let w = max(width(kind, s), 1)
            let item = Item(id: nextID, kind: kind, text: s, start: end, width: w)
            nextID += 1
            items.append(item)
            added.append(item)
            end += w
        }
        return added
    }

    /// Empties the line (resize, reduced motion text change). Returns the removed items.
    mutating func reset() -> [Item] {
        let gone = items
        items = []
        scroll = 0
        seqIndex = 0
        return gone
    }
}

// MARK: - Renderer

/// Ticker: the time and date as one enormous line of type scrolling endlessly left, solid time
/// then outlined date with accent dots between, plus two small mono tickers running the other
/// way. Ported from the prototype's `Ticker`.
///
/// Each item is one `CAShapeLayer` whose glyph path is built once (Core Text, cached per glyph and
/// per text) when the item enters off the right edge; per frame only positions change.
final class TickerRenderer: ClockStyle {
    /// One side ticker: the band text drawn once into an image, repeated by a replicator.
    private final class Band {
        let replicator = CAReplicatorLayer()
        let tile = CALayer()
        var width: Double = 1      // `bw`: the band's advance, its repeat distance
        init() {
            replicator.anchorPoint = .zero
            replicator.addSublayer(tile)
            tile.anchorPoint = .zero
        }
    }

    private let context: StyleContext
    private var appearance: Appearance
    private var palette: R3Palette
    private let chrome = R3Chrome()
    private let streamLayer = CALayer()
    private let bands = [Band(), Band()]          // top (moves right), bottom (moves left)
    private let rules = [CALayer(), CALayer()]

    private var stream = TickerStream()
    private var itemLayers: [Int: CAShapeLayer] = [:]
    private var pool: [CAShapeLayer] = []
    private var glyphPaths: [CGGlyph: CGPath] = [:]
    private var textPaths: [String: (path: CGPath, width: CGFloat)] = [:]
    private var font: CTFont?
    private var bandKey = ""

    private var bounds = CGRect.zero, scale: CGFloat = 2
    private var size: CGFloat = 0                 // type size: 46% of height
    private var lastT: Double?
    private var bandPhase: Double = 0
    private var minuteKey = Int.min
    private var dateText = ""
    private var shownTime = "", shownDate = ""    // reduced motion: what the still line says
    private var speed: Double { max(context.timeScale, 0.01) }

    var wantsContinuousFrames: Bool { !context.reduceMotion }

    init(context: StyleContext) {
        self.context = context
        self.palette = .forAppearance(context.appearance)
        self.appearance = context.appearance
    }

    func start(in root: CALayer) {
        chrome.install(in: root)
        chrome.label.isHidden = true                  // Ticker has no corner label
        streamLayer.anchorPoint = .zero
        root.addSublayer(streamLayer)
        for b in bands { root.addSublayer(b.replicator) }
        for r in rules { root.addSublayer(r) }
        applyPalette()
    }

    func layout(bounds: CGRect, scale: CGFloat) {
        self.bounds = bounds
        self.scale = scale
        chrome.layout(bounds: bounds, scale: scale)
        streamLayer.frame = bounds
        size = bounds.height * 0.46                    // size = H * .46
        font = size > 0 ? Fonts.anybody(size: size, weight: 800, width: 75) : nil   // fontStretch: condensed
        for item in stream.reset() { recycle(item) }
        glyphPaths.removeAll()
        textPaths.removeAll()
        bandKey = ""
        for b in bands { b.tile.contentsScale = scale }
        // fillRect(0, H*.13, W, 1) / fillRect(0, H*.875, W, 1), oversized for the burn-in shift.
        let room = Room.frame(bounds)
        for (r, y) in zip(rules, [0.13, 0.875]) {
            let py = (bounds.height * y * scale).rounded() / scale
            r.frame = CGRect(x: room.minX, y: py, width: room.width, height: 1)
        }
    }

    // MARK: Frame

    func render(time: ClockTime, frameTime: CFTimeInterval) {
        guard size > 0, let font else { return }
        let T = frameTime / speed
        let dt = lastT.map { min(0.064, max(0, T - $0)) } ?? 0        // dt = min(64, t - lt)
        lastT = T
        let W = Double(bounds.width), H = bounds.height
        let reduce = context.reduceMotion
        let v = reduce ? 0 : W * 0.06                                  // sp = W * .06 / 1000 per ms

        let mk = Int((time.date.timeIntervalSinceReferenceDate / 60).rounded(.down))
        if mk != minuteKey { minuteKey = mk; dateText = TickerText.date(time.date) }
        let timeText = TickerText.time(time, showSeconds: context.showSeconds)

        // Reduced motion: the line never moves, so rebuild it in place when its text goes stale.
        if reduce && (timeText != shownTime || dateText != shownDate) {
            for item in stream.reset() { recycle(item) }
            shownTime = timeText
            shownDate = dateText
        }

        stream.advance(by: v * dt)
        for item in stream.prune(screenWidth: W) { recycle(item) }
        let added = stream.fill(screenWidth: W,
                                text: { $0 == .time ? timeText : dateText },
                                width: { kind, s in kind == .sep ? Double(self.size * 0.62) : Double(self.textPath(s, font: font).width) })
        for item in added { makeLayer(for: item, font: font) }

        // cy = H*.5, base = cy + size*.36; each layer's origin is its item's (left, baseline).
        let base = H * 0.5 + size * 0.36
        for item in stream.items {
            guard let l = itemLayers[item.id] else { continue }
            let p = CGPoint(x: CGFloat(stream.x(item)) + l.bounds.minX, y: base + l.bounds.minY)
            if l.position != p { l.position = p }
        }

        updateBands(time: time, timeText: timeText, dt: dt, velocity: v)
    }

    private func makeLayer(for item: TickerStream.Item, font: CTFont) {
        let l = pool.popLast() ?? CAShapeLayer()
        l.anchorPoint = .zero
        l.contentsScale = scale
        let path: CGPath
        switch item.kind {
        case .time, .date:
            path = textPath(item.text, font: font).path
        case .sep:
            // arc(x + w/2, cy, size * .085): relative to the item's baseline origin.
            let r = size * 0.085, cx = CGFloat(item.width) / 2, cy = -size * 0.36
            path = CGPath(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r), transform: nil)
        }
        l.path = path
        let pad = strokeWidth + 2
        l.bounds = path.boundingBoxOfPath.insetBy(dx: -pad, dy: -pad)
        style(l, item.kind)
        itemLayers[item.id] = l
        streamLayer.addSublayer(l)
    }

    private var strokeWidth: CGFloat { max(1.2, size * 0.012) }       // lineWidth = max(1.2, size * .012)

    private func style(_ l: CAShapeLayer, _ kind: TickerStream.Kind) {
        switch kind {
        case .time:
            l.fillColor = palette.ink
            l.strokeColor = nil
        case .date:
            l.fillColor = nil
            l.strokeColor = palette.ink(0.9)                           // strokeStyle = ink .9
            l.lineWidth = strokeWidth
        case .sep:
            l.fillColor = palette.accent
            l.strokeColor = nil
        }
    }

    private func recycle(_ item: TickerStream.Item) {
        guard let l = itemLayers.removeValue(forKey: item.id) else { return }
        l.removeFromSuperlayer()
        l.path = nil
        pool.append(l)
        // Keep only the paths still on the line (one date, a couple of times).
        if textPaths.count > 4 {
            let live = Set(stream.items.map(\.text))
            textPaths = textPaths.filter { live.contains($0.key) }
        }
    }

    /// The text's outline with its baseline at y = 0 (y down) and its advance width. Glyph outlines
    /// are cached per glyph with their overlapping contours unioned, so the outlined date shows only
    /// the visible edge of each letter.
    private func textPath(_ text: String, font: CTFont) -> (path: CGPath, width: CGFloat) {
        if let hit = textPaths[text] { return hit }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        let path = CGMutablePath()
        for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
            let n = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: n), pos = [CGPoint](repeating: .zero, count: n)
            CTRunGetGlyphs(run, CFRange(location: 0, length: n), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: n), &pos)
            for i in 0..<n {
                guard let g = glyphPath(glyphs[i], font: font) else { continue }
                path.addPath(g, transform: CGAffineTransform(translationX: pos[i].x, y: -pos[i].y))
            }
        }
        let result = (path as CGPath, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
        textPaths[text] = result
        return result
    }

    private func glyphPath(_ glyph: CGGlyph, font: CTFont) -> CGPath? {
        if let hit = glyphPaths[glyph] { return hit }
        var flip = CGAffineTransform(scaleX: 1, y: -1)
        guard let raw = CTFontCreatePathForGlyph(font, glyph, &flip) else { return nil }
        let outline: CGPath
        if #available(macOS 13.0, *) { outline = raw.normalized(using: .winding) } else { outline = raw }
        glyphPaths[glyph] = outline
        return outline
    }

    // MARK: Side tickers

    private func updateBands(time: ClockTime, timeText: String, dt: Double, velocity v: Double) {
        let W = Double(bounds.width)
        let text = TickerText.band(date: dateText, time: timeText, meridiem: time.meridiem)
        if text != bandKey { renderBand(text) }
        let bw = bands[0].width
        // o1 = (t * sp * .35) mod bw, kept as a phase so a change of band width never jumps the
        // copy at the phase; the text just reflows after it.
        bandPhase = (bandPhase + v * 0.35 * dt).truncatingRemainder(dividingBy: bw)
        let margin = Double(Room.shiftMargin)
        let copies = Int(ceil((W + 2 * margin) / bw)) + 3
        // Top: x = -bw + o1 + k*bw (moves right); bottom: x = -o1 + k*bw (moves left).
        for (b, x0) in zip(bands, [bandPhase - 2 * bw, -bandPhase - bw]) {
            if b.replicator.instanceCount != copies { b.replicator.instanceCount = copies }
            let p = CGPoint(x: CGFloat(x0), y: 0)
            if b.replicator.position != p { b.replicator.position = p }
        }
    }

    /// Draws one repeat of the band (500 mono at max(9, W * .012), ink .42) into an image shared by
    /// both tickers and all their copies.
    private func renderBand(_ text: String) {
        bandKey = text
        let W = bounds.width, H = bounds.height
        let fs = max(9, W * 0.012)
        let font = Fonts.label(size: fs) as CTFont
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: NSColor(cgColor: palette.ink(0.42)) ?? .gray,
        ]))
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let bw = max(1, CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        ascent = ceil(ascent + 1); descent = ceil(descent + 1)
        let w = CGFloat(bw), h = ascent + descent
        let pw = Int(ceil(w * scale)), ph = Int(ceil(h * scale))
        var image: CGImage?
        if let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpace(name: CGColorSpace.sRGB)!,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            ctx.scaleBy(x: scale, y: scale)
            ctx.textPosition = CGPoint(x: 0, y: descent)
            CTLineDraw(line, ctx)
            image = ctx.makeImage()
        }
        // Baselines at H*.11 and H*.92.
        for (b, baseline) in zip(bands, [H * 0.11, H * 0.92]) {
            b.width = bw
            b.tile.contents = image
            b.tile.frame = CGRect(x: 0, y: baseline - ascent, width: CGFloat(pw) / scale, height: CGFloat(ph) / scale)
            b.replicator.instanceTransform = CATransform3DMakeTranslation(w, 0, 0)
            b.replicator.bounds = CGRect(x: 0, y: 0, width: w, height: H)
        }
        if bandPhase >= bw { bandPhase = bandPhase.truncatingRemainder(dividingBy: bw) }
    }

    // MARK: Appearance

    func appearanceDidChange(_ appearance: Appearance) {
        self.appearance = appearance
        palette = .forAppearance(appearance)
        applyPalette()
    }

    func stop() {
        chrome.remove()
        streamLayer.removeFromSuperlayer()
        for b in bands { b.replicator.removeFromSuperlayer() }
        for r in rules { r.removeFromSuperlayer() }
        for item in stream.reset() { recycle(item) }
        pool.removeAll()
        glyphPaths.removeAll()
        textPaths.removeAll()
    }

    private func applyPalette() {
        chrome.apply(palette, pureBlack: context.pureBlack && appearance == .dark)
        // pal.rule: rgba(ink, .14) at night, rgba(ink, .16) on paper.
        let rule = palette.ink(appearance == .dark ? 0.14 : 0.16)
        for r in rules { r.backgroundColor = rule }
        for item in stream.items { if let l = itemLayers[item.id] { style(l, item.kind) } }
        bandKey = ""     // redraw the band in the new ink on the next frame
    }
}

import AppKit
import QuartzCore

/// Hinge: a split-flap clock. Four cards (HH MM), optional small seconds cards,
/// AM/PM label above the first card. All sizes are in prototype units (1 u = 1% of screen width).
final class HingeRenderer: ClockStyle {
    private let context: StyleContext
    private var appearance: Appearance
    private var palette: HingePalette

    private let background = CAGradientLayer()
    private let label = CATextLayer()
    private let hourMinuteCards: [HingeCard]
    private let secondCards: [HingeCard]

    private var bounds = CGRect.zero
    private var scale: CGFloat = 2
    private var unit: CGFloat = 0
    private var leadingVisible: Bool?
    private var meridiem: String?
    private var hasRendered = false

    private var cardSize: CGSize { HingeLayout.cardSize(showSeconds: context.showSeconds) }
    private static let secondCardSize = HingeLayout.secondCardSize
    private static let pairGap = HingeLayout.pairGap
    private static let groupGap = HingeLayout.groupGap
    private static let labelRise = HingeLayout.labelRise
    private static let labelSize: CGFloat = 1.4

    init(context: StyleContext) {
        self.context = context
        self.palette = .forAppearance(context.appearance)
        self.appearance = context.appearance
        hourMinuteCards = (0..<4).map { _ in HingeCard(isSmall: false, timeScale: context.timeScale, freezeAt: context.freezeFlipAt) }
        secondCards = context.showSeconds
            ? (0..<2).map { _ in HingeCard(isSmall: true, timeScale: context.timeScale, freezeAt: context.freezeFlipAt) }
            : []
    }

    private var allCards: [HingeCard] { hourMinuteCards + secondCards }

    func start(in root: CALayer) {
        // radial-gradient(ellipse 70% 60% at 50% 40%, --bgA, --bgB)
        background.type = .radial
        background.startPoint = CGPoint(x: 0.5, y: 0.4)
        background.endPoint = CGPoint(x: 0.5 + 0.7, y: 0.4 + 0.6)
        root.addSublayer(background)
        for c in allCards { root.addSublayer(c.container) }
        label.alignmentMode = .left
        label.isWrapped = false
        root.addSublayer(label)
        applyPalette()
    }

    func layout(bounds: CGRect, scale: CGFloat) {
        self.bounds = bounds
        self.scale = scale
        background.frame = Room.frame(bounds)
        background.contentsScale = scale
        label.contentsScale = scale
        resize()
    }

    private var rowChange: LeadingSlotChange?
    /// Unit the card layers were last laid out at; during a glide they are scaled from it.
    private var layoutUnit: CGFloat = 0

    private func targetUnit(leading: Bool) -> CGFloat {
        HingeLayout.unit(width: bounds.width, height: bounds.height,
                         leadingVisible: leading, showSeconds: context.showSeconds)
    }

    /// Lays the cards out at `u` (rebuilding glyph paths), then positions the settled row.
    private func resize() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        rowChange = nil
        let leading = leadingVisible ?? true
        layoutCards(at: targetUnit(leading: leading))
        for c in allCards { c.container.isHidden = false }
        hourMinuteCards[0].container.isHidden = !leading
        hourMinuteCards[0].container.opacity = 1
        positionRow(unit: layoutUnit, leading: leading ? 1 : 0)
    }

    private func layoutCards(at u: CGFloat) {
        unit = u
        layoutUnit = u
        let main = CGSize(width: cardSize.width * u, height: cardSize.height * u)
        let small = CGSize(width: Self.secondCardSize.width * u, height: Self.secondCardSize.height * u)
        let mainGlyphs = HingeGlyphs(cardSize: main)
        for c in hourMinuteCards { c.layout(size: main, unit: u, glyphs: mainGlyphs, scale: scale) }
        if !secondCards.isEmpty {
            let smallGlyphs = HingeGlyphs(cardSize: small)
            for c in secondCards { c.layout(size: small, unit: u, glyphs: smallGlyphs, scale: scale) }
        }
        updateLabelText()
    }

    /// Flex row: [H]H gap MM gap [SS], bottoms aligned, centered, at `u` points per unit (the card
    /// layers are scaled from `layoutUnit`). `leading` is how much of the leading card's slot is
    /// open, 0…1: its slot narrows as it fades, and it sits just left of the second hour card.
    private func positionRow(unit u: CGFloat, leading p: CGFloat) {
        guard u > 0, layoutUnit > 0 else { return }
        let k = u / layoutUnit
        let t = k == 1 ? CATransform3DIdentity : CATransform3DMakeScale(k, k, 1)
        let main = cardSize.width * u, small = Self.secondCardSize.width * u
        let gap = Self.pairGap * u, groupGap = Self.groupGap * u
        var total = p * (main + gap) + main + groupGap + 2 * main + gap
        if !secondCards.isEmpty { total += groupGap + 2 * small + gap }
        let mainHeight = cardSize.height * u
        let rowLeft = (bounds.width - total) / 2
        let rowTop = (bounds.height - mainHeight) / 2
        let rowBottom = rowTop + mainHeight

        func place(_ c: HingeCard, left: CGFloat, width: CGFloat, height: CGFloat) {
            c.container.transform = t
            c.container.position = CGPoint(x: left + width / 2, y: rowBottom - height / 2)
        }
        var x = rowLeft + p * (main + gap)
        place(hourMinuteCards[0], left: x - main - gap, width: main, height: mainHeight)
        place(hourMinuteCards[1], left: x, width: main, height: mainHeight)
        x += main + groupGap
        place(hourMinuteCards[2], left: x, width: main, height: mainHeight)
        x += main + gap
        place(hourMinuteCards[3], left: x, width: main, height: mainHeight)
        x += main
        if !secondCards.isEmpty {
            let h = Self.secondCardSize.height * u
            x += groupGap
            place(secondCards[0], left: x, width: small, height: h)
            place(secondCards[1], left: x + small + gap, width: small, height: h)
        }

        // .hinge-ampm { left: .3cqw; top: -3.2cqw; font: 1.4cqw/1 mono }
        let fontSize = Self.labelSize * layoutUnit
        label.transform = t
        label.bounds = CGRect(x: 0, y: 0, width: 12 * layoutUnit, height: fontSize * 1.4)
        label.position = CGPoint(x: rowLeft + 0.3 * u + 6 * u, y: rowTop - Self.labelRise * u + fontSize * 1.4 * k / 2)
    }

    func render(time: ClockTime, frameTime: CFTimeInterval) {
        let animate = hasRendered && !context.reduceMotion
        let t = frameTime / max(context.timeScale, 0.01)
        let digits = time.digits
        let leading = digits[0] != nil

        if leading != leadingVisible {
            let was = leadingVisible
            leadingVisible = leading
            if animate, let was, was != leading, bounds.width > 0 {
                beginRowChange(opening: leading, at: t)
            } else {
                resize()
            }
        }
        // While the row opens, the flips wait for it (a flip starting later holds the old face).
        var flipAt = frameTime
        if let change = rowChange { flipAt = max(frameTime, change.changeStart * max(context.timeScale, 0.01)) }
        for (i, c) in hourMinuteCards.enumerated() { c.set(digits[i], now: flipAt, animate: animate) }
        if !secondCards.isEmpty {
            let s = time.secondDigits
            secondCards[0].set(s[0], now: frameTime, animate: animate)
            secondCards[1].set(s[1], now: frameTime, animate: animate)
        }
        if let change = rowChange { advanceRowChange(change, at: t) }

        if time.meridiem != meridiem || !hasRendered {
            meridiem = time.meridiem
            updateLabelText()
        }
        for c in allCards where c.isFlipping { c.update(now: frameTime) }
        hasRendered = true
    }

    private func beginRowChange(opening: Bool, at t: Double) {
        let from = targetUnit(leading: !opening), to = targetUnit(leading: opening)
        // Lay the cards out at the larger unit so the glide only ever scales them down.
        layoutCards(at: max(from, to))
        unit = from
        let card0 = hourMinuteCards[0].container
        card0.isHidden = false
        card0.opacity = opening ? 0 : 1
        rowChange = LeadingSlotChange(start: t, opening: opening, settle: HingeFlipTimeline.total)
        positionRow(unit: from, leading: opening ? 0 : 1)
    }

    private func advanceRowChange(_ change: LeadingSlotChange, at t: Double) {
        if change.isDone(at: t) {
            resize()   // settle: crisp layout at the final unit, card 0 shown or hidden
            return
        }
        let open = CGFloat(change.presence(at: t))
        let u = targetUnit(leading: false) + (targetUnit(leading: true) - targetUnit(leading: false)) * open
        unit = u
        hourMinuteCards[0].container.opacity = Float(open)
        positionRow(unit: u, leading: open)
    }

    func appearanceDidChange(_ appearance: Appearance) {
        self.appearance = appearance
        palette = .forAppearance(appearance)
        applyPalette()
    }

    func stop() {
        background.removeFromSuperlayer()
        label.removeFromSuperlayer()
        for c in allCards { c.container.removeFromSuperlayer() }
    }

    private func applyPalette() {
        background.colors = Room.colors(center: palette.roomCenter, edge: palette.roomEdge,
                                        appearance: appearance, pureBlack: context.pureBlack)
        for c in allCards { c.apply(palette) }
        updateLabelText()
    }

    private func updateLabelText() {
        guard let m = meridiem, layoutUnit > 0 else { label.string = nil; return }
        let size = Self.labelSize * layoutUnit
        label.string = NSAttributedString(string: m, attributes: [
            .font: Fonts.label(size: size),
            .kern: 0.24 * size,
            .foregroundColor: NSColor(cgColor: palette.label) ?? .gray,
        ])
    }
}

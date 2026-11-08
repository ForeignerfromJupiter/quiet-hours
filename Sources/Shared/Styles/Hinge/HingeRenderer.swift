import AppKit
import QuartzCore

/// Hinge: a split-flap clock. Four cards (HH MM), optional small seconds cards,
/// AM/PM label above the first card. All sizes are in prototype units (1 u = 1% of screen width).
final class HingeRenderer: ClockStyle {
    private let context: StyleContext
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
        background.frame = bounds
        background.contentsScale = scale
        label.contentsScale = scale
        resize()
    }

    /// Sizes the cards for the row that is currently showing, then positions them.
    /// Runs on layout and whenever the 12h leading card appears or disappears.
    private func resize() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        unit = HingeLayout.unit(width: bounds.width, height: bounds.height,
                                leadingVisible: leadingVisible ?? true,
                                showSeconds: context.showSeconds)

        let main = CGSize(width: cardSize.width * unit, height: cardSize.height * unit)
        let small = CGSize(width: Self.secondCardSize.width * unit, height: Self.secondCardSize.height * unit)
        let mainGlyphs = HingeGlyphs(cardSize: main)
        for c in hourMinuteCards { c.layout(size: main, unit: unit, glyphs: mainGlyphs, scale: scale) }
        if !secondCards.isEmpty {
            let smallGlyphs = HingeGlyphs(cardSize: small)
            for c in secondCards { c.layout(size: small, unit: unit, glyphs: smallGlyphs, scale: scale) }
        }
        updateLabelText()
        positionRow()
    }

    /// Flex row: [HH] gap [MM] gap [SS], bottoms aligned, centered. A hidden leading card takes no space.
    private func positionRow() {
        guard unit > 0 else { return }
        let showLeading = leadingVisible ?? true
        var groups: [[HingeCard]] = [
            showLeading ? [hourMinuteCards[0], hourMinuteCards[1]] : [hourMinuteCards[1]],
            [hourMinuteCards[2], hourMinuteCards[3]],
        ]
        if !secondCards.isEmpty { groups.append(secondCards) }

        func width(_ c: HingeCard) -> CGFloat { c.container.bounds.width }
        let groupWidths = groups.map { g in g.map(width).reduce(0, +) + CGFloat(g.count - 1) * Self.pairGap * unit }
        let total = groupWidths.reduce(0, +) + CGFloat(groups.count - 1) * Self.groupGap * unit
        let mainHeight = cardSize.height * unit
        let rowLeft = (bounds.width - total) / 2
        let rowTop = (bounds.height - mainHeight) / 2
        let rowBottom = rowTop + mainHeight

        var x = rowLeft
        for (gi, g) in groups.enumerated() {
            for (ci, c) in g.enumerated() {
                let s = c.container.bounds.size
                c.container.position = CGPoint(x: x + s.width / 2, y: rowBottom - s.height / 2)
                x += s.width + (ci < g.count - 1 ? Self.pairGap * unit : 0)
            }
            if gi < groups.count - 1 { x += Self.groupGap * unit }
        }

        // .hinge-ampm { left: .3cqw; top: -3.2cqw; font: 1.4cqw/1 mono }
        let fontSize = Self.labelSize * unit
        label.frame = CGRect(x: rowLeft + 0.3 * unit, y: rowTop - Self.labelRise * unit,
                             width: 12 * unit, height: fontSize * 1.4)
    }

    func render(time: ClockTime, frameTime: CFTimeInterval) {
        let animate = hasRendered && !context.reduceMotion
        let digits = time.digits
        for (i, c) in hourMinuteCards.enumerated() { c.set(digits[i], now: frameTime, animate: animate) }
        if !secondCards.isEmpty {
            let s = time.secondDigits
            secondCards[0].set(s[0], now: frameTime, animate: animate)
            secondCards[1].set(s[1], now: frameTime, animate: animate)
        }

        let leading = digits[0] != nil
        if leading != leadingVisible {
            leadingVisible = leading
            resize()
        }
        if time.meridiem != meridiem || !hasRendered {
            meridiem = time.meridiem
            updateLabelText()
        }
        for c in allCards where c.isFlipping { c.update(now: frameTime) }
        hasRendered = true
    }

    func appearanceDidChange(_ appearance: Appearance) {
        palette = .forAppearance(appearance)
        applyPalette()
    }

    func stop() {
        background.removeFromSuperlayer()
        label.removeFromSuperlayer()
        for c in allCards { c.container.removeFromSuperlayer() }
    }

    private func applyPalette() {
        background.colors = [palette.roomCenter, palette.roomEdge]
        for c in allCards { c.apply(palette) }
        updateLabelText()
    }

    private func updateLabelText() {
        guard let m = meridiem, unit > 0 else { label.string = nil; return }
        let size = Self.labelSize * unit
        label.string = NSAttributedString(string: m, attributes: [
            .font: Fonts.label(size: size),
            .kern: 0.24 * size,
            .foregroundColor: NSColor(cgColor: palette.label) ?? .gray,
        ])
    }
}

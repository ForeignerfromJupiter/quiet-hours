import CoreGraphics

/// Hinge sizing. All proportions come from the prototype, in units where 1 u was 1% of the
/// screen width (CSS `cqw`). The native build then scales `u` so the row that is showing fills
/// the screen, instead of using the prototype's fixed 1 u = 1% of the width.
enum HingeLayout {
    static func cardSize(showSeconds: Bool) -> CGSize {
        showSeconds ? CGSize(width: 17.4, height: 25) : CGSize(width: 21.5, height: 31)
    }
    static let secondCardSize = CGSize(width: 5.9, height: 8.4)
    static let pairGap: CGFloat = 1        // between the two cards of a pair
    static let groupGap: CGFloat = 3.2     // between hours, minutes and seconds
    static let labelRise: CGFloat = 3.2    // AM/PM label sits this far above the cards

    /// Share of the screen width the visible row fills.
    static let widthFill: CGFloat = 0.94
    /// Share of the screen height the cards plus the AM/PM label may take.
    static let heightFill: CGFloat = 0.70

    /// Row width in units: [H]H  MM  [SS].
    static func rowWidth(leadingVisible: Bool, showSeconds: Bool) -> CGFloat {
        let card = cardSize(showSeconds: showSeconds).width
        let hours = leadingVisible ? 2 * card + pairGap : card
        let minutes = 2 * card + pairGap
        var width = hours + groupGap + minutes
        if showSeconds { width += groupGap + 2 * secondCardSize.width + pairGap }
        return width
    }

    /// Points per unit. The visible row fills `widthFill` of the width unless that would make the
    /// block taller than `heightFill` of the height. So a three-card 12h time like 7:49 gets
    /// larger cards than 10:49, and ultrawide screens stay height-limited.
    static func unit(width: CGFloat, height: CGFloat, leadingVisible: Bool, showSeconds: Bool) -> CGFloat {
        let byWidth = widthFill * width / rowWidth(leadingVisible: leadingVisible, showSeconds: showSeconds)
        let byHeight = heightFill * height / (cardSize(showSeconds: showSeconds).height + labelRise)
        return max(0.5, min(byWidth, byHeight))
    }
}

import AppKit
import QuartzCore

/// Digit outlines for one card size, positioned in card space (origin top-left, y down) the way
/// the prototype's CSS lays them out: font-size 80% of card height, line-height = card height,
/// centered on the advance width.
struct HingeGlyphs {
    let paths: [Character: CGPath]

    init(cardSize: CGSize) {
        let font = Fonts.anybody(size: cardSize.height * 0.8, weight: 680, width: 74)
        let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font)
        let baseline = (cardSize.height - (ascent + descent)) / 2 + ascent
        var out: [Character: CGPath] = [:]
        for ch in "0123456789" {
            var unichar = UniChar(ch.unicodeScalars.first!.value)
            var glyph: CGGlyph = 0
            guard CTFontGetGlyphsForCharacters(font, &unichar, &glyph, 1) else { continue }
            var advance = CGSize.zero
            CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
            var t = CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                                      tx: (cardSize.width - advance.width) / 2, ty: baseline)
            out[ch] = CTFontCreatePathForGlyph(font, glyph, &t)
        }
        paths = out
    }

    func path(_ ch: Character?) -> CGPath? { ch.flatMap { paths[$0] } }
}

/// One split-flap card: two static halves, two moving leaves, shades, seam, pins, highlight, shadow.
final class HingeCard {
    let container = CALayer()
    let isSmall: Bool

    private let shadowSoft = CALayer(), shadowTight = CALayer()
    private let topHalf = CAGradientLayer(), topGlyph = CAShapeLayer(), topHighlight = CALayer()
    private let bottomHalf = CAGradientLayer(), bottomGlyph = CAShapeLayer(), bottomShade = CALayer()
    private let front = CAGradientLayer(), frontGlyph = CAShapeLayer(), frontHighlight = CALayer(), frontShade = CAGradientLayer()
    private let back = CAGradientLayer(), backGlyph = CAShapeLayer(), backShade = CAGradientLayer()
    private let seam = CALayer(), pinLeft = CALayer(), pinRight = CALayer()
    /// Holds the two moving leaves and carries the perspective. A plain CALayer flattens its
    /// sublayers, so the leaves are composited at z = 0 and the seam and pins (later siblings)
    /// always draw on top, like the CSS z-index stacking. Without it Core Animation depth-sorts
    /// the tilted leaves in front of the seam.
    private let leafPlane = CALayer()

    private var glyphs: HingeGlyphs?
    private(set) var value: Character?
    private var topChar: Character?, bottomChar: Character?, frontChar: Character?, backChar: Character?
    private var flip: (start: CFTimeInterval, to: Character)?
    private let timeScale: Double
    private let freezeAt: Double?

    var isFlipping: Bool { flip != nil }

    init(isSmall: Bool, timeScale: Double, freezeAt: Double? = nil) {
        self.isSmall = isSmall
        self.timeScale = max(timeScale, 0.01)
        self.freezeAt = freezeAt

        container.allowsGroupOpacity = true
        container.opacity = isSmall ? 0.82 : 1
        container.isHidden = true

        for half in [topHalf, front] { half.masksToBounds = true; half.maskedCorners = Self.topCorners }
        for half in [bottomHalf, back] { half.masksToBounds = true; half.maskedCorners = Self.bottomCorners }
        for g in [topHalf, bottomHalf, front, back] {
            g.startPoint = CGPoint(x: 0.5, y: 0)
            g.endPoint = CGPoint(x: 0.5, y: 1)
        }
        for leaf in [front, back] {
            leaf.isDoubleSided = false
            leaf.allowsEdgeAntialiasing = true
            leaf.isHidden = true
        }
        front.anchorPoint = CGPoint(x: 0.5, y: 1)   // hinge on its bottom edge
        back.anchorPoint = CGPoint(x: 0.5, y: 0)    // hinge on its top edge
        for s in [frontShade, backShade] {
            s.startPoint = CGPoint(x: 0.5, y: 0)
            s.endPoint = CGPoint(x: 0.5, y: 1)
        }
        frontShade.opacity = 0
        bottomShade.opacity = 0

        shadowSoft.shadowOpacity = 0.8
        shadowTight.shadowOpacity = 0.35
        for s in [shadowSoft, shadowTight] { s.shadowColor = CGColor(gray: 0, alpha: 1) }

        topHalf.addSublayer(topGlyph); topHalf.addSublayer(topHighlight)
        bottomHalf.addSublayer(bottomGlyph); bottomHalf.addSublayer(bottomShade)
        front.addSublayer(frontGlyph); front.addSublayer(frontHighlight); front.addSublayer(frontShade)
        back.addSublayer(backGlyph); back.addSublayer(backShade)
        pinLeft.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        pinRight.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]

        leafPlane.addSublayer(front)
        leafPlane.addSublayer(back)
        for l in [shadowSoft, shadowTight, bottomHalf, topHalf, leafPlane, seam, pinLeft, pinRight] {
            container.addSublayer(l)
        }
    }

    // In the geometry-flipped tree, min Y is the visual top.
    private static let topCorners: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    private static let bottomCorners: CACornerMask = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]

    // MARK: Geometry

    /// `u` is the layout unit (1% of screen width in the prototype).
    func layout(size: CGSize, unit u: CGFloat, glyphs: HingeGlyphs, scale: CGFloat) {
        self.glyphs = glyphs
        let w = size.width, h = size.height, half = h / 2
        let r = (isSmall ? 0.6 : 1.6) * u
        let px = 1 / scale

        container.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / (60 * u)
        // perspective: 60cqw, origin at the card's center (the hinge line)
        leafPlane.frame = CGRect(x: 0, y: 0, width: w, height: h)
        leafPlane.sublayerTransform = perspective

        let topRect = CGRect(x: 0, y: 0, width: w, height: half)
        let bottomRect = CGRect(x: 0, y: half, width: w, height: half)
        let full = CGRect(x: 0, y: 0, width: w, height: h)

        for l in [topHalf, bottomHalf, front, back] { l.cornerRadius = r }
        topHalf.frame = topRect
        bottomHalf.frame = bottomRect
        front.bounds = CGRect(x: 0, y: 0, width: w, height: half)
        front.position = CGPoint(x: w / 2, y: half)
        back.bounds = front.bounds
        back.position = CGPoint(x: w / 2, y: half)

        topGlyph.frame = full
        frontGlyph.frame = full
        bottomGlyph.frame = full.offsetBy(dx: 0, dy: -half)
        backGlyph.frame = full.offsetBy(dx: 0, dy: -half)

        // box-shadow: inset 0 .12cqw 0 var(--hi)
        let hi = CGRect(x: 0, y: 0, width: w, height: max(px, 0.12 * u))
        topHighlight.frame = hi
        frontHighlight.frame = hi

        bottomShade.frame = CGRect(x: 0, y: 0, width: w, height: half)
        frontShade.frame = front.bounds
        backShade.frame = back.bounds

        // box-shadow: 0 1.6cqw 2.6cqw -.8cqw rgba(0,0,0,.8), 0 .3cqw .5cqw rgba(0,0,0,.35)
        // CSS blur radius ≈ 2 × CA shadowRadius; negative spread insets the shape.
        for s in [shadowSoft, shadowTight] { s.frame = bottomRect }
        let spread = 0.8 * u
        shadowSoft.shadowPath = Self.bottomRounded(CGRect(x: 0, y: 0, width: w, height: half).insetBy(dx: spread, dy: spread),
                                                   radius: max(0, r - spread))
        shadowSoft.shadowOffset = CGSize(width: 0, height: 1.6 * u)
        shadowSoft.shadowRadius = 1.3 * u
        shadowTight.shadowPath = Self.bottomRounded(CGRect(x: 0, y: 0, width: w, height: half), radius: r)
        shadowTight.shadowOffset = CGSize(width: 0, height: 0.3 * u)
        shadowTight.shadowRadius = 0.25 * u

        // ::after seam, ::before pins
        let seamH = max(px, 0.2 * u)
        seam.frame = CGRect(x: 0, y: half - seamH / 2, width: w, height: seamH)
        let pinW = (isSmall ? 0.3 : 0.55) * u
        let pinH = (isSmall ? 0.8 : 1.8) * u
        let overhang = (isSmall ? 0.15 : 0.3) * u
        pinLeft.frame = CGRect(x: -overhang, y: half - pinH / 2, width: pinW, height: pinH)
        pinRight.frame = CGRect(x: w + overhang - pinW, y: half - pinH / 2, width: pinW, height: pinH)
        for p in [pinLeft, pinRight] { p.cornerRadius = 0.25 * u }

        setScale(scale)
        refreshGlyphPaths()
    }

    private func setScale(_ scale: CGFloat) {
        var stack: [CALayer] = [container]
        while let l = stack.popLast() {
            l.contentsScale = scale
            stack.append(contentsOf: l.sublayers ?? [])
        }
    }

    private static func bottomRounded(_ rect: CGRect, radius r: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let r = min(r, rect.width / 2, rect.height)
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: r)
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: r)
        p.closeSubpath()
        return p
    }

    // MARK: Colors

    func apply(_ p: HingePalette) {
        topHalf.colors = [p.topA, p.topB]
        front.colors = [p.topA, p.topB]
        bottomHalf.colors = [p.bottomA, p.bottomB]
        back.colors = [p.bottomA, p.bottomB]
        for g in [topGlyph, bottomGlyph, frontGlyph, backGlyph] { g.fillColor = p.ink }
        topHighlight.backgroundColor = p.highlight
        frontHighlight.backgroundColor = p.highlight
        bottomShade.backgroundColor = p.fold
        frontShade.colors = [p.foldClear, p.fold]
        backShade.colors = [p.fold, p.foldClear]
        seam.backgroundColor = p.seam
        pinLeft.backgroundColor = p.pin
        pinRight.backgroundColor = p.pin
    }

    // MARK: Values and flipping

    /// Shows `v` (nil hides the card). Animates from the current digit when `animate` is true.
    func set(_ v: Character?, now: CFTimeInterval, animate: Bool) {
        guard v != value else { return }
        let old = value
        value = v
        container.isHidden = (v == nil)
        guard let v else { endFlip(); return }

        if let old, animate {
            // Same assignment as the prototype's set(): top shows new, bottom shows old until the
            // back leaf lands; the front leaf carries the old digit down, the back leaf brings the new one.
            topChar = v; bottomChar = old; frontChar = old; backChar = v
            refreshGlyphPaths()
            flip = (now, v)
            apply(HingeFlipTimeline.state(at: 0))
        } else {
            topChar = v; bottomChar = v
            endFlip()
            refreshGlyphPaths()
        }
    }

    /// Advances a running flip. Returns true while still flipping.
    @discardableResult
    func update(now: CFTimeInterval) -> Bool {
        guard let f = flip else { return false }
        let state = HingeFlipTimeline.state(at: freezeAt ?? (now - f.start) / timeScale)
        if state.finished {
            bottomChar = f.to
            bottomGlyph.path = glyphs?.path(f.to)
            endFlip()
            return false
        }
        apply(state)
        return true
    }

    private func apply(_ s: HingeFlipTimeline.State) {
        front.isHidden = !s.frontVisible
        front.transform = CATransform3DMakeRotation(CGFloat(s.frontAngle * .pi / 180), 1, 0, 0)
        frontShade.opacity = Float(s.frontShade)
        bottomShade.opacity = Float(s.bottomShade)
        back.isHidden = !s.backVisible
        back.transform = CATransform3DMakeRotation(CGFloat(s.backAngle * .pi / 180), 1, 0, 0)
        backShade.opacity = Float(s.backShade)
    }

    private func endFlip() {
        flip = nil
        front.isHidden = true
        back.isHidden = true
        front.transform = CATransform3DIdentity
        back.transform = CATransform3DIdentity
        frontShade.opacity = 0
        bottomShade.opacity = 0
    }

    private func refreshGlyphPaths() {
        guard let glyphs else { return }
        topGlyph.path = glyphs.path(topChar)
        bottomGlyph.path = glyphs.path(bottomChar)
        frontGlyph.path = glyphs.path(frontChar)
        backGlyph.path = glyphs.path(backChar)
    }
}

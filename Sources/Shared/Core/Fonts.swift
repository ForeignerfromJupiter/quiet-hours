import AppKit
import CoreText

/// The bundled Anybody variable font (SIL OFL 1.1).
enum Fonts {
    /// Variation axis tags as CoreText expects them (four-char codes).
    static let weightAxis = NSNumber(value: 0x7767_6874)  // 'wght'
    static let widthAxis = NSNumber(value: 0x7764_7468)   // 'wdth'

    private static let fontURL: URL? =
        Bundle(for: QuietHoursView.self).url(forResource: "Anybody-Variable", withExtension: "ttf")

    private static var didRegister = false

    /// Registers the font for this process once. Safe to call from every view instance
    /// (the host creates one per display plus one for the thumbnail).
    static func registerOnce() {
        guard !didRegister, let url = fontURL else { return }
        didRegister = true
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            // kCTFontManagerErrorAlreadyRegistered (105) is fine: another instance got there first.
            let code = error.map { CFErrorGetCode($0.takeRetainedValue()) } ?? 0
            if code != 105 { NSLog("QuietHours: font registration failed (\(code))") }
        }
    }

    /// Descriptor built from our file, not looked up by name, so a different Anybody
    /// installed on the Mac can never be picked by mistake.
    private static let baseDescriptor: CTFontDescriptor? = {
        guard let url = fontURL,
              let list = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor]
        else { return nil }
        return list.first
    }()

    /// Anybody at the given size and variation (weight 100–900, width 50–150).
    static func anybody(size: CGFloat, weight: CGFloat, width: CGFloat) -> CTFont {
        guard let base = baseDescriptor else {
            return NSFont.systemFont(ofSize: size, weight: .heavy) as CTFont
        }
        let variation: [NSNumber: NSNumber] = [weightAxis: NSNumber(value: Double(weight)),
                                               widthAxis: NSNumber(value: Double(width))]
        let attrs = [kCTFontVariationAttribute: variation] as CFDictionary
        let desc = CTFontDescriptorCreateCopyWithAttributes(base, attrs)
        return CTFontCreateWithFontDescriptor(desc, size, nil)
    }

    /// Small monospaced label face (the prototype uses Geist Mono 500; SF Mono is the native stand-in).
    static func label(size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
    }
}

import AppKit
import CoreText

/// Bundled fonts (all SIL OFL 1.1): Anybody (variable) and Instrument Serif (regular + italic).
enum Fonts {
    /// Variation axis tags as CoreText expects them (four-char codes).
    static let weightAxis = NSNumber(value: 0x7767_6874)  // 'wght'
    static let widthAxis = NSNumber(value: 0x7764_7468)   // 'wdth'

    private static let files = ["Anybody-Variable", "InstrumentSerif-Regular", "InstrumentSerif-Italic"]

    private static func url(_ name: String) -> URL? {
        Bundle(for: QuietHoursView.self).url(forResource: name, withExtension: "ttf")
    }

    private static var didRegister = false

    /// Registers the fonts for this process once. Safe to call from every view instance
    /// (the host creates one per display plus one for the thumbnail).
    static func registerOnce() {
        guard !didRegister else { return }
        didRegister = true
        for name in files {
            guard let url = url(name) else { NSLog("QuietHours: missing font \(name)"); continue }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // kCTFontManagerErrorAlreadyRegistered (105) is fine: another instance got there first.
                let code = error.map { CFErrorGetCode($0.takeRetainedValue()) } ?? 0
                if code != 105 { NSLog("QuietHours: font registration failed for \(name) (\(code))") }
            }
        }
    }

    /// Descriptors built from our files, not looked up by name, so a different copy installed
    /// on the Mac can never be picked by mistake.
    private static var descriptors: [String: CTFontDescriptor] = [:]
    private static func descriptor(_ name: String) -> CTFontDescriptor? {
        if let d = descriptors[name] { return d }
        guard let url = url(name),
              let list = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let d = list.first else { return nil }
        descriptors[name] = d
        return d
    }

    /// Anybody at the given size and variation (weight 100–900, width 50–150).
    static func anybody(size: CGFloat, weight: CGFloat, width: CGFloat) -> CTFont {
        guard let base = descriptor("Anybody-Variable") else {
            return NSFont.systemFont(ofSize: size, weight: .heavy) as CTFont
        }
        let variation: [NSNumber: NSNumber] = [weightAxis: NSNumber(value: Double(weight)),
                                               widthAxis: NSNumber(value: Double(width))]
        let attrs = [kCTFontVariationAttribute: variation] as CFDictionary
        return CTFontCreateWithFontDescriptor(CTFontDescriptorCreateCopyWithAttributes(base, attrs), size, nil)
    }

    /// Instrument Serif, regular or italic.
    static func instrumentSerif(size: CGFloat, italic: Bool) -> CTFont {
        guard let d = descriptor(italic ? "InstrumentSerif-Italic" : "InstrumentSerif-Regular") else {
            return NSFont(name: italic ? "Georgia-Italic" : "Georgia", size: size) ?? NSFont.systemFont(ofSize: size)
        }
        return CTFontCreateWithFontDescriptor(d, size, nil)
    }

    /// Small monospaced label face (the prototype uses Geist Mono 500; SF Mono is the native stand-in).
    static func label(size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
    }
}

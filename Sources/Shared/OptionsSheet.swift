import AppKit

/// A plain Options sheet (System Settings → Screen Saver → Options…). Phase 5 replaces it with
/// the full panel (live preview, displays, dim); this one lets the real saver switch styles now.
final class OptionsSheet: NSObject {
    let window: NSWindow
    private weak var view: QuietHoursView?
    private let defaults: UserDefaults
    private let fixedStyle: StyleID?

    private let stylePopup = NSPopUpButton()
    private let finishPopup = NSPopUpButton()
    private let hourPopup = NSPopUpButton()
    private let secondsCheck = NSButton(checkboxWithTitle: "Show seconds", target: nil, action: nil)

    private static let hourTitles: [(HourCycle, String)] = [(.system, "System setting"), (.h12, "12-hour"), (.h24, "24-hour")]

    /// `fixedStyle`: each saver bundle is one style, so its sheet has no style picker.
    init(view: QuietHoursView, defaults: UserDefaults, fixedStyle: StyleID? = nil) {
        self.view = view
        self.defaults = defaults
        self.fixedStyle = fixedStyle
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
                          styleMask: [.titled], backing: .buffered, defer: true)
        super.init()
        build()
        load()
    }

    private func build() {
        for id in StyleID.allCases {
            stylePopup.addItem(withTitle: id.displayName)
            stylePopup.lastItem?.representedObject = id.rawValue
        }
        for (_, title) in Self.hourTitles { hourPopup.addItem(withTitle: title) }
        stylePopup.target = self
        stylePopup.action = #selector(styleChanged)

        let grid = NSGridView(views: [
            [label("Style:"), stylePopup],
            [label("Finish:"), finishPopup],
            [label("Time:"), hourPopup],
            [NSGridCell.emptyContentView, secondsCheck],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        if fixedStyle != nil { grid.row(at: 0).isHidden = true }

        let done = NSButton(title: "Done", target: self, action: #selector(done))
        done.keyEquivalent = "\r"
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [cancel, done])
        buttons.spacing = 8

        let note = NSTextField(wrappingLabelWithString: "Auto follows macOS light and dark mode.")
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        note.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [grid, note, buttons])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            note.widthAnchor.constraint(equalTo: grid.widthAnchor),
        ])
    }

    private func label(_ s: String) -> NSTextField { NSTextField(labelWithString: s) }

    private var selectedStyle: StyleID {
        if let fixedStyle { return fixedStyle }
        return (stylePopup.selectedItem?.representedObject as? String).flatMap(StyleID.init(rawValue:)) ?? .hinge
    }

    private var current = Settings()

    /// Reads the stored settings into the controls (every time the sheet opens).
    func load() {
        current = Settings.load(from: defaults)
        if let i = StyleID.allCases.firstIndex(of: fixedStyle ?? current.style) { stylePopup.selectItem(at: i) }
        fillFinishes()
        hourPopup.selectItem(at: Self.hourTitles.firstIndex { $0.0 == current.hourCycle } ?? 0)
        secondsCheck.state = current.showSeconds ? .on : .off
    }

    private func fillFinishes() {
        let style = selectedStyle
        let names = style.finishNames
        finishPopup.removeAllItems()
        finishPopup.addItems(withTitles: ["Auto", names.dark, names.light])
        shownStyle = style
        let choice = current.finish(for: style)
        finishPopup.selectItem(at: FinishChoice.allCases.firstIndex(of: choice) ?? 0)
    }

    private var shownStyle: StyleID?

    @objc private func styleChanged() {
        // Keep the finish picked for the previous style before the list switches.
        if let prev = shownStyle {
            current.finishes[prev] = FinishChoice.allCases[max(0, finishPopup.indexOfSelectedItem)]
        }
        fillFinishes()
    }

    @objc private func done() {
        var s = current
        s.style = selectedStyle
        s.finishes[s.style] = FinishChoice.allCases[max(0, finishPopup.indexOfSelectedItem)]
        s.hourCycle = Self.hourTitles[max(0, hourPopup.indexOfSelectedItem)].0
        s.showSeconds = secondsCheck.state == .on
        s.save(to: defaults)
        close()
        view?.restart()   // the System Settings thumbnail shows the change right away
    }

    @objc private func cancel() { close() }

    private func close() {
        if let parent = window.sheetParent { parent.endSheet(window) } else { window.orderOut(nil) }
    }
}

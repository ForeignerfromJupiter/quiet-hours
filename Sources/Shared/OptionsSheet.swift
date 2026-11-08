import AppKit

/// The Options panel (System Settings → Screen Saver → Options…): a live preview of the saver with
/// the pending choices, then appearance, time format, seconds, Pure black, displays and dim.
/// Nothing is saved until Done.
final class OptionsSheet: NSObject {
    let window: NSWindow
    private weak var view: QuietHoursView?
    private let defaults: UserDefaults
    private let fixedStyle: StyleID?

    private let preview: QuietHoursView?
    private let stylePopup = NSPopUpButton()
    private let finishPopup = NSPopUpButton()
    private let hourPopup = NSPopUpButton()
    private let displaysPopup = NSPopUpButton()
    private let secondsCheck = NSButton(checkboxWithTitle: "Show seconds", target: nil, action: nil)
    private let pureBlackCheck = NSButton(checkboxWithTitle: "Pure black background (OLED)", target: nil, action: nil)
    private let dimSlider = NSSlider(value: 0, minValue: 0, maxValue: 0.6, target: nil, action: nil)
    private let dimValue = NSTextField(labelWithString: "0%")

    private static let hourTitles: [(HourCycle, String)] = [(.system, "System setting"), (.h12, "12-hour"), (.h24, "24-hour")]
    private static let previewSize = NSSize(width: 384, height: 216)

    /// `fixedStyle`: each saver bundle is one style, so its sheet has no style picker.
    init(view: QuietHoursView, defaults: UserDefaults, fixedStyle: StyleID? = nil) {
        self.view = view
        self.defaults = defaults
        self.fixedStyle = fixedStyle
        preview = QuietHoursView(frame: NSRect(origin: .zero, size: Self.previewSize), isPreview: true)
        preview?.followsHostLifecycle = false
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 424, height: 520),
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
        displaysPopup.addItems(withTitles: ["All displays", "Main display only"])
        stylePopup.target = self
        stylePopup.action = #selector(styleChanged)
        for c in [finishPopup, hourPopup, displaysPopup, secondsCheck, pureBlackCheck, dimSlider] as [NSControl] {
            c.target = self
            c.action = #selector(changed)
        }
        dimSlider.isContinuous = true
        dimValue.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        dimValue.textColor = .secondaryLabelColor
        let dimRow = NSStackView(views: [dimSlider, dimValue])
        dimRow.spacing = 8
        dimSlider.widthAnchor.constraint(equalToConstant: 160).isActive = true

        let grid = NSGridView(views: [
            [label("Style:"), stylePopup],
            [label("Appearance:"), finishPopup],
            [label("Time:"), hourPopup],
            [NSGridCell.emptyContentView, secondsCheck],
            [NSGridCell.emptyContentView, pureBlackCheck],
            [label("Displays:"), displaysPopup],
            [label("Dim:"), dimRow],
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

        let note = NSTextField(wrappingLabelWithString:
            "Match system follows macOS light and dark mode as it changes. Pure black applies to the dark look. The clock drifts a few pixels over time to protect OLED screens.")
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        note.textColor = .secondaryLabelColor

        var views: [NSView] = []
        if let preview {
            preview.translatesAutoresizingMaskIntoConstraints = false
            preview.wantsLayer = true
            preview.layer?.cornerRadius = 6
            preview.layer?.masksToBounds = true
            NSLayoutConstraint.activate([
                preview.widthAnchor.constraint(equalToConstant: Self.previewSize.width),
                preview.heightAnchor.constraint(equalToConstant: Self.previewSize.height),
            ])
            views.append(preview)
        }
        views += [grid, note, buttons]
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 16, right: 20)
        stack.setCustomSpacing(18, after: grid)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            note.widthAnchor.constraint(equalToConstant: Self.previewSize.width),
        ])
    }

    private func label(_ s: String) -> NSTextField { NSTextField(labelWithString: s) }

    private var selectedStyle: StyleID {
        if let fixedStyle { return fixedStyle }
        return (stylePopup.selectedItem?.representedObject as? String).flatMap(StyleID.init(rawValue:)) ?? .hinge
    }

    private var current = Settings()
    private var shownStyle: StyleID?

    /// Reads the stored settings into the controls (every time the sheet opens) and starts the preview.
    func load() {
        current = Settings.load(from: defaults)
        if let i = StyleID.allCases.firstIndex(of: fixedStyle ?? current.style) { stylePopup.selectItem(at: i) }
        fillFinishes()
        hourPopup.selectItem(at: Self.hourTitles.firstIndex { $0.0 == current.hourCycle } ?? 0)
        secondsCheck.state = current.showSeconds ? .on : .off
        pureBlackCheck.state = current.pureBlack ? .on : .off
        displaysPopup.selectItem(at: current.allDisplays ? 0 : 1)
        dimSlider.doubleValue = current.dim
        updatePreview()
    }

    private func fillFinishes() {
        let style = selectedStyle
        let names = style.finishNames
        finishPopup.removeAllItems()
        finishPopup.addItems(withTitles: ["Match system", "Always dark (\(names.dark))", "Always light (\(names.light))"])
        shownStyle = style
        finishPopup.selectItem(at: FinishChoice.allCases.firstIndex(of: current.finish(for: style)) ?? 0)
    }

    /// The settings as the controls show them right now.
    private var pending: Settings {
        var s = current
        s.style = selectedStyle
        s.finishes[s.style] = FinishChoice.allCases[max(0, finishPopup.indexOfSelectedItem)]
        s.hourCycle = Self.hourTitles[max(0, hourPopup.indexOfSelectedItem)].0
        s.showSeconds = secondsCheck.state == .on
        s.pureBlack = pureBlackCheck.state == .on
        s.allDisplays = displaysPopup.indexOfSelectedItem == 0
        s.dim = (dimSlider.doubleValue * 20).rounded() / 20      // 5% steps
        return s
    }

    @objc private func styleChanged() {
        // Keep the finish picked for the previous style before the list switches.
        if let prev = shownStyle {
            current.finishes[prev] = FinishChoice.allCases[max(0, finishPopup.indexOfSelectedItem)]
        }
        fillFinishes()
        updatePreview()
    }

    @objc private func changed() { updatePreview() }

    private func updatePreview() {
        dimValue.stringValue = "\(Int((pending.dim * 100).rounded()))%"
        guard let preview else { return }
        preview.overrideSettings = pending
        preview.restart()
    }

    @objc private func done() {
        pending.save(to: defaults)
        current = pending
        close()
        view?.restart()   // the System Settings thumbnail shows the change right away
    }

    @objc private func cancel() { close() }

    private func close() {
        preview?.halt()
        if let parent = window.sheetParent { parent.endSheet(window) } else { window.orderOut(nil) }
    }
}

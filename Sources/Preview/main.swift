import AppKit

let app = NSApplication.shared
let delegate = PreviewAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

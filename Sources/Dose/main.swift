import AppKit

let app = NSApplication.shared
let arguments = CommandLine.arguments
if let flag = arguments.firstIndex(of: "--snapshots"), arguments.indices.contains(flag + 1) {
    app.setActivationPolicy(.prohibited)
    Log.enabled = false
    Snapshots.run(into: URL(fileURLWithPath: arguments[flag + 1]))
    exit(0)
}
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

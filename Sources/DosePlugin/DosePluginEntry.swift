import AppKit
import DoseCore
import NeyKit
import UserNotifications

/// Dose dentro do NeyHub. Linka só DoseCore e NeyKit (nunca NeyKitApp).
final class DoseEntry: NSObject, NeyPlugin {
    private lazy var app = DoseApp(defaults: AppDefaults.forApp("local.dose"), hosted: true, version: Self.version)

    var contractVersion: Int { neyPluginContractVersion }

    func start(host: NeyHost) {
        app.onOpenPermissions = { host.openPermissions() }
        app.start()
    }

    func stop() { app.stop() }
    func setMenuBarVisible(_ visible: Bool) { app.setMenuBarVisible(visible) }
    func makeScreen() -> NSViewController? { app.makeScreen() }
    func makeSettings() -> NSViewController { app.makeSettings() }
    func notificationCategories() -> Set<UNNotificationCategory> { app.notificationCategories() }
    func handleNotification(identifier: String, actionIdentifier: String) { app.handleNotification(identifier: identifier, actionIdentifier: actionIdentifier) }

    /// Versão do manifest.json ao lado do dylib (o release.sh grava nele a do Info.plist).
    private static var version: String {
        var info = Dl_info()
        guard dladdr(#dsohandle, &info) != 0, let path = info.dli_fname else { return "?" }
        let manifest = URL(fileURLWithPath: String(cString: path)).deletingLastPathComponent().appendingPathComponent("manifest.json")
        return (try? JSONDecoder().decode(PluginManifest.self, from: Data(contentsOf: manifest)))?.version ?? "?"
    }
}

@_cdecl("neyhub_plugin_v1") public func neyhubPluginV1() -> UnsafeMutableRawPointer {
    Unmanaged.passRetained(DoseEntry()).toOpaque()
}

import AppKit
import DoseCore
import NeyKit
import UserNotifications

/// Dose dentro do NeyHub. Linka só DoseCore e NeyKit (nunca NeyKitApp).
final class DoseEntry: NSObject, NeyPlugin {
    private lazy var app = DoseApp(defaults: AppDefaults.forApp("local.dose"), hosted: true, version: PluginLocation.version(dso: #dsohandle))

    var contractVersion: Int { neyPluginContractVersion }

    func start(host: NeyHost) {
        app.onOpenPermissions = { host.openPermissions() }
        // Opcional no contrato v1: NeyHub antigo sem showScreen fica no popover.
        if host.responds(to: #selector(NeyHost.showScreen(id:))) {
            app.onShowScreen = { host.showScreen?(id: "local.dose") }
        }
        app.start()
    }

    func stop() { app.stop() }
    func setMenuBarVisible(_ visible: Bool) { app.setMenuBarVisible(visible) }
    func makeScreen() -> NSViewController? { app.makeScreen() }
    func makeSettings() -> NSViewController { app.makeSettings() }
    func notificationCategories() -> Set<UNNotificationCategory> { app.notificationCategories() }
    func handleNotification(identifier: String, actionIdentifier: String) { app.handleNotification(identifier: identifier, actionIdentifier: actionIdentifier) }
}

@_cdecl("neyhub_plugin_v1") public func neyhubPluginV1() -> UnsafeMutableRawPointer {
    Unmanaged.passRetained(DoseEntry()).toOpaque()
}

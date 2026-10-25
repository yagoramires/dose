import AppKit
import DoseCore
import NeyKitApp

/// Casca do avulso: o Dose em si mora no DoseCore, o mesmo que o NeyHub carrega como plugin.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var dose: DoseApp?
    private var updater: Updater?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if HubCheck.isHosted(id: "local.dose") && HubCheck.leaveForHub(id: "local.dose", name: "Dose") { return }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let dose = DoseApp(defaults: .standard, hosted: false, version: version)
        dose.start()
        setupMenu()
        dose.applyPresence(dose.presence)
        self.dose = dose

        let updater = Updater(name: "Dose", repo: "yagoramires/dose", id: "local.dose")
        dose.updateReady = updater.staged != nil
        updater.onChange = { [weak dose, weak updater] in dose?.updateReady = updater?.staged != nil }
        updater.start()
        self.updater = updater
        // Toda abertura: mostra as novidades uma vez e limpa um preparado velho.
        if let notes = Updater.notesAfterUpdate(id: "local.dose", current: version) {
            WhatsNew.show(name: "Dose", version: version, notes: notes)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        _ = updater?.applyStaged()
    }

    /// Clique no Dock (modo Tela) ou aberto de novo pelo Finder: traz a janela de volta.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard let dose, dose.presence.screen else { return true }
        dose.showScreen()
        return false
    }

    /// No modo Tela (com ícone no Dock) o menu do app é o caminho até as configurações sem a pílula.
    private func setupMenu() {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Configurações…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Sair do Dose", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let item = NSMenuItem()
        item.submenu = appMenu
        NSApp.mainMenu = NSMenu()
        NSApp.mainMenu?.addItem(item)
    }

    @objc private func showSettings() { dose?.showSettings() }
}

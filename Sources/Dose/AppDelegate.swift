import AppKit
import Combine
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let store = Store(url: Store.defaultURL)
    private let nav = Nav()
    private lazy var reminders = Reminders(store: store)
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var subscriptions = Set<AnyCancellable>()
    /// Escuta cliques nos outros apps enquanto a janelinha está aberta.
    private var outsideClicks: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)

        let host = NSHostingController(rootView: RootView().environmentObject(store).environmentObject(nav).environmentObject(reminders))
        // A janelinha acompanha o tamanho de cada tela.
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient
        popover.delegate = self

        // Qualquer mudança (dose marcada, item editado, virada do dia) atualiza o ícone e os lembretes.
        store.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] in
                self?.refreshStatusItem()
                self?.reminders.check()
            }
            .store(in: &subscriptions)

        reminders.onOpen = { [weak self] id in self?.open(id.map(Screen.log) ?? .today) }
        reminders.start()

        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.tick() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                          queue: .main) { [weak self] _ in self?.tick() }
        // Lembrete só funciona com o app aberto: na primeira vez já entra nos itens de início.
        if !UserDefaults.standard.bool(forKey: "loginItemOffered") {
            UserDefaults.standard.set(true, forKey: "loginItemOffered")
            do { try SMAppService.mainApp.register() } catch { debugLog("abrir ao iniciar falhou: \(error)") }
        }
        refreshStatusItem()
        tick()
        debugLog("iniciou · \(store.active.count) itens · \(store.intakes.count) doses")
    }

    private func tick() {
        store.now = Date()
        reminders.refreshPermission()
    }

    /// Pílula na barra; com número quando falta alguma coisa hoje.
    private func refreshStatusItem() {
        guard let button = statusItem.button else { return }
        let due = store.due
        button.image = NSImage(systemSymbolName: due.isEmpty ? "pills" : "pills.fill", accessibilityDescription: "Dose")
        button.imagePosition = .imageLeading
        button.title = due.isEmpty ? "" : " \(due.count)"
        button.toolTip = due.isEmpty ? "Dose: tudo em dia" : "Falta: " + due.map(\.name).joined(separator: ", ")
    }

    @objc private func toggle() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            open(.today)
        }
    }

    private func open(_ screen: Screen) {
        nav.screen = screen
        guard let button = statusItem.button else { return }
        tick()
        // App de barra não é ativo: sem isso os campos de texto não recebem teclado.
        NSApp.activate()
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        // O .transient sozinho não fecha quando o clique cai em outro app (o Dose nem sempre fica
        // ativo); um monitor global pega esse clique. Cliques dentro do próprio app não chegam aqui.
        if outsideClicks == nil {
            outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.popover.performClose(nil)
            }
        }
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        outsideClicks = nil
        nav.screen = .today
    }
}

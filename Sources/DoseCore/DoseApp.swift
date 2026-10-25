import AppKit
import Combine
import NeyKit
import ServiceManagement
import SwiftUI
import UserNotifications

/// O Dose inteiro, sem a casca: o avulso (`Dose`) e o plugin do NeyHub (`DosePlugin`) usam o mesmo.
public final class DoseApp: NSObject, NSPopoverDelegate {
    private let defaults: UserDefaults
    /// Dentro do NeyHub: sem item de login, sem "Sair" e sem pedir notificações.
    private let hosted: Bool
    let store: Store
    private let nav = Nav()
    /// Navegação da tela de app, separada da do popover (as duas podem estar abertas).
    let screenNav = Nav()
    let reminders: Reminders
    let shell: Shell
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var subscriptions = Set<AnyCancellable>()
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    /// Escuta cliques nos outros apps enquanto a janelinha está aberta.
    private var outsideClicks: Any?
    private var settingsWindow: NSWindow?
    private var screenWindow: NSWindow?

    /// Hospedado: o NeyHub liga à tela de Permissões dele (a permissão de notificações é do NeyHub).
    public var onOpenPermissions: (() -> Void)? {
        get { reminders.openPermissions }
        set { reminders.openPermissions = newValue }
    }
    /// Hospedado: o NeyHub mostra a tela do Dose (`NeyHost.showScreen`). nil = NeyHub sem esse pedido.
    public var onShowScreen: (() -> Void)?
    /// Avulso: o Updater já preparou uma versão, que entra quando o app fechar.
    public var updateReady = false { didSet { shell.state.updateReady = updateReady } }

    public convenience init(defaults: UserDefaults, hosted: Bool, version: String) {
        self.init(defaults: defaults, hosted: hosted, version: version, storeURL: Store.defaultURL, center: nil)
    }

    /// `storeURL` e `center` só mudam no selftest: arquivo temporário e centro de notificações falso.
    init(defaults: UserDefaults, hosted: Bool, version: String, storeURL: URL, center: Notifier?) {
        self.defaults = defaults
        self.hosted = hosted
        store = Store(url: storeURL)
        reminders = Reminders(store: store, hosted: hosted, center: center)
        shell = Shell(state: PopoverState(version: version, hosted: hosted))
        super.init()
        shell.showSettings = { [weak self] in
            self?.popover.performClose(nil)
            self?.showSettings()
        }
    }

    public func start() {
        // Qualquer mudança (dose marcada, item editado, virada do dia) atualiza o ícone e os lembretes.
        store.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] in
                self?.refreshStatusItem()
                self?.reminders.check()
            }
            .store(in: &subscriptions)

        reminders.onOpen = { [weak self] id in self?.openFromNotification(id) }
        reminders.start()

        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.tick() }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                                         queue: .main) { [weak self] _ in self?.tick() }
        // Lembrete só funciona com o app aberto: na primeira vez já entra nos itens de início. No NeyHub o login é dele.
        if !hosted, !defaults.bool(forKey: "loginItemOffered") {
            defaults.set(true, forKey: "loginItemOffered")
            do { try SMAppService.mainApp.register() } catch { debugLog("abrir ao iniciar falhou: \(error)") }
        }
        refreshStatusItem()
        tick()
        debugLog("iniciou\(hosted ? " no NeyHub" : "") · \(store.active.count) itens · \(store.intakes.count) doses")
    }

    /// Desinstalar no NeyHub: para os lembretes e tira o ícone.
    public func stop() {
        timer?.invalidate()
        timer = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        subscriptions = []
        reminders.onOpen = { _ in }
        reminders.stop()
        setMenuBarVisible(false)
        removeOutsideClicks()
        settingsWindow?.close()
        screenWindow?.close()
        debugLog("parou")
    }

    /// false REMOVE o ícone; true cria com autosaveName "local.dose" (a posição na barra é lembrada).
    public func setMenuBarVisible(_ visible: Bool) {
        if !visible, let statusItem {
            popover.performClose(nil)
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        } else if visible, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = "local.dose"
            item.button?.target = self
            item.button?.action = #selector(toggle)
            statusItem = item
            refreshStatusItem()
        }
    }

    public func makeScreen() -> NSViewController {
        NSHostingController(rootView: ScreenView().environmentObject(store).environmentObject(screenNav)
            .environmentObject(reminders).environmentObject(shell))
    }

    public func makeSettings() -> NSViewController {
        NSHostingController(rootView: SettingsView(
            version: shell.state.version,
            presence: hosted ? nil : presence,
            onPresence: { [weak self] presence in
                guard let self else { return }
                presence.save(defaults)
                applyPresence(presence)
            })
            .environmentObject(reminders))
    }

    public func notificationCategories() -> Set<UNNotificationCategory> { Reminders.categories }

    public func handleNotification(identifier: String, actionIdentifier: String) {
        reminders.handle(identifier: identifier, action: actionIdentifier)
    }

    public static func runSnapshots(into folder: URL) { Snapshots.run(into: folder) }

    // MARK: Avulso

    /// Modo do avulso. Sem escolha salva fica só na barra de menus, como na 0.1.0 (o padrão do NeyKit com tela seria "os dois").
    public var presence: Presence {
        Presence.load(defaults, hasScreen: false).normalized(hasScreen: true)
    }

    /// Avulso: troca o modo na hora, sem reiniciar. Tela = ícone no Dock + janela; barra de menus = a pílula.
    public func applyPresence(_ presence: Presence) {
        setMenuBarVisible(presence.menuBar)
        NSApp.setActivationPolicy(presence.screen ? .regular : .accessory)
        if presence.screen { showScreen() } else { screenWindow?.close() }
    }

    public func showScreen() {
        if screenWindow == nil {
            screenWindow = window(makeScreen(), title: "Dose")
            screenWindow?.setContentSize(NSSize(width: 820, height: 560))
        }
        bringToFront(screenWindow)
    }

    /// Janela de configurações do avulso: Itens e ajustes → Configurações… ou o menu do app no modo Tela.
    public func showSettings() {
        if settingsWindow == nil { settingsWindow = window(makeSettings(), title: "Configurações do Dose") }
        bringToFront(settingsWindow)
    }

    private func window(_ controller: NSViewController, title: String) -> NSWindow {
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func bringToFront(_ window: NSWindow?) {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: Barra de menus

    /// Toque no aviso: hospedado vai para a tela do Dose no NeyHub (a pílula pode estar escondida),
    /// já no registro do item quando é escolher o local. No avulso, o popover, como sempre.
    func openFromNotification(_ id: UUID?) {
        let screen = id.map(Screen.log) ?? .today
        if hosted, let onShowScreen {
            screenNav.screen = screen
            onShowScreen()
        } else {
            open(screen)
        }
    }

    private func tick() {
        store.now = Date()
        reminders.refreshPermission()
    }

    /// Pílula na barra; com número quando falta alguma coisa hoje.
    private func refreshStatusItem() {
        guard let button = statusItem?.button else { return }
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
        guard let button = statusItem?.button else { return }
        if popover.contentViewController == nil {
            let host = NSHostingController(rootView: RootView().environmentObject(store).environmentObject(nav)
                .environmentObject(reminders).environmentObject(shell))
            // A janelinha acompanha o tamanho de cada tela.
            host.sizingOptions = .preferredContentSize
            popover.contentViewController = host
            popover.behavior = .transient
            popover.appearance = NSAppearance(named: .darkAqua)
            popover.delegate = self
        }
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

    public func popoverDidClose(_ notification: Notification) {
        removeOutsideClicks()
        nav.screen = .today
    }

    private func removeOutsideClicks() {
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        outsideClicks = nil
    }
}

/// O que muda no popover entre o avulso e o NeyHub.
struct PopoverState: Equatable {
    var version: String
    var hosted: Bool
    var updateReady = false

    /// Hospedado o login é o do NeyHub.
    var showsLoginItem: Bool { !hosted }
    /// Hospedado fecharia o NeyHub inteiro.
    var showsQuit: Bool { !hosted }
    /// Hospedado as configurações ficam no card do NeyHub.
    var showsSettings: Bool { !hosted }
    /// Hospedado quem atualiza é o NeyHub.
    var showsUpdate: Bool { updateReady && !hosted }
}

/// Ponte entre as telas do popover e a casca.
final class Shell: ObservableObject {
    @Published var state: PopoverState
    var showSettings: () -> Void = {}

    init(state: PopoverState) { self.state = state }
}

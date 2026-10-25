import AppKit
import UserNotifications

/// O pedaço do UNUserNotificationCenter que o Dose usa; o selftest troca por um falso (nunca posta aviso de verdade).
protocol Notifier: AnyObject {
    func setDelegate(_ delegate: UNUserNotificationCenterDelegate)
    func setCategories(_ categories: Set<UNNotificationCategory>)
    func authorization(_ done: @escaping (UNAuthorizationStatus) -> Void)
    func requestAuthorization(_ done: @escaping (Bool, Error?) -> Void)
    func post(_ request: UNNotificationRequest)
    func removeDelivered(_ identifiers: [String])
}

extension UNUserNotificationCenter: Notifier {
    func setDelegate(_ delegate: UNUserNotificationCenterDelegate) { self.delegate = delegate }
    func setCategories(_ categories: Set<UNNotificationCategory>) { setNotificationCategories(categories) }
    func authorization(_ done: @escaping (UNAuthorizationStatus) -> Void) { getNotificationSettings { done($0.authorizationStatus) } }
    func requestAuthorization(_ done: @escaping (Bool, Error?) -> Void) { requestAuthorization(options: [.alert, .sound], completionHandler: done) }
    func post(_ request: UNNotificationRequest) {
        add(request) { error in debugLog("lembrete \(request.content.title)\(error.map { " falhou: \($0)" } ?? "")") }
    }
    func removeDelivered(_ identifiers: [String]) { removeDeliveredNotifications(withIdentifiers: identifiers) }
}

/// Lembretes feitos pelo próprio app em vez de notificações agendadas no sistema: assim só
/// avisa o que ainda falta e para sozinho quando a dose é marcada (por aqui ou pela barra).
final class Reminders: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    /// Enquanto não marcar, avisa de novo a cada 2 h.
    static let nag: TimeInterval = 2 * 60 * 60
    static let snooze: TimeInterval = 30 * 60
    /// Insistências só entre 7 h e 23 h.
    static let quiet = 7..<23
    /// Identificadores de aviso e de categoria: no NeyHub o centro é de todos os plugins e ele roteia por esse prefixo.
    static let prefix = "local.dose."
    static let categories: Set<UNNotificationCategory> = {
        let take = UNNotificationAction(identifier: "take", title: "Tomei")
        let pick = UNNotificationAction(identifier: "pick", title: "Escolher local…", options: .foreground)
        let later = UNNotificationAction(identifier: "snooze", title: "Daqui a 30 min")
        return [
            UNNotificationCategory(identifier: prefix + "dose", actions: [take, later], intentIdentifiers: []),
            UNNotificationCategory(identifier: prefix + "dose-site", actions: [pick, later], intentIdentifiers: []),
        ]
    }()

    private let store: Store
    /// Dentro do NeyHub: ele é o delegate, registra as categorias e pede a permissão.
    private let hosted: Bool
    private let injected: Notifier?
    // Preguiçoso: fora de um .app (modo --snapshots) o sistema derruba o processo ao pedir o center.
    private lazy var center: Notifier = injected ?? UNUserNotificationCenter.current()
    private var nextNag: [UUID: Date] = [:]
    /// Doses já tomadas no ciclo quando olhamos da última vez: mudou, o aviso velho sai da Central.
    private var seenTaken: [UUID: Int] = [:]
    /// Só avisa com permissão; antes disso o aviso se perderia. Começa true pra não piscar o
    /// alerta de "notificações desligadas" enquanto o sistema não responde.
    @Published private(set) var authorized = true
    private var asked = false
    /// Desinstalado no NeyHub: nada mais consulta nem avisa.
    private var stopped = false
    /// Abre a janelinha da barra; com id, já na tela de registrar aquele item.
    var onOpen: (UUID?) -> Void = { _ in }
    /// Hospedado: o "Ligar" vai para a tela de Permissões do NeyHub.
    var openPermissions: (() -> Void)?

    init(store: Store, hosted: Bool = false, center: Notifier? = nil) {
        self.store = store
        self.hosted = hosted
        injected = center
    }

    func start() {
        if !hosted {
            center.setDelegate(self)
            center.setCategories(Self.categories)
        }
        refreshPermission()
    }

    /// Desinstalar no NeyHub: para de avisar. Os avisos na Central ficam: sair do NeyHub também chama stop(), e quem
    /// tira ao desinstalar é o NeyHub.
    func stop() { stopped = true }

    /// Confere a permissão (pode ter mudado nos Ajustes) e, se estiver liberada, os lembretes.
    func refreshPermission() {
        guard !stopped else { return }
        center.authorization { status in
            DispatchQueue.main.async { [self] in
                // Hospedado só consulta: quem pede é a tela de Permissões do NeyHub.
                if status == .notDetermined, !asked, !hosted {
                    asked = true
                    center.requestAuthorization { granted, error in
                        debugLog("pedido de notificações: \(granted ? "permitidas" : "negadas")\(error.map { " (\($0))" } ?? "")")
                        self.refreshPermission()
                    }
                    return
                }
                let allowed = status == .authorized || status == .provisional
                if allowed != authorized { debugLog("notificações \(allowed ? "liberadas" : "desligadas") (status \(status.rawValue))") }
                authorized = allowed
                check()
            }
        }
    }

    /// Abre Ajustes → Notificações já no Dose.
    func openSettings() {
        if let openPermissions { return openPermissions() }
        let id = Bundle.main.bundleIdentifier ?? "local.dose"
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Chamado a cada 30 s e ao acordar o Mac.
    func check() {
        guard authorized, !stopped else { return }
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        for item in store.active {
            guard item.remind, let next = item.times.first, case .pending(let since) = store.status(of: item) else {
                if nextNag[item.id] != nil { clear(item) }
                continue
            }
            let taken = store.taken(item, since: since)
            if seenTaken[item.id] != taken {
                if seenTaken[item.id] != nil { clear(item) }
                seenTaken[item.id] = taken
            }
            let due = (store.nextTime(of: item, since: since) ?? next).on(since)
            guard now >= due, now >= nextNag[item.id] ?? .distantPast else { continue }
            // Na madrugada só sai o aviso do próprio horário marcado, não as insistências.
            if !Self.quiet.contains(hour), now.timeIntervalSince(due) > 60 * 60 { continue }
            post(item, overdue: Format.days(from: since, to: now), dose: taken + 1)
            nextNag[item.id] = now.addingTimeInterval(Self.nag)
        }
    }

    /// Dose marcada: tira a notificação que ficou na Central.
    func clear(_ item: Item) {
        nextNag[item.id] = nil
        // O sem prefixo é aviso da 0.1.0 que ficou na Central.
        center.removeDelivered([Self.prefix + item.id.uuidString, item.id.uuidString])
    }

    private func post(_ item: Item, overdue: Int, dose: Int) {
        let content = UNMutableNotificationContent()
        content.title = item.dose.isEmpty ? item.name : "\(item.name) · \(item.dose)"
        if overdue > 0 {
            content.body = "Atrasado \(overdue) \(overdue == 1 ? "dia" : "dias"). Já tomou?"
        } else if item.tracksSite {
            content.body = "Hora da aplicação. Sugestão: \(store.suggestedSite(for: item).label.lowercased())."
        } else if item.dosesPerDay > 1 {
            content.body = "Hora da \(dose)ª dose de \(item.dosesPerDay)."
        } else {
            content.body = "Hora de tomar."
        }
        content.sound = .default
        content.categoryIdentifier = Self.prefix + (item.tracksSite ? "dose-site" : "dose")
        content.userInfo = ["item": item.id.uuidString]
        // Mesmo identificador: o aviso novo substitui o anterior em vez de empilhar. O da 0.1.0 (sem prefixo) sai.
        center.removeDelivered([item.id.uuidString])
        center.post(UNNotificationRequest(identifier: Self.prefix + item.id.uuidString, content: content, trigger: nil))
    }

    /// Aviso da 0.1.0 que ficou na Central (avulso): o identificador era o uuid puro.
    static func normalized(_ identifier: String) -> String {
        UUID(uuidString: identifier) == nil ? identifier : prefix + identifier
    }

    /// Resposta a um aviso (`local.dose.<uuid>`), venha do próprio delegate (avulso) ou do NeyHub. Sem o prefixo não é do Dose.
    func handle(identifier: String, action: String) {
        guard identifier.hasPrefix(Self.prefix) else { return }
        guard let id = UUID(uuidString: String(identifier.dropFirst(Self.prefix.count))), let item = store.item(id) else { return onOpen(nil) }
        switch action {
        case "take":
            if store.status(of: item).isPending { store.take(item) }
            clear(item)
        case "snooze":
            nextNag[item.id] = Date().addingTimeInterval(Self.snooze)
        case "pick":
            onOpen(item.id)
        default:
            onOpen(item.tracksSite ? item.id : nil)
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = Self.normalized(response.notification.request.identifier), action = response.actionIdentifier
        DispatchQueue.main.async { [self] in
            handle(identifier: identifier, action: action)
            completionHandler()
        }
    }
}

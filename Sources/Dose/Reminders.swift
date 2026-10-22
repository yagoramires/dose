import AppKit
import UserNotifications

/// Lembretes feitos pelo próprio app em vez de notificações agendadas no sistema: assim só
/// avisa o que ainda falta e para sozinho quando a dose é marcada (por aqui ou pela barra).
final class Reminders: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    /// Enquanto não marcar, avisa de novo a cada 2 h.
    static let nag: TimeInterval = 2 * 60 * 60
    static let snooze: TimeInterval = 30 * 60
    /// Insistências só entre 7 h e 23 h.
    static let quiet = 7..<23

    private let store: Store
    private let center = UNUserNotificationCenter.current()
    private var nextNag: [UUID: Date] = [:]
    /// Só avisa com permissão; antes disso o aviso se perderia. Começa true pra não piscar o
    /// alerta de "notificações desligadas" enquanto o sistema não responde.
    @Published private(set) var authorized = true
    private var asked = false
    /// Abre a janelinha da barra; com id, já na tela de registrar aquele item.
    var onOpen: (UUID?) -> Void = { _ in }

    init(store: Store) {
        self.store = store
    }

    func start() {
        center.delegate = self
        let take = UNNotificationAction(identifier: "take", title: "Tomei")
        let pick = UNNotificationAction(identifier: "pick", title: "Escolher local…", options: .foreground)
        let later = UNNotificationAction(identifier: "snooze", title: "Daqui a 30 min")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "dose", actions: [take, later], intentIdentifiers: []),
            UNNotificationCategory(identifier: "dose-site", actions: [pick, later], intentIdentifiers: []),
        ])
        refreshPermission()
    }

    /// Confere a permissão (pode ter mudado nos Ajustes) e, se estiver liberada, os lembretes.
    func refreshPermission() {
        center.getNotificationSettings { settings in
            let status = settings.authorizationStatus
            DispatchQueue.main.async { [self] in
                if status == .notDetermined, !asked {
                    asked = true
                    center.requestAuthorization(options: [.alert, .sound]) { granted, error in
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
        let id = Bundle.main.bundleIdentifier ?? "local.dose"
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Chamado a cada 30 s e ao acordar o Mac.
    func check() {
        guard authorized else { return }
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        for item in store.active {
            guard let reminder = item.reminder, case .pending(let since) = store.status(of: item) else {
                if nextNag[item.id] != nil { clear(item) }
                continue
            }
            let due = reminder.on(since)
            guard now >= due, now >= nextNag[item.id] ?? .distantPast else { continue }
            // Na madrugada só sai o aviso do próprio horário marcado, não as insistências.
            if !Self.quiet.contains(hour), now.timeIntervalSince(due) > 60 * 60 { continue }
            post(item, overdue: Format.days(from: since, to: now))
            nextNag[item.id] = now.addingTimeInterval(Self.nag)
        }
    }

    /// Dose marcada: tira a notificação que ficou na Central.
    func clear(_ item: Item) {
        nextNag[item.id] = nil
        center.removeDeliveredNotifications(withIdentifiers: [item.id.uuidString])
    }

    private func post(_ item: Item, overdue: Int) {
        let content = UNMutableNotificationContent()
        content.title = item.dose.isEmpty ? item.name : "\(item.name) · \(item.dose)"
        if overdue > 0 {
            content.body = "Atrasado \(overdue) \(overdue == 1 ? "dia" : "dias"). Já tomou?"
        } else if item.tracksSite {
            content.body = "Hora da aplicação. Sugestão: \(store.suggestedSite(for: item).label.lowercased())."
        } else {
            content.body = "Hora de tomar."
        }
        content.sound = .default
        content.categoryIdentifier = item.tracksSite ? "dose-site" : "dose"
        content.userInfo = ["item": item.id.uuidString]
        // Mesmo identificador: o aviso novo substitui o anterior em vez de empilhar.
        let request = UNNotificationRequest(identifier: item.id.uuidString, content: content, trigger: nil)
        center.add(request) { error in
            debugLog("lembrete \(item.name)\(error.map { " falhou: \($0)" } ?? "")")
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let raw = response.notification.request.content.userInfo["item"] as? String
        DispatchQueue.main.async { [self] in
            defer { completionHandler() }
            guard let id = raw.flatMap(UUID.init), let item = store.item(id) else { return onOpen(nil) }
            switch response.actionIdentifier {
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
    }
}

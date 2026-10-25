import AppKit
import NeyKit
import UserNotifications

/// `Dose --selftest`. Sem XCTest (só CommandLineTools). Nunca abre o dados.json de verdade, nunca grava no
/// `.standard` (é o domínio do Dose em uso) e nunca posta aviso: o centro de notificações é um falso.
extension DoseApp {
    public static func selfTest() {
        Log.enabled = false
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dose-selftest-\(UUID())")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        storeLoads(folder)
        hostedLeavesLoginItem(folder)
        reminders(folder)
        routing(folder)
        hostedTap(folder)
        popover(folder)
        days(folder)
    }

    /// Suite temporária no lugar do `.standard`; o chamador apaga. Nome fixo: não junta um plist por rodada.
    /// `UserDefaults(suiteName:)` direto só aqui: o app usa `AppDefaults.forApp`; o teste quer um domínio descartável.
    private static func tempDefaults() -> (UserDefaults, String) {
        let name = "dose.selftest"
        return (UserDefaults(suiteName: name)!, name)
    }

    /// As respostas do centro falso chegam por DispatchQueue.main.
    private static func spin() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }

    /// Item diário vencido agora (o horário é o minuto atual): sempre dá aviso, a qualquer hora do dia.
    private static func dueNow() -> Item {
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return Item(name: "Teste", dose: "1 cápsula", schedule: .daily, times: [Clock(hour: now.hour!, minute: now.minute!)])
    }

    /// Um dados.json de exemplo (com um item no formato da v0.1) abre inteiro, sem virar cópia "ilegível".
    static func storeLoads(_ folder: URL) {
        let url = folder.appendingPathComponent("dados.json")
        let first = UUID()
        let json = """
        {"items":[
          {"id":"\(first)","name":"Vitamina C","dose":"5 g","schedule":{"daily":{}},"times":[{"hour":9,"minute":0}],"tint":"teal","created":"2026-10-01T12:00:00Z"},
          {"id":"\(UUID())","name":"Medicação semanal","schedule":{"weekly":{"weekday":7}},"reminder":{"hour":9,"minute":0}},
          {"id":"\(UUID())","name":"comer doce","dose":"","schedule":{"counter":{}},"tint":"blue","archived":true}
        ],
        "intakes":[{"id":"\(UUID())","itemID":"\(first)","date":"2026-10-20T11:00:00Z"}]}
        """
        try! Data(json.utf8).write(to: url)
        let store = Store(url: url)
        precondition(store.items.count == 3 && store.active.count == 2 && store.intakes.count == 1, "\(store.items)")
        precondition(store.items[1].schedule == .weekdays([7]) && store.items[1].times == [Clock(hour: 9, minute: 0)])
        let files = try! FileManager.default.contentsOfDirectory(atPath: folder.path)
        precondition(files == ["dados.json"], "\(files)")
    }

    /// Hospedado: o login é o do NeyHub. Não grava `loginItemOffered` (nem no defaults injetado nem no `.standard`)
    /// e não pede notificação, nem vira delegate, nem registra categorias (é o NeyHub que faz).
    static func hostedLeavesLoginItem(_ folder: URL) {
        let (d, name) = tempDefaults()
        defer { d.removePersistentDomain(forName: name) }
        let before = UserDefaults.standard.object(forKey: "loginItemOffered") as? Bool
        let center = FakeNotifier(status: .notDetermined)
        let app = DoseApp(defaults: d, hosted: true, version: "9.8.7", storeURL: folder.appendingPathComponent("login.json"), center: center)
        let item = dueNow()
        app.store.upsert(item)
        app.start()
        spin()
        app.stop()
        precondition(d.object(forKey: "loginItemOffered") == nil, "hospedado gravou loginItemOffered")
        precondition(UserDefaults.standard.object(forKey: "loginItemOffered") as? Bool == before, "mexeu no .standard")
        precondition(center.calls.isEmpty && center.posted.isEmpty, "\(center.calls)")
        // Desinstalado: os avisos do Dose saem da Central e nada mais é avisado, mesmo com permissão.
        precondition(center.removed.contains("local.dose.\(item.id)"), "\(center.removed)")
        center.status = .authorized
        app.reminders.refreshPermission()
        app.reminders.check()
        spin()
        precondition(center.posted.isEmpty, "avisou depois do stop()")
    }

    /// Avulso: delegate, categorias e um pedido só. Aviso com identificador e categoria `local.dose.`.
    static func reminders(_ folder: URL) {
        let store = Store(url: folder.appendingPathComponent("lembretes.json"))
        let item = dueNow()
        store.upsert(item)
        let center = FakeNotifier(status: .notDetermined)
        let alone = Reminders(store: store, hosted: false, center: center)
        alone.start()
        spin()
        alone.refreshPermission()
        spin()
        precondition(center.calls == ["delegate", "categories", "request"], "\(center.calls)")

        center.status = .authorized
        alone.refreshPermission()
        spin()
        precondition(center.posted.map(\.identifier) == ["local.dose.\(item.id)"], "\(center.posted)")
        precondition(center.posted[0].content.categoryIdentifier == "local.dose.dose")
        precondition(center.removed.contains(item.id.uuidString), "aviso da 0.1.0 ficou na Central")
        precondition(Reminders.normalized("\(item.id)") == "local.dose.\(item.id)")
        precondition(Reminders.normalized("local.dose.\(item.id)") == "local.dose.\(item.id)" && Reminders.normalized("x") == "x")
        precondition(Set(Reminders.categories.map(\.identifier)) == ["local.dose.dose", "local.dose.dose-site"])
        precondition(Reminders.categories.allSatisfy { !$0.actions.isEmpty })

        // Hospedado o aviso sai igual (pelo centro do NeyHub), mas sem pedido nem delegate.
        let hostedCenter = FakeNotifier(status: .notDetermined)
        let hosted = Reminders(store: store, hosted: true, center: hostedCenter)
        hosted.start()
        spin()
        precondition(hostedCenter.calls.isEmpty && !hosted.authorized)
        hostedCenter.status = .authorized
        hosted.refreshPermission()
        spin()
        precondition(hostedCenter.posted.map(\.identifier) == ["local.dose.\(item.id)"] && hostedCenter.calls.isEmpty)
    }

    /// O NeyHub entrega `local.dose.<uuid>`; sem o prefixo (ou de outro plugin) não é do Dose.
    static func routing(_ folder: URL) {
        let (d, name) = tempDefaults()
        defer { d.removePersistentDomain(forName: name) }
        let app = DoseApp(defaults: d, hosted: true, version: "9.8.7", storeURL: folder.appendingPathComponent("rotas.json"),
                          center: FakeNotifier(status: .authorized))
        let item = dueNow()
        app.store.upsert(item)
        var opened: [UUID?] = []
        app.reminders.onOpen = { opened.append($0) }
        for ignored in ["\(item.id)", "local.dosex.\(item.id)", "local.aero.\(item.id)", "local.dose"] {
            app.handleNotification(identifier: ignored, actionIdentifier: "take")
        }
        precondition(app.store.intakes.isEmpty && opened.isEmpty, "tratou aviso que não é do Dose")
        // Do Dose, mas de um item que não existe mais: só abre o popover, como antes.
        app.handleNotification(identifier: "local.dose.\(UUID())", actionIdentifier: "take")
        precondition(app.store.intakes.isEmpty && opened == [nil])
        app.handleNotification(identifier: "local.dose.\(item.id)", actionIdentifier: "take")
        precondition(app.store.intakes.map(\.itemID) == [item.id])
        app.handleNotification(identifier: "local.dose.\(item.id)", actionIdentifier: UNNotificationDefaultActionIdentifier)
        precondition(app.store.intakes.count == 1 && opened == [nil, nil], "\(opened)")
        precondition(Set(app.notificationCategories().map(\.identifier)) == Set(Reminders.categories.map(\.identifier)))
    }

    /// Hospedado com `showScreen` no NeyHub: o toque leva à tela do Dose; "Escolher local…" já no registro do item.
    static func hostedTap(_ folder: URL) {
        let (d, name) = tempDefaults()
        defer { d.removePersistentDomain(forName: name) }
        let app = DoseApp(defaults: d, hosted: true, version: "9.8.7", storeURL: folder.appendingPathComponent("toque.json"),
                          center: FakeNotifier(status: .notDetermined))
        var item = dueNow()
        item.tracksSite = true
        app.store.upsert(item)
        var shown = 0
        app.onShowScreen = { shown += 1 }
        app.start()
        Presence(screen: true, menuBar: false).save(d)
        app.screenNav.screen = .history
        app.handleNotification(identifier: "local.dose.\(item.id)", actionIdentifier: "pick")
        precondition(shown == 1 && app.screenNav.screen == .log(item.id), "\(app.screenNav.screen)")
        app.handleNotification(identifier: "local.dose.\(UUID())", actionIdentifier: UNNotificationDefaultActionIdentifier)
        precondition(shown == 2 && app.screenNav.screen == .today)
        // Só barra de menus (a escolha no NeyHub): o popover, já no registro do item; a tela não muda.
        Presence(screen: false, menuBar: true).save(d)
        app.handleNotification(identifier: "local.dose.\(item.id)", actionIdentifier: "pick")
        precondition(shown == 2 && app.screenNav.screen == .today && app.nav.screen == .log(item.id), "\(app.nav.screen)")
        // Os dois desligados: o NeyHub normaliza para barra de menus (a pílula aparece), então também é o popover.
        Presence(screen: false, menuBar: false).save(d)
        app.nav.screen = .today
        app.handleNotification(identifier: "local.dose.\(item.id)", actionIdentifier: "pick")
        precondition(shown == 2 && app.nav.screen == .log(item.id))
        // NeyHub sem showScreen: cai no popover e não mexe na tela.
        Presence(screen: true, menuBar: true).save(d)
        app.onShowScreen = nil
        app.nav.screen = .today
        app.handleNotification(identifier: "local.dose.\(item.id)", actionIdentifier: "pick")
        precondition(shown == 2 && app.screenNav.screen == .today && app.nav.screen == .log(item.id))
        app.stop()
    }

    /// Grade da tela de app (completo, parcial, esquecido) e o "em 3 h" da agenda.
    static func days(_ folder: URL) {
        let calendar = Calendar.current
        let store = Store(url: folder.appendingPathComponent("grade.json"))
        let today = calendar.startOfDay(for: store.now)
        func day(_ n: Int, _ hour: Int = 10) -> Date { calendar.date(byAdding: .hour, value: hour, to: calendar.date(byAdding: .day, value: -n, to: today)!)! }
        var daily = Item(name: "Duas doses", dose: "", schedule: .daily, times: [Clock(hour: 8, minute: 0), Clock(hour: 20, minute: 0)])
        daily.created = day(5, 0)
        store.upsert(daily)
        store.take(daily, at: day(1, 8)); store.take(daily, at: day(1, 20))
        store.take(daily, at: day(2, 8))
        precondition(store.mark(of: daily, on: day(1)) == .done && store.mark(of: daily, on: day(2)) == .partial)
        precondition(store.mark(of: daily, on: day(3)) == .missed, "dia sem dose não ficou esquecido")
        precondition(store.mark(of: daily, on: day(0)) == .none, "hoje ainda dá tempo")
        precondition(store.mark(of: daily, on: day(6)) == .none, "antes de criar o item")
        let weekday = calendar.component(.weekday, from: day(3))
        var weekly = Item(name: "Semanal", dose: "", schedule: .weekdays([weekday]), times: [Clock(hour: 9, minute: 0)])
        weekly.created = day(30, 0)
        store.upsert(weekly)
        precondition(store.mark(of: weekly, on: day(3)) == .missed && store.mark(of: weekly, on: day(2)) == .none)
        store.take(weekly, at: day(4))
        precondition(store.mark(of: weekly, on: day(3)) == .none && store.mark(of: weekly, on: day(4)) == .done, "véspera vale")
        var every = Item(name: "A cada 3", dose: "", schedule: .interval(days: 3))
        every.created = day(30, 0)
        store.upsert(every)
        precondition(store.mark(of: every, on: day(2)) == .none)
        let now = Date()
        precondition(Format.until(now.addingTimeInterval(20 * 60 - 1), now: now) == "em 20 min")
        precondition(Format.until(now.addingTimeInterval(160 * 60), now: now) == "em 3 h")
        precondition(Format.until(now.addingTimeInterval(10), now: now) == "em 1 min")
    }

    /// Hospedado: sem "Abrir ao iniciar", sem "Sair" (fecharia o NeyHub), sem Configurações… e sem linha de atualização.
    static func popover(_ folder: URL) {
        func state(hosted: Bool) -> PopoverState {
            let (d, name) = tempDefaults()
            defer { d.removePersistentDomain(forName: name) }
            let app = DoseApp(defaults: d, hosted: hosted, version: "9.8.7",
                              storeURL: folder.appendingPathComponent("popover-\(hosted).json"), center: FakeNotifier(status: .authorized))
            app.updateReady = true
            return app.shell.state
        }
        let hosted = state(hosted: true), alone = state(hosted: false)
        precondition(!hosted.showsLoginItem && !hosted.showsQuit && !hosted.showsSettings && !hosted.showsUpdate, "\(hosted)")
        precondition(alone.showsLoginItem && alone.showsQuit && alone.showsSettings && alone.showsUpdate, "\(alone)")
        precondition(hosted.version == "9.8.7" && alone.version == "9.8.7")

        // Avulso sem escolha salva: só barra de menus, como na 0.1.0. Escolha salva vale.
        let (d, name) = tempDefaults()
        defer { d.removePersistentDomain(forName: name) }
        let app = DoseApp(defaults: d, hosted: false, version: "9.8.7", storeURL: folder.appendingPathComponent("modo.json"),
                          center: FakeNotifier(status: .authorized))
        precondition(app.presence == Presence(screen: false, menuBar: true))
        Presence(screen: true, menuBar: false).save(d)
        precondition(app.presence == Presence(screen: true, menuBar: false))
        Presence(screen: false, menuBar: false).save(d)
        precondition(app.presence == Presence(screen: false, menuBar: true))
    }
}

/// Centro de notificações falso: anota o que o Dose pediu, nada chega ao sistema.
final class FakeNotifier: Notifier {
    var status: UNAuthorizationStatus
    var calls: [String] = []
    var posted: [UNNotificationRequest] = []
    var removed: [String] = []

    init(status: UNAuthorizationStatus) { self.status = status }

    func setDelegate(_ delegate: UNUserNotificationCenterDelegate) { calls.append("delegate") }
    func setCategories(_ categories: Set<UNNotificationCategory>) { calls.append("categories") }
    func authorization(_ done: @escaping (UNAuthorizationStatus) -> Void) { done(status) }
    func requestAuthorization(_ done: @escaping (Bool, Error?) -> Void) { calls.append("request") }
    func post(_ request: UNNotificationRequest) { posted.append(request) }
    func removeDelivered(_ identifiers: [String]) { removed += identifiers }
}

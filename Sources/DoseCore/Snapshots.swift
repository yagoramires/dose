import AppKit
import NeyKit
import SwiftUI

/// `Dose --snapshots <pasta>`: desenha cada tela com dados de exemplo em PNG e sai.
/// Serve pra conferir o visual sem abrir a janelinha na tela de ninguém; usa um arquivo de dados
/// temporário, nunca o de verdade.
enum Snapshots {
    static func run(into folder: URL) {
        Log.enabled = false
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("dose-snapshots-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = Store(url: file)
        store.items = Item.samples
        store.items[0].times = [Clock(hour: 8, minute: 0), Clock(hour: 20, minute: 0)]
        let calendar = Calendar.current
        let now = Date()
        func ago(_ days: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0,
                          of: calendar.date(byAdding: .day, value: -days, to: now)!)!
        }
        for index in store.items.indices { store.items[index].created = ago(40, 0) }
        let vitaminaC = store.items[0], multi = store.items[1], semanal = store.items[2], cha = store.items[3]
        for day in 1...9 { store.take(vitaminaC, at: ago(day, 8, 10)) }
        store.take(vitaminaC, at: ago(0, 8, 12))
        store.take(multi, at: ago(1, 9, 3))
        // Semana com de tudo na grade da tela: completo, parcial (C tem duas doses) e esquecido.
        for day in [2, 3, 5, 6, 7, 8, 10, 11, 12, 13] { store.take(multi, at: ago(day, 9, 5)) }
        for day in [1, 3, 4, 6, 7, 9] { store.take(vitaminaC, at: ago(day, 20, 5)) }
        let sites: [Site] = [.armLeft, .armRight, .abdomenLeft]
        for (week, site) in sites.enumerated() { store.take(semanal, at: ago(5 + 7 * (sites.count - 1 - week), 9), site: site) }
        store.take(cha, at: ago(0, 7, 40))
        store.take(cha, at: ago(0, 13, 15))
        let doce = store.items[5]
        store.take(doce, at: ago(30, 20))
        store.take(doce, at: ago(12, 21))
        var fastFood = Item(name: "fast food", dose: "", schedule: .counter, tint: .green)
        fastFood.created = ago(19, 0)
        store.upsert(fastFood)
        var soda = Item(name: "beber refrigerante", dose: "", schedule: .counter, tint: .orange)
        soda.created = ago(40, 0)
        store.upsert(soda)
        for day in [25, 16, 14, 3] { store.take(soda, at: ago(day, 15)) }

        var omega = Item(name: "Ômega 3", dose: "2 cápsulas", schedule: .interval(days: 3), times: [Clock(hour: 20, minute: 0)],
                         tint: .yellow)
        omega.created = ago(40, 0)
        store.upsert(omega)
        store.take(omega, at: ago(3, 20, 5))
        var gym = Item(name: "Alongamento", dose: "1 dose", schedule: .weekdays([2, 4, 6]), times: [Clock(hour: 18, minute: 0)],
                       tint: .green)
        gym.created = ago(40, 0)
        store.upsert(gym)

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let nav = Nav()
        let screens: [(String, Screen)] = [
            ("1-hoje", .today), ("8-novo-contador", .newCounter), ("2-semanal", .log(semanal.id)), ("3-historico", .history),
            ("4-itens", .items), ("5-editar", .edit(semanal)), ("6-novo-item", .edit(nil)), ("9-editar-dias", .edit(gym)), ("10-editar-intervalo", .edit(omega)), ("7-zerar", .log(doce.id)),
        ]
        let emptyFile = FileManager.default.temporaryDirectory.appendingPathComponent("dose-snapshots-vazio-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: emptyFile) }
        let empty = Store(url: emptyFile)
        let alone = Shell(state: PopoverState(version: "0.2.0", hosted: false, updateReady: true))
        render(RootView().environmentObject(empty).environmentObject(Nav()).environmentObject(Reminders(store: empty))
            .environmentObject(alone), to: folder.appendingPathComponent("0-vazio.png"))
        for (name, screen) in screens {
            nav.screen = screen
            render(RootView().environmentObject(store).environmentObject(nav).environmentObject(Reminders(store: store))
                .environmentObject(alone), to: folder.appendingPathComponent("\(name).png"))
        }
        // Dentro do NeyHub: sem login, Sair, Configurações… nem linha de atualização.
        nav.screen = .items
        render(RootView().environmentObject(store).environmentObject(nav).environmentObject(Reminders(store: store))
            .environmentObject(Shell(state: PopoverState(version: "0.2.0", hosted: true))), to: folder.appendingPathComponent("4-itens-neyhub.png"))
        // Notificações negadas, pelo centro falso do selftest: nada chega ao sistema.
        let off = Reminders(store: store, hosted: true, center: FakeNotifier(status: .denied))
        off.refreshPermission()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        nav.screen = .today
        render(RootView().environmentObject(store).environmentObject(nav).environmentObject(off).environmentObject(alone),
               to: folder.appendingPathComponent("1-hoje-sem-notificacoes.png"))
        render(SettingsView(version: "0.2.0", presence: Presence(screen: false, menuBar: true), onPresence: { _ in })
            .environmentObject(Reminders(store: store)), to: folder.appendingPathComponent("settings.png"))
        render(SettingsView(version: "0.2.0", presence: nil, onPresence: { _ in }).environmentObject(off),
               to: folder.appendingPathComponent("settings-neyhub.png"))
        // Tela de app no tamanho da área do NeyHub com a janela no padrão; a estreita confere o empilhar das colunas.
        let screenNav = Nav()
        for (name, screen, width) in [("screen", Screen.today, 790.0), ("screen-historico", .history, 790), ("screen-itens", .edit(semanal), 790),
                                      ("screen-estreita", .today, 520), ("screen-neyhub", .today, 898)] {
            screenNav.screen = screen
            render(ScreenView().environmentObject(store).environmentObject(screenNav).environmentObject(Reminders(store: store))
                .environmentObject(alone).frame(width: width, height: width == 898 ? 580 : 560), to: folder.appendingPathComponent("\(name).png"))
        }
        print("✓ \(folder.path)")
    }

    /// Desenha a tela numa janela fora da vista e grava o PNG.
    private static func render(_ root: some View, to file: URL) {
        let view = NSHostingView(rootView: root)
        view.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: view.fittingSize),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        window.setContentSize(view.fittingSize)
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: file)
    }
}

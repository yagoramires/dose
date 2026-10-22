import AppKit
import SwiftUI

/// `Dose --snapshots <pasta>`: desenha cada tela com dados de exemplo em PNG e sai.
/// Serve pra conferir o visual sem abrir a janelinha na tela de ninguém; usa um arquivo de dados
/// temporário, nunca o de verdade.
enum Snapshots {
    static func run(into folder: URL) {
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
        let sites: [Site] = [.abdomenLeft, .abdomenRight, .thighLeft]
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
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            render(RootView().environmentObject(empty).environmentObject(Nav()).environmentObject(Reminders(store: empty)),
                   appearance: appearance, to: folder.appendingPathComponent("0-vazio\(appearance == .aqua ? "" : "-escuro").png"))
        }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for (name, screen) in screens {
                nav.screen = screen
                let suffix = appearance == .aqua ? "" : "-escuro"
                render(RootView().environmentObject(store).environmentObject(nav).environmentObject(Reminders(store: store)),
                       appearance: appearance, to: folder.appendingPathComponent("\(name)\(suffix).png"))
            }
        }
        print("✓ \(folder.path)")
    }

    /// Desenha a tela numa janela fora da vista e grava o PNG.
    private static func render(_ root: some View, appearance: NSAppearance.Name, to file: URL) {
        let view = NSHostingView(rootView: root.background(Color(nsColor: .windowBackgroundColor)))
        view.appearance = NSAppearance(named: appearance)
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

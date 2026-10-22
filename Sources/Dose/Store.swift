import Foundation

/// Itens e doses tomadas, salvos num JSON em ~/Library/Application Support/Dose.
final class Store: ObservableObject {
    static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Dose/dados.json")

    @Published var items: [Item] { didSet { save() } }
    /// Sempre em ordem de data, da mais antiga pra mais recente.
    @Published private(set) var intakes: [Intake] { didSet { save() } }
    /// Relógio que as telas observam: muda a cada minuto pra virar o dia e os atrasos sozinho.
    @Published var now = Date()

    private let url: URL
    private struct Snapshot: Codable {
        var items: [Item]
        var intakes: [Intake]
    }

    init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let snapshot = try? JSONDecoder.dose.decode(Snapshot.self, from: data) {
            items = snapshot.items
            intakes = snapshot.intakes.sorted { $0.date < $1.date }
        } else {
            // Arquivo existe mas não abriu: guarda uma cópia antes de recomeçar, pra não perder o histórico.
            if FileManager.default.fileExists(atPath: url.path) {
                let copy = url.deletingPathExtension().appendingPathExtension("ilegivel-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.copyItem(at: url, to: copy)
                debugLog("dados.json ilegível, cópia em \(copy.lastPathComponent)")
            }
            items = Item.examples
            intakes = []
            save()
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.dose.encode(Snapshot(items: items, intakes: intakes))
            try data.write(to: url, options: .atomic)
        } catch {
            debugLog("falhou ao salvar: \(error)")
        }
    }

    var active: [Item] { items.filter { !$0.archived } }

    func item(_ id: UUID) -> Item? { items.first { $0.id == id } }

    // MARK: Registro

    func take(_ item: Item, at date: Date = Date(), site: Site? = nil) {
        intakes.append(Intake(itemID: item.id, date: date, site: site))
        intakes.sort { $0.date < $1.date }
        debugLog("tomou \(item.name) em \(date)\(site.map { " · \($0.rawValue)" } ?? "")")
    }

    func delete(_ intake: Intake) {
        intakes.removeAll { $0.id == intake.id }
        debugLog("apagou dose de \(item(intake.itemID)?.name ?? "?") em \(intake.date)")
    }

    func upsert(_ item: Item) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
    }

    func archive(_ item: Item) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].archived = true
    }

    // MARK: Consultas

    func intakes(of item: Item) -> [Intake] { intakes.filter { $0.itemID == item.id } }

    func last(_ item: Item) -> Intake? { intakes.last { $0.itemID == item.id } }

    func status(of item: Item) -> Status {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let last = last(item)

        switch item.schedule {
        case .daily:
            if let last, last.date >= today { return .done(last) }
            return .pending(since: today)

        case .weekdays(let days):
            guard !days.isEmpty else { return .later(next: .distantFuture, last: last) }
            let todayWeekday = calendar.component(.weekday, from: today)
            // Último dia marcado até hoje (o ciclo atual) e o próximo depois de hoje.
            let back = days.map { (todayWeekday - $0 + 7) % 7 }.min()!
            let ahead = days.map { ($0 - todayWeekday + 6) % 7 + 1 }.min()!
            let cycle = calendar.date(byAdding: .day, value: -back, to: today)!
            let next = calendar.date(byAdding: .day, value: ahead, to: today)!
            // Uma vez por semana: tomar um dia antes também vale (ex.: viagem no dia da aplicação).
            let early = days.count == 1 ? calendar.date(byAdding: .day, value: -1, to: cycle)! : cycle
            if let last, last.date >= early {
                return last.date >= today ? .done(last) : .later(next: next, last: last)
            }
            if cycle < calendar.startOfDay(for: item.created) { return .later(next: next, last: last) }
            return .pending(since: cycle)

        case .interval(let every):
            if let last, last.date >= today { return .done(last) }
            // Sem dose ainda: vale desde que o item foi criado.
            guard let last else { return .pending(since: max(calendar.startOfDay(for: item.created), today)) }
            let due = calendar.date(byAdding: .day, value: max(1, every), to: calendar.startOfDay(for: last.date))!
            return due <= today ? .pending(since: due) : .later(next: due, last: last)

        case .asNeeded:
            return .asNeeded(today: intakes(of: item).filter { $0.date >= today })

        case .counter:
            return .counter(since: last?.date ?? item.created)
        }
    }

    /// Contador: o maior intervalo, em dias, entre duas vezes (contando o atual).
    func record(of item: Item) -> Int {
        let dates = intakes(of: item).map(\.date)
        let start = min(item.created, dates.first ?? item.created)
        var best = 0
        for (from, to) in zip([start] + dates, dates + [now]) {
            best = max(best, Format.days(from: from, to: to))
        }
        return best
    }

    /// Itens que ainda faltam: o número que aparece na barra de menus.
    var due: [Item] { active.filter { status(of: $0).isPending } }

    /// Último uso de cada local por este item.
    func lastUse(of item: Item) -> [Site: Date] {
        var result: [Site: Date] = [:]
        for intake in intakes(of: item) {
            if let site = intake.site { result[site] = intake.date }
        }
        return result
    }

    /// Rodízio: o local usado há mais tempo (os nunca usados primeiro, na ordem de Site).
    func suggestedSite(for item: Item) -> Site {
        let used = lastUse(of: item)
        return Site.allCases.min { (used[$0] ?? .distantPast) < (used[$1] ?? .distantPast) } ?? .abdomenLeft
    }

    /// Dias seguidos com dose, contando até hoje (ou até ontem, se hoje ainda falta).
    func streak(of item: Item) -> Int {
        let calendar = Calendar.current
        let days = Set(intakes(of: item).map { calendar.startOfDay(for: $0.date) })
        var day = calendar.startOfDay(for: now)
        if !days.contains(day) { day = calendar.date(byAdding: .day, value: -1, to: day)! }
        var count = 0
        while days.contains(day) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }
}

extension JSONEncoder {
    static let dose: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

extension JSONDecoder {
    static let dose: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

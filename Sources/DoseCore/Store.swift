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

    /// Formato que esta versão grava; arquivo sem `schema` é o da 0.1.0 (= 1).
    static let schema = 1
    /// Aviso de só leitura (dados de uma versão mais nova, ou ilegíveis): nada é gravado por cima.
    @Published private(set) var readOnly: String?

    private let url: URL
    private struct Snapshot: Codable {
        var schema: Int?
        var items: [Item]
        var intakes: [Intake]
    }
    private struct Header: Decodable { var schema: Int? }

    init(url: URL) {
        self.url = url
        guard FileManager.default.fileExists(atPath: url.path) else {
            // Começa vazio: cada um adiciona e configura o que toma.
            items = []
            intakes = []
            save()
            return
        }
        let data = try? Data(contentsOf: url)
        let schema = data.flatMap { try? JSONDecoder().decode(Header.self, from: $0) }.map { $0.schema ?? 1 }
        let snapshot = data.flatMap { try? JSONDecoder.dose.decode(Snapshot.self, from: $0) }
        items = snapshot?.items ?? []
        intakes = (snapshot?.intakes ?? []).sorted { $0.date < $1.date }
        if let schema, schema > Self.schema {
            readOnly = "Dados de uma versão mais nova do Dose — atualize"
            debugLog("dados.json schema \(schema) (este lê até \(Self.schema)): só leitura")
        } else if snapshot == nil {
            // Não abriu: guarda uma cópia (uma só por conteúdo) e não grava um vazio por cima, pra não perder o histórico.
            let copy = Self.unreadableCopy(of: url, data: data)
            readOnly = "Não deu pra ler os dados do Dose — nada é salvo (cópia em \(copy.lastPathComponent))"
            debugLog("dados.json ilegível, cópia em \(copy.lastPathComponent): só leitura")
        }
    }

    /// Cópia `<nome>.ilegivel-<ts>.json`; se já há uma com os mesmos bytes, devolve essa em vez de criar outra a cada abertura.
    private static func unreadableCopy(of url: URL, data: Data?) -> URL {
        let fm = FileManager.default, dir = url.deletingLastPathComponent()
        let prefix = url.deletingPathExtension().lastPathComponent + ".ilegivel-"
        let existing = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
            .filter { $0.hasPrefix(prefix) && $0.hasSuffix(".json") }.map { dir.appendingPathComponent($0) }
        if let data, let same = existing.first(where: { fm.contents(atPath: $0.path) == data }) { return same }
        let copy = url.deletingPathExtension().appendingPathExtension("ilegivel-\(Int(Date().timeIntervalSince1970)).json")
        try? fm.copyItem(at: url, to: copy)
        return copy
    }

    private func save() {
        guard readOnly == nil else { return debugLog("só leitura: não salvou") }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.dose.encode(Snapshot(schema: Self.schema, items: items, intakes: intakes))
            try data.write(to: url, options: .atomic)
        } catch {
            debugLog("falhou ao salvar: \(error)")
        }
    }

    var active: [Item] { items.filter { !$0.archived } }
    /// Itens com dia certo pra tomar.
    var scheduled: [Item] { active.filter { $0.schedule.isScheduled } }
    var asNeeded: [Item] { active.filter { $0.schedule == .asNeeded } }
    var counters: [Item] { active.filter { $0.schedule == .counter } }

    func item(_ id: UUID) -> Item? { items.first { $0.id == id } }

    // MARK: Registro

    /// Só leitura recusa já aqui, não só no save(): um "Tomei" só em memória pararia os lembretes e sumiria ao reabrir.
    private func canWrite() -> Bool {
        if readOnly != nil { debugLog("só leitura: ignorou a mudança") }
        return readOnly == nil
    }

    func take(_ item: Item, at date: Date = Date(), site: Site? = nil) {
        guard canWrite() else { return }
        intakes.append(Intake(itemID: item.id, date: date, site: site))
        intakes.sort { $0.date < $1.date }
        debugLog("tomou \(item.name) em \(date)\(site.map { " · \($0.rawValue)" } ?? "")")
    }

    func delete(_ intake: Intake) {
        guard canWrite() else { return }
        intakes.removeAll { $0.id == intake.id }
        debugLog("apagou dose de \(item(intake.itemID)?.name ?? "?") em \(intake.date)")
    }

    func upsert(_ item: Item) {
        guard canWrite() else { return }
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
    }

    func archive(_ item: Item) {
        guard canWrite() else { return }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].archived = true
    }

    // MARK: Consultas

    func intakes(of item: Item) -> [Intake] { intakes.filter { $0.itemID == item.id } }

    /// Doses do item de `day` em diante (hoje: `Calendar.current.startOfDay(for: now)`).
    func intakes(of item: Item, since day: Date) -> [Intake] { intakes(of: item).filter { $0.date >= day } }

    func intakesToday(of item: Item) -> [Intake] { intakes(of: item, since: Calendar.current.startOfDay(for: now)) }

    /// Última dose com local registrado.
    func lastSiteIntake(of item: Item) -> Intake? { intakes(of: item).last { $0.site != nil } }

    /// Dias de atraso de uma dose pendente desde `since` (0 = é de hoje).
    func lateDays(since: Date) -> Int { Format.days(from: since, to: now) }

    func last(_ item: Item) -> Intake? { intakes.last { $0.itemID == item.id } }

    func status(of item: Item) -> Status {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let last = last(item)
        let doses = item.dosesPerDay

        switch item.schedule {
        case .daily:
            if let last, taken(item, since: today) >= doses { return .done(last) }
            return .pending(since: today)

        case .weekdays(let days):
            guard !days.isEmpty else { return .later(next: .distantFuture, last: last) }
            let todayWeekday = calendar.component(.weekday, from: today)
            // Último dia marcado até hoje (o ciclo atual) e o próximo depois de hoje.
            let back = days.map { (todayWeekday - $0 + 7) % 7 }.min()!
            let ahead = days.map { ($0 - todayWeekday + 6) % 7 + 1 }.min()!
            let cycle = calendar.date(byAdding: .day, value: -back, to: today)!
            let next = calendar.date(byAdding: .day, value: ahead, to: today)!
            let early = item.schedule.allowsEveDose ? calendar.date(byAdding: .day, value: -1, to: cycle)! : cycle
            if let last, taken(item, since: early) >= doses {
                return last.date >= today ? .done(last) : .later(next: next, last: last)
            }
            if cycle < calendar.startOfDay(for: item.created) { return .later(next: next, last: last) }
            return .pending(since: cycle)

        case .interval(let every):
            let todayCount = taken(item, since: today)
            if let last, todayCount >= doses { return .done(last) }
            // Começou as doses de hoje e falta alguma.
            if todayCount > 0 { return .pending(since: today) }
            // Sem dose ainda: vale desde que o item foi criado.
            guard let last else { return .pending(since: max(calendar.startOfDay(for: item.created), today)) }
            let due = calendar.date(byAdding: .day, value: max(1, every), to: calendar.startOfDay(for: last.date))!
            return due <= today ? .pending(since: due) : .later(next: due, last: last)

        case .asNeeded:
            return .asNeeded(today: intakes(of: item, since: today))

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

    /// Quantas doses desde o começo de um dia (pra itens com mais de uma dose por dia).
    func taken(_ item: Item, since day: Date) -> Int {
        intakes(of: item, since: day).count
    }

    /// 0 a 1: quanto das doses do dia já foi tomado (preenche a cápsula).
    func doseFraction(of item: Item) -> Double {
        progress(of: item).map { Double($0.taken) / Double($0.total) } ?? 0
    }

    /// Doses tomadas e total do dia em andamento; nil quando é dose única.
    func progress(of item: Item) -> (taken: Int, total: Int)? {
        guard item.dosesPerDay > 1 else { return nil }
        switch status(of: item) {
        case .pending(let since): return (taken(item, since: since), item.dosesPerDay)
        case .done: return (item.dosesPerDay, item.dosesPerDay)
        default: return nil
        }
    }

    /// Horário da próxima dose que falta (a 2ª de 08:00 e 20:00 depois de tomar a 1ª).
    func nextTime(of item: Item, since: Date) -> Clock? {
        guard !item.times.isEmpty else { return nil }
        return item.times[min(taken(item, since: since), item.times.count - 1)]
    }

    /// Horário da coluna da tela de app: o da próxima dose; feito, o último do dia; atrasado ou fora do dia, nenhum.
    func clock(of item: Item) -> Clock? {
        switch status(of: item) {
        case .pending(let since): lateDays(since: since) > 0 ? nil : nextTime(of: item, since: since)
        case .done: item.times.last
        default: nil
        }
    }

    /// Itens que ainda faltam: o número que aparece na barra de menus.
    var due: [Item] { active.filter { status(of: $0).isPending } }

    /// Bloco "Agora": falta e já passou da hora (atrasado, horário vencido ou sem horário no dia).
    func isDueNow(_ item: Item) -> Bool {
        guard case .pending(let since) = status(of: item) else { return false }
        if lateDays(since: since) > 0 { return true }
        guard let next = nextTime(of: item, since: since) else { return true }
        return now >= next.on(since)
    }

    /// Itens com horário que contam hoje (fora do dia não): quantos faltam, de quantos e quantos atrasados.
    var dayProgress: (missing: Int, total: Int, late: Int) {
        var result = (missing: 0, total: 0, late: 0)
        for item in active where item.schedule.isScheduled {
            let status = status(of: item)
            if case .later = status { continue }
            result.total += 1
            guard case .pending(let since) = status else { continue }
            result.missing += 1
            if lateDays(since: since) > 0 { result.late += 1 }
        }
        return result
    }

    /// "Falta 3 de 5, 2 atrasados"; nil sem nada pra hoje.
    var summary: String? {
        let day = dayProgress
        guard day.total > 0 else { return nil }
        if day.missing == 0 { return "Tudo tomado hoje" }
        return "Falta \(day.missing) de \(day.total)" + (day.late > 0 ? ", \(day.late) \(day.late == 1 ? "atrasado" : "atrasados")" : "")
    }

    /// Grade dos últimos dias na tela de app: como ficou `item` no dia de `day`.
    func mark(of item: Item, on day: Date) -> DayMark {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let count = intakes(of: item, since: start).filter { $0.date < end }.count
        if count >= item.dosesPerDay { return .done }
        if count > 0 { return .partial }
        // Hoje ainda dá tempo; antes de o item existir não havia o que tomar.
        guard start < calendar.startOfDay(for: now), start >= calendar.startOfDay(for: item.created) else { return .none }
        switch item.schedule {
        case .daily:
            return .missed
        case .weekdays(let days):
            guard days.contains(calendar.component(.weekday, from: start)) else { return .none }
            let eve = calendar.date(byAdding: .day, value: -1, to: start)!
            if item.schedule.allowsEveDose, intakes.contains(where: { $0.itemID == item.id && $0.date >= eve && $0.date < start }) { return .none }
            return .missed
        // shortcut: "a cada N dias" não marca esquecido (o vencimento depende da dose anterior); calcular se fizer falta.
        case .interval, .asNeeded, .counter:
            return .none
        }
    }

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

    /// Cor de item novo: a primeira que nenhum item ativo usa.
    func freeTint(fallback: Tint) -> Tint {
        Tint.allCases.first { tint in !active.contains { $0.tint == tint } } ?? fallback
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

import Foundation

enum Schedule: Hashable {
    case daily
    /// Dias fixos da semana, no padrão do Calendar: 1 = domingo … 7 = sábado. [7] = todo sábado.
    case weekdays([Int])
    /// A cada N dias, contando da última dose.
    case interval(days: Int)
    /// Sem horário nem cobrança: só registra quando tomou (chá, café…).
    case asNeeded
    /// "12 dias sem comer doce": conta os dias desde a última vez que aconteceu.
    case counter

    /// Entra na lista do dia (tem dia certo pra tomar).
    var isScheduled: Bool {
        switch self {
        case .daily, .weekdays, .interval: true
        case .asNeeded, .counter: false
        }
    }
}

extension Schedule: Codable {
    private enum Kind: String, CodingKey { case daily, weekly, weekdays, interval, asNeeded, counter }
    private enum Field: String, CodingKey { case weekday, days }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Kind.self)
        if container.contains(.daily) {
            self = .daily
        } else if container.contains(.weekly) {
            // Formato da v0.1: um dia só.
            let fields = try container.nestedContainer(keyedBy: Field.self, forKey: .weekly)
            self = .weekdays([try fields.decode(Int.self, forKey: .weekday)])
        } else if container.contains(.weekdays) {
            let fields = try container.nestedContainer(keyedBy: Field.self, forKey: .weekdays)
            self = .weekdays(try fields.decode([Int].self, forKey: .days))
        } else if container.contains(.interval) {
            let fields = try container.nestedContainer(keyedBy: Field.self, forKey: .interval)
            self = .interval(days: try fields.decode(Int.self, forKey: .days))
        } else if container.contains(.asNeeded) {
            self = .asNeeded
        } else if container.contains(.counter) {
            self = .counter
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "frequência desconhecida"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Kind.self)
        switch self {
        case .daily: _ = container.nestedContainer(keyedBy: Field.self, forKey: .daily)
        case .weekdays(let days):
            var fields = container.nestedContainer(keyedBy: Field.self, forKey: .weekdays)
            try fields.encode(days.sorted(), forKey: .days)
        case .interval(let days):
            var fields = container.nestedContainer(keyedBy: Field.self, forKey: .interval)
            try fields.encode(days, forKey: .days)
        case .asNeeded: _ = container.nestedContainer(keyedBy: Field.self, forKey: .asNeeded)
        case .counter: _ = container.nestedContainer(keyedBy: Field.self, forKey: .counter)
        }
    }
}

/// Cor da cápsula de cada item, pra reconhecer de relance.
enum Tint: String, Codable, CaseIterable {
    case teal, orange, purple, pink, blue, green, yellow, brown
}

struct Clock: Codable, Hashable {
    var hour: Int
    var minute: Int

    var label: String { String(format: "%02d:%02d", hour, minute) }

    func on(_ day: Date) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
}

struct Item: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var dose: String
    var schedule: Schedule
    var reminder: Clock?
    var tint: Tint = .teal
    /// Pede o local da aplicação (injetáveis) e sugere o rodízio.
    var tracksSite = false
    /// Excluído pelo usuário: some da tela, mas o histórico continua com o nome.
    var archived = false
    /// Semanas antes disso não contam como atrasadas, senão o item já nasceria "atrasado".
    var created = Date()
}

enum Site: String, Codable, CaseIterable, Identifiable {
    // A ordem é a do rodízio sugerido quando há empate (nenhum usado ainda).
    case abdomenLeft, abdomenRight, thighLeft, thighRight, armLeft, armRight

    var id: String { rawValue }

    /// Linhas do mapa do corpo: região, lado esquerdo, lado direito.
    static let rows: [(region: String, left: Site, right: Site)] = [
        ("Braço", .armLeft, .armRight),
        ("Abdômen", .abdomenLeft, .abdomenRight),
        ("Coxa", .thighLeft, .thighRight),
    ]

    /// "coxa esq.", pras linhas apertadas da tela principal.
    var short: String {
        let side = [.abdomenLeft, .thighLeft, .armLeft].contains(self) ? "esq." : "dir."
        return "\(label.split(separator: " ")[0].lowercased()) \(side)"
    }

    var label: String {
        switch self {
        case .abdomenLeft: "Abdômen esquerdo"
        case .abdomenRight: "Abdômen direito"
        case .thighLeft: "Coxa esquerda"
        case .thighRight: "Coxa direita"
        case .armLeft: "Braço esquerdo"
        case .armRight: "Braço direito"
        }
    }
}

struct Intake: Codable, Identifiable, Hashable {
    var id = UUID()
    var itemID: UUID
    var date: Date
    var site: Site?
}

enum Status {
    /// Precisa tomar. `since` é o dia em que passou a valer (antes de hoje = atrasado).
    case pending(since: Date)
    /// Já tomou hoje.
    case done(Intake)
    /// Semanal fora do dia, já tomado no ciclo atual (ou ainda nem começou).
    case later(next: Date, last: Intake?)
    case asNeeded(today: [Intake])
    /// Contador: `since` é a última vez que aconteceu (ou quando o contador foi criado).
    case counter(since: Date)

    var isPending: Bool {
        if case .pending = self { return true }
        return false
    }
}

extension Item {
    static var examples: [Item] {
        [
            Item(name: "Vitamina C", dose: "5 g", schedule: .daily, reminder: Clock(hour: 9, minute: 0), tint: .teal),
            Item(name: "Vitamina D", dose: "1 cápsula", schedule: .daily, reminder: Clock(hour: 9, minute: 0),
                 tint: .orange),
            Item(name: "Medicação semanal", dose: "", schedule: .weekdays([7]), reminder: Clock(hour: 9, minute: 0),
                 tint: .purple, tracksSite: true),
            Item(name: "Chá", dose: "", schedule: .asNeeded, tint: .brown),
            Item(name: "Café", dose: "", schedule: .asNeeded, tint: .pink),
            Item(name: "comer doce", dose: "", schedule: .counter, tint: .blue),
        ]
    }

    var scheduleLabel: String {
        let time = reminder.map { " às \($0.label)" } ?? ""
        switch schedule {
        case .daily: return "Todo dia" + time
        case .weekdays(let days): return Format.weekdays(days) + time
        case .interval(let days): return (days == 1 ? "Todo dia" : "A cada \(days) dias") + time
        case .asNeeded: return "Quando precisar"
        case .counter: return "Contador de dias"
        }
    }

    /// Nome de exibição: contadores leem "dias sem comer doce".
    var title: String { schedule == .counter ? "Sem \(name)" : name }
}

extension Item {
    private enum CodingKeys: String, CodingKey {
        case id, name, dose, schedule, reminder, tint, tracksSite, archived, created
    }

    /// Campos novos entram com valor padrão, pra abrir os dados salvos por versões anteriores.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        dose = try container.decodeIfPresent(String.self, forKey: .dose) ?? ""
        schedule = try container.decode(Schedule.self, forKey: .schedule)
        reminder = try container.decodeIfPresent(Clock.self, forKey: .reminder)
        tint = try container.decodeIfPresent(Tint.self, forKey: .tint) ?? .teal
        tracksSite = try container.decodeIfPresent(Bool.self, forKey: .tracksSite) ?? false
        archived = try container.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        created = try container.decodeIfPresent(Date.self, forKey: .created) ?? Date()
    }
}

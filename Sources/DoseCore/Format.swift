import Foundation

enum Format {
    static let weekdays = ["domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"]

    /// "Todo sábado", "Toda segunda": sábado e domingo são masculinos.
    static func every(_ weekday: Int) -> String {
        (weekday == 1 || weekday == 7 ? "Todo " : "Toda ") + weekdays[weekday - 1]
    }

    /// "Todo sábado", "Seg, qua e sex", "Todo dia" (os 7), "Fim de semana".
    static func weekdays(_ days: [Int]) -> String {
        let sorted = Set(days).sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }  // segunda primeiro
        switch sorted.count {
        case 0: return "Nenhum dia"
        case 1: return every(sorted[0])
        case 7: return "Todo dia"
        default:
            if sorted == [7, 1] { return "Fim de semana" }
            if sorted == [2, 3, 4, 5, 6] { return "Dias úteis" }
            return list(sorted.map { String(weekdays[$0 - 1].prefix(3)) }).capitalizedFirst
        }
    }

    /// "a", "a e b", "a, b e c"
    static func list(_ parts: [String]) -> String {
        guard parts.count > 1 else { return parts.first ?? "" }
        return parts.dropLast().joined(separator: ", ") + " e " + parts.last!
    }

    private static let locale = Locale(identifier: "pt_BR")

    private static func formatter(_ template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    private static let timeFormatter = formatter("HH:mm")
    private static let shortFormatter = formatter("EEE dd/MM")
    private static let longFormatter = formatter("EEEE d MMMM")
    private static let dateFormatter = formatter("dd/MM")

    static func time(_ date: Date) -> String { timeFormatter.string(from: date) }

    /// "17/10"
    static func date(_ date: Date) -> String { dateFormatter.string(from: date) }

    /// "quinta-feira, 22 de outubro"
    static func long(_ date: Date) -> String { longFormatter.string(from: date) }

    /// "hoje", "ontem", "amanhã" ou "sáb., 25/10".
    static func day(_ date: Date, now: Date = Date()) -> String {
        switch days(from: now, to: date) {
        case 0: "hoje"
        case -1: "ontem"
        case 1: "amanhã"
        default: shortFormatter.string(from: date)
        }
    }

    /// "em 20 min", "em 3 h" (arredondado), pra uma hora que ainda não chegou.
    static func until(_ date: Date, now: Date = Date()) -> String {
        let minutes = max(1, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
        return minutes < 60 ? "em \(minutes) min" : "em \((minutes + 30) / 60) h"
    }

    /// "nunca", "hoje", "há 3 dias", "há 2 sem."
    static func ago(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "nunca" }
        let count = -days(from: now, to: date)
        switch count {
        case ...0: return "hoje"
        case 1: return "ontem"
        case ..<14: return "há \(count) dias"
        default: return "há \(count / 7) sem."
        }
    }

    /// Diferença em dias de calendário (não em períodos de 24 h).
    static func days(from start: Date, to end: Date) -> Int {
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                       to: calendar.startOfDay(for: end)).day ?? 0
    }
}

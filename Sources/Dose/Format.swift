import Foundation

enum Format {
    static let weekdays = ["domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"]

    /// "Todo sábado", "Toda segunda": sábado e domingo são masculinos.
    static func every(_ weekday: Int) -> String {
        (weekday == 1 || weekday == 7 ? "Todo " : "Toda ") + weekdays[weekday - 1]
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

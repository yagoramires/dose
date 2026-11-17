import NeyKit
import SwiftUI

/// Halo do Domo: o card continua grafite, com borda, brilho no canto e sombra na cor do item.
extension View {
    func halo(_ tint: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: Grafite.cardRadius)
        return background {
            shape.fill(Grafite.card)
                .overlay(shape.fill(RadialGradient(colors: [tint.opacity(0.14), .clear], center: .topLeading,
                                                   startRadius: 0, endRadius: 240)))
                .shadow(color: tint.opacity(0.2), radius: 9, y: 5)
        }
        .overlay(shape.strokeBorder(tint.opacity(0.32), lineWidth: 1))
    }
}

/// Título de seção em caixa normal (o GSectionLabel do NeyKit é caixa-alta).
struct SectionText: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(Grafite.muted) }
}

/// O que falta agora: aceso na cor do item, com o botão de tomar à mão.
struct DueCard: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var nav: Nav
    let item: Item
    /// Tela de app: botão embaixo do nome, com a dose ou o local.
    var tall = false
    @ViewState private var hovering = false

    var body: some View {
        let late = lateDays
        let tint = late > 0 ? Color.red : item.tint.color
        let mark = PillMark(tint: tint, style: .todo, progress: store.progress(of: item).map { Double($0.taken) / Double($0.total) } ?? 0)
        Group {
            if tall {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) { mark; name(late: late); ItemMenu(item: item, hovering: hovering) }
                    action
                }
            } else {
                HStack(spacing: 10) { mark; name(late: late); action; ItemMenu(item: item, hovering: hovering) }
            }
        }
        .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 10)
        .halo(item.tint.color)
        .onHover { hovering = $0 }
    }

    private var lateDays: Int {
        guard case .pending(let since) = store.status(of: item) else { return 0 }
        return Format.days(from: since, to: store.now)
    }

    private func name(late: Int) -> some View {
        Button { nav.screen = .edit(item) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Grafite.strong).lineLimit(1)
                Text(detail(late: late)).font(.system(size: 11))
                    .foregroundStyle(late > 0 ? Color.red : Grafite.warn).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Editar \(item.name)")
    }

    /// "3 dias de atraso, glúteo dir." / "Desde 09:00, 1 cápsula" / "Hoje, 1 dose".
    private func detail(late: Int) -> String {
        var parts: [String] = []
        if late > 0 {
            parts.append("\(late) \(late == 1 ? "dia" : "dias") de atraso")
        } else if case .pending(let since) = store.status(of: item), let next = store.nextTime(of: item, since: since) {
            parts.append("Desde \(next.label)")
        } else {
            parts.append("Hoje")
        }
        if tall { return parts[0] }
        if item.tracksSite { parts.append(store.suggestedSite(for: item).short) } else if !item.dose.isEmpty { parts.append(item.dose) }
        if let progress = store.progress(of: item) { parts.append("\(progress.taken) de \(progress.total)") }
        return parts.joined(separator: ", ")
    }

    private var action: some View {
        let tint = item.tint.color
        let title: String = {
            if item.tracksSite { return tall ? "Aplicar no \(store.suggestedSite(for: item).short)" : "Aplicar" }
            return tall && !item.dose.isEmpty ? "Tomei \(item.dose)" : "Tomei"
        }()
        return Button { nav.take(item, store: store) } label: {
            Label(title, systemImage: item.tracksSite ? "syringe" : "checkmark")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(tint).lineLimit(1)
                .padding(.horizontal, 10).frame(height: 24)
                .background(tint.opacity(0.16), in: Capsule())
                .overlay(Capsule().strokeBorder(tint.opacity(0.45), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(item.tracksSite ? "Registrar e escolher o local" : "Marcar como tomado")
    }
}

/// Régua de 0 a 24 h com os horários de hoje (cheio = tomado, vermelho = passou) e a hora atual.
struct DayRuler: View {
    @EnvironmentObject private var store: Store

    private struct Dot: Hashable { let at: Double; let tint: Color; let done: Bool; let missed: Bool }

    private var dots: [Dot] {
        let today = Calendar.current.startOfDay(for: store.now)
        return store.active.filter { $0.schedule.isScheduled }.flatMap { item -> [Dot] in
            if case .later = store.status(of: item) { return [] }
            let taken = store.taken(item, since: today)
            return item.times.sorted().enumerated().map { index, clock in
                let done = index < taken
                return Dot(at: Double(clock.hour * 60 + clock.minute) / 1440, tint: item.tint.color,
                           done: done, missed: !done && clock.on(today) < store.now)
            }
        }
    }

    static func hasDots(_ store: Store) -> Bool {
        store.active.contains { $0.schedule.isScheduled && !$0.times.isEmpty }
    }

    var body: some View {
        let calendar = Calendar.current
        let now = Double(calendar.component(.hour, from: store.now) * 60 + calendar.component(.minute, from: store.now)) / 1440
        VStack(spacing: 4) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Grafite.cardBorder).frame(height: 4)
                    Capsule().fill(Grafite.ghostBorder).frame(width: width * now, height: 4)
                    ForEach(dots, id: \.self) { dot in
                        Circle()
                            .fill(dot.done ? dot.tint : Grafite.bg)
                            .overlay(Circle().strokeBorder(dot.missed ? Color.red : dot.tint, lineWidth: 2))
                            .frame(width: 12, height: 12)
                            .offset(x: width * dot.at - 6)
                    }
                    RoundedRectangle(cornerRadius: 1).fill(Grafite.accent).frame(width: 2, height: 18)
                        .shadow(color: Grafite.accent.opacity(0.7), radius: 4)
                        .offset(x: width * now - 1)
                }
                .frame(height: 18)
            }
            .frame(height: 18)
            HStack {
                ForEach(["0h", "6h", "12h", "18h", "24h"], id: \.self) { label in
                    Text(label)
                    if label != "24h" { Spacer() }
                }
            }
            .font(.system(size: 9)).foregroundStyle(Grafite.ghostText)
        }
        .accessibilityHidden(true)
    }
}

/// Anel do dia: tomados sobre o total, com a conta no meio.
struct ProgressRing: View {
    let done: Int
    let total: Int
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            Circle().stroke(Grafite.cardBorder, lineWidth: 3.5)
            Circle().trim(from: 0, to: total > 0 ? CGFloat(done) / CGFloat(total) : 0)
                .stroke(Grafite.accent, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(done)/\(total)").font(.system(size: size * 0.3, weight: .semibold)).monospacedDigit().foregroundStyle(Grafite.strong)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("\(done) de \(total) tomados hoje")
    }
}

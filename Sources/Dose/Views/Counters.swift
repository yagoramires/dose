import SwiftUI

/// Três propostas de visual pros contadores, pra escolher uma (as outras saem depois).
enum CounterStyle: String, CaseIterable {
    /// Placa de "Estamos há X dias sem acidentes", com dígitos de placar.
    case plate
    /// Linha com barra até o recorde.
    case record
    /// Linha com as últimas 4 semanas em pontinhos.
    case dots

    static var current: CounterStyle {
        UserDefaults.standard.string(forKey: "counterStyle").flatMap(CounterStyle.init) ?? .plate
    }
}

private struct CounterStyleKey: EnvironmentKey {
    static let defaultValue = CounterStyle.current
}

extension EnvironmentValues {
    var counterStyle: CounterStyle {
        get { self[CounterStyleKey.self] }
        set { self[CounterStyleKey.self] = newValue }
    }
}

struct CounterSection: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var nav: Nav
    @Environment(\.counterStyle) private var style

    var body: some View {
        let counters = store.active.filter { $0.schedule == .counter }
        VStack(alignment: .leading, spacing: 0) {
            if style == .plate {
                HazardStripes().frame(height: 7)
                Text("Estamos há…")
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
            } else {
                SectionTitle(text: "Contadores")
            }
            VStack(spacing: 0) {
                ForEach(counters) { CounterRow(item: $0, style: style) }
            }
            Button { nav.screen = .newCounter } label: {
                Label("Novo contador", systemImage: "plus")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }
}

struct CounterRow: View {
    @EnvironmentObject private var store: Store
    let item: Item
    let style: CounterStyle
    @ViewState private var hovering = false

    var body: some View {
        let since: Date = if case .counter(let since) = store.status(of: item) { since } else { item.created }
        let days = Format.days(from: since, to: store.now)
        let record = store.record(of: item)

        HStack(alignment: style == .plate ? .center : .top, spacing: 12) {
            number(days)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(days == 1 ? "dia" : "dias") \(item.title.lowercased())")
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                switch style {
                case .plate:
                    Text(note(days: days, record: record, since: since)).font(.caption).foregroundStyle(.secondary)
                case .record:
                    RecordBar(days: days, record: record, tint: item.tint.color)
                    Text(note(days: days, record: record, since: since)).font(.caption).foregroundStyle(.secondary)
                case .dots:
                    WeekDots(item: item, tint: item.tint.color)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 2) {
                Button { store.take(item) } label: {
                    Image(systemName: "arrow.counterclockwise").frame(width: 20, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Aconteceu agora: zerar (dá pra desfazer no ⋯)")
                ItemMenu(item: item, hovering: true)
            }
            .opacity(hovering ? 1 : 0.35)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(hovering ? Color.primary.opacity(0.05) : .clear)
        .onHover { hovering = $0 }
    }

    @ViewBuilder private func number(_ days: Int) -> some View {
        switch style {
        case .plate:
            FlipNumber(value: days)
        case .record, .dots:
            Text("\(days)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(item.tint.color)
                .frame(minWidth: 40, alignment: .trailing)
        }
    }

    private func note(days: Int, record: Int, since: Date) -> String {
        guard store.last(item) != nil else { return "Contando desde \(Format.date(since))" }
        if days >= record { return days == 0 ? "Aconteceu hoje" : "Recorde atual" }
        return "Recorde: \(record) dias"
    }
}

/// Dígitos de placar: uma plaquinha escura por algarismo, com o vinco no meio.
struct FlipNumber: View {
    let value: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(String(format: "%02d", value).enumerated()), id: \.offset) { _, digit in
                Text(String(digit))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(width: 21, height: 32)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.18)))
                    .overlay(Rectangle().fill(Color.black.opacity(0.55)).frame(height: 1))
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.08)))
    }
}

/// Faixa zebrada amarela e preta, das placas de segurança.
struct HazardStripes: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 1, green: 0.8, blue: 0.1)))
            let step: CGFloat = 12
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                var stripe = Path()
                stripe.move(to: CGPoint(x: x, y: size.height))
                stripe.addLine(to: CGPoint(x: x + size.height, y: 0))
                stripe.addLine(to: CGPoint(x: x + size.height + step / 2, y: 0))
                stripe.addLine(to: CGPoint(x: x + step / 2, y: size.height))
                stripe.closeSubpath()
                context.fill(stripe, with: .color(Color(white: 0.1)))
                x += step
            }
        }
    }
}

/// Barra do atual em relação ao recorde; passa do recorde e enche.
struct RecordBar: View {
    let days: Int
    let record: Int
    let tint: Color

    var body: some View {
        let fraction = record > 0 ? min(1, Double(days) / Double(record)) : 1
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.18))
                Capsule().fill(tint).frame(width: max(5, geometry.size.width * fraction))
            }
        }
        .frame(height: 5)
    }
}

/// As últimas 4 semanas, uma bolinha por dia (cheia = aconteceu), hoje na ponta direita.
struct WeekDots: View {
    @EnvironmentObject private var store: Store
    let item: Item
    let tint: Color

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: store.now)
        let hits = Set(store.intakes(of: item).map { calendar.startOfDay(for: $0.date) })
        let start = calendar.startOfDay(for: item.created)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                ForEach(0..<4) { week in
                    HStack(spacing: 2) {
                        ForEach(0..<7) { weekday in
                            let back = 27 - (week * 7 + weekday)
                            let day = calendar.date(byAdding: .day, value: -back, to: today)!
                            Circle()
                                .fill(hits.contains(day) ? tint : tint.opacity(day < start ? 0.06 : 0.2))
                                .overlay(Circle().strokeBorder(back == 0 ? tint : .clear, lineWidth: 1))
                                .frame(width: 4.5, height: 4.5)
                        }
                    }
                }
            }
            Text("\(hits.filter { $0 > calendar.date(byAdding: .day, value: -28, to: today)! }.count)× em 4 semanas")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: Novo contador

/// Criar um contador montando a frase: "0 dias sem ____".
struct NewCounterView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var nav: Nav
    @ViewState private var name = ""
    @ViewState private var last = Date()
    @ViewState private var tint: Tint?

    var body: some View {
        let chosen = tint ?? Tint.allCases.first { tint in !store.active.contains { $0.tint == tint } } ?? .blue
        let days = Format.days(from: last, to: Date())
        VStack(alignment: .leading, spacing: 0) {
            Header(title: "Novo contador", back: { nav.screen = .today })
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(days)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(chosen.color)
                    Text(days == 1 ? "dia sem" : "dias sem").font(.title3.weight(.medium))
                    TextField("", text: $name, prompt: Text("comer doce"))
                        .textFieldStyle(.plain)
                        .font(.title3.weight(.medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(chosen.color.opacity(0.12)))

                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow {
                        Text("Última vez").foregroundStyle(.secondary)
                        DatePicker("", selection: $last, in: ...Date(), displayedComponents: .date).labelsHidden()
                    }
                    GridRow {
                        Text("Cor").foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            ForEach(Tint.allCases, id: \.self) { option in
                                Button { tint = option } label: {
                                    Circle().fill(option.color).frame(width: 18, height: 18)
                                        .overlay(Circle().strokeBorder(.primary.opacity(chosen == option ? 0.8 : 0), lineWidth: 2)
                                            .padding(-3))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.leading, 3)
                    }
                }

                HStack {
                    Spacer()
                    Button("Cancelar") { nav.screen = .today }
                    Button("Criar contador") {
                        var item = Item(name: name.trimmingCharacters(in: .whitespaces), dose: "", schedule: .counter,
                                        tint: chosen)
                        item.created = last
                        store.upsert(item)
                        nav.screen = .today
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(14)
        }
    }
}

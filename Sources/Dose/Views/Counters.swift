import SwiftUI

struct CounterSection: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var nav: Nav

    var body: some View {
        let counters = store.active.filter { $0.schedule == .counter }
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(text: "Contadores")
            VStack(spacing: 0) {
                ForEach(counters) { CounterRow(item: $0) }
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

/// "12 dias sem comer doce", com a barra do quanto falta pro recorde.
struct CounterRow: View {
    @EnvironmentObject private var store: Store
    let item: Item
    @ViewState private var hovering = false

    var body: some View {
        let since: Date = if case .counter(let since) = store.status(of: item) { since } else { item.created }
        let days = Format.days(from: since, to: store.now)
        let record = store.record(of: item)

        HStack(alignment: .top, spacing: 12) {
            Text("\(days)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(item.tint.color)
                .frame(minWidth: 40, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(days == 1 ? "dia" : "dias") \(item.title.lowercased())")
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                RecordBar(days: days, record: record, tint: item.tint.color)
                Text(note(days: days, record: record, since: since)).font(.caption).foregroundStyle(.secondary)
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

    private func note(days: Int, record: Int, since: Date) -> String {
        guard store.last(item) != nil else { return "Contando desde \(Format.date(since))" }
        if days >= record { return days == 0 ? "Aconteceu hoje" : "Recorde atual" }
        return "Recorde: \(record) dias"
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

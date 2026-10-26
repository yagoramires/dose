import NeyKit
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var nav: Nav

    var body: some View {
        let streaks = store.active
            .filter { $0.schedule == .daily }
            .map { ($0, store.streak(of: $0)) }
            .filter { $0.1 > 1 }

        VStack(alignment: .leading, spacing: 0) {
            Header(title: "Histórico", back: { nav.screen = .today })
            Line()
            if store.intakes.isEmpty {
                Text("Nada registrado ainda.")
                    .foregroundStyle(Grafite.muted)
                    .frame(maxWidth: .infinity)
                    .padding(24)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !streaks.isEmpty {
                            SectionTitle(text: "Sequências")
                            ForEach(streaks, id: \.0.id) { item, streak in
                                HStack(spacing: 8) {
                                    Circle().fill(item.tint.color).frame(width: 7, height: 7)
                                    Text(item.name)
                                    Spacer()
                                    Text("\(streak) dias seguidos").monospacedDigit().foregroundStyle(Grafite.muted)
                                }
                                .font(.callout)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 3)
                            }
                        }
                        HistoryDays()
                    }
                    .padding(.bottom, 8)
                }
                .frame(height: 400)
            }
        }
    }
}

/// Registros por dia, do mais novo pro mais antigo, com o apagar de cada um (popover e tela de app).
struct HistoryDays: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        let calendar = Calendar.current
        let days = Dictionary(grouping: store.intakes.reversed()) { calendar.startOfDay(for: $0.date) }
            .sorted { $0.key > $1.key }
        ForEach(days, id: \.key) { day, intakes in
            SectionTitle(text: dayTitle(day))
            ForEach(intakes) { HistoryRow(intake: $0) }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let relative = Format.day(day, now: store.now)
        return relative.contains("/") ? Format.long(day).capitalizedFirst : "\(relative.capitalizedFirst), \(Format.long(day))"
    }
}

private struct HistoryRow: View {
    @EnvironmentObject private var store: Store
    let intake: Intake
    @ViewState private var hovering = false

    var body: some View {
        let item = store.item(intake.itemID)
        HStack(spacing: 8) {
            Text(Format.time(intake.date)).monospacedDigit().foregroundStyle(Grafite.muted)
            Circle().fill(item?.tint.color ?? Grafite.muted).frame(width: 7, height: 7)
            // Contador: o registro é o evento em si ("Comer doce").
            Text(item.map { $0.schedule == .counter ? $0.name.capitalizedFirst : $0.name } ?? "Item apagado")
            if let dose = item?.dose, !dose.isEmpty {
                Text(dose).foregroundStyle(Grafite.muted)
            }
            Spacer(minLength: 4)
            if let site = intake.site {
                Text(site.label).font(.caption).foregroundStyle(Grafite.muted)
            }
            Button { store.delete(intake) } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Apagar este registro")
            .opacity(hovering ? 1 : 0)
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
        .background(hovering ? Grafite.selected : .clear)
        .onHover { hovering = $0 }
    }
}

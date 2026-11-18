import NeyKit
import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var nav: Nav
    @EnvironmentObject private var reminders: Reminders

    var body: some View {
        let scheduled = store.scheduled
        // Agora: atrasados primeiro. Depois o que ainda vem, o que já foi e, por último, os fora do dia.
        let now = scheduled.filter(store.isDueNow).sorted { rank($0) < rank($1) }
        let rest = scheduled.filter { !store.isDueNow($0) }.sorted { rank($0) < rank($1) }
        let asNeeded = store.asNeeded
        let day = store.dayProgress

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if day.total > 0 { ProgressRing(done: day.total - day.missing, total: day.total) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(Format.long(store.now).capitalizedFirst).font(.system(size: 13, weight: .bold)).foregroundStyle(Grafite.strong)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    if let summary = store.summary {
                        Text(summary).font(.system(size: 11)).foregroundStyle(day.late > 0 ? Color.red : Grafite.muted)
                    }
                }
                Spacer(minLength: 0)
                IconButton(symbol: "plus", help: "Novo item") { nav.screen = .edit(nil) }
                IconButton(symbol: "clock.arrow.circlepath", help: "Histórico") { nav.screen = .history }
                IconButton(symbol: "gearshape", help: "Itens e ajustes") { nav.screen = .items }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            if DayRuler.hasDots(store) {
                DayRuler().padding(.horizontal, 14).padding(.bottom, 8)
            }
            Line()

            if store.active.isEmpty {
                Welcome()
            }
            if !now.isEmpty {
                SectionTitle(text: "Agora")
                VStack(spacing: 8) {
                    ForEach(now) { DueCard(item: $0) }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            if !rest.isEmpty {
                if !now.isEmpty { SectionTitle(text: "Resto do dia") }
                VStack(spacing: 0) {
                    ForEach(rest) { ItemRow(item: $0) }
                }
                .padding(.vertical, 6)
            }
            if !asNeeded.isEmpty {
                if !scheduled.isEmpty { Line() }
                SectionTitle(text: "Quando precisar")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(asNeeded) { NeedChip(item: $0) }
                }
                .padding(.horizontal, 14)
                .padding(.top, 4)
                .padding(.bottom, 10)
            }
            if !store.active.isEmpty {
                if !scheduled.isEmpty || !asNeeded.isEmpty { Line() }
                CounterSection()
            }
            if !reminders.authorized {
                Line()
                NotificationsOff()
            }
        }
    }

    private func rank(_ item: Item) -> Int {
        switch store.status(of: item) {
        case .pending: 0
        case .done: 1
        case .later, .asNeeded, .counter: 2
        }
    }

}

/// O Ligar abre Ajustes no avulso e Permissões no NeyHub.
struct NotificationsOff: View {
    @EnvironmentObject private var reminders: Reminders

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.slash").foregroundStyle(Grafite.warn)
            Text("Notificações desligadas, os lembretes não aparecem.").font(.callout).foregroundStyle(Grafite.warn)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            GPill(title: "Ligar") { reminders.openSettings() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

/// Primeira abertura: nada vem pronto, cada um monta a sua lista.
struct Welcome: View {
    @EnvironmentObject private var nav: Nav

    var body: some View {
        VStack(spacing: 10) {
            PillMark(tint: Tint.teal.color, style: .todo).scaleEffect(1.6).padding(.vertical, 8)
            Text("O que você toma?").font(.title3.weight(.semibold)).foregroundStyle(Grafite.strong)
            Text("Adicione cada remédio ou suplemento com a frequência e os horários dele. Também dá pra contar dias sem alguma coisa.")
                .font(.callout).foregroundStyle(Grafite.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                FormButton(title: "Novo contador") { nav.screen = .newCounter }
                FormButton(title: "Adicionar item", style: .primary) { nav.screen = .edit(nil) }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }
}

// MARK: Linha de remédio

struct ItemRow: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var nav: Nav
    let item: Item
    /// Tela de app: coluna do horário à esquerda e "em 3 h" / "feito às" à direita.
    var wide = false
    @ViewState private var hovering = false

    var body: some View {
        let status = store.status(of: item)
        HStack(spacing: 12) {
            if wide {
                Text(store.clock(of: item)?.label ?? "").font(.system(size: 11, design: .monospaced)).foregroundStyle(Grafite.muted)
                    .frame(width: 40, alignment: .leading)
            }
            check(status)
            // O nome abre a edição (frequência, dose, lembrete); quem marca é a cápsula.
            Button { nav.screen = .edit(item) } label: {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(item.name).fontWeight(.medium)
                        if !item.dose.isEmpty {
                            Text(item.dose).font(.callout).foregroundStyle(Grafite.muted)
                        }
                    }
                    if let detail = detail(status) {
                        Text(detail).font(.caption).foregroundStyle(Grafite.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Editar \(item.name)")
            trailing(status)
            ItemMenu(item: item, hovering: hovering)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(hovering ? Grafite.selected : .clear)
        .onHover { hovering = $0 }
    }

    // MARK: Cápsula da esquerda

    @ViewBuilder private func check(_ status: Status) -> some View {
        switch status {
        case .done:
            PillMark(tint: item.tint.color, style: .done).help("Tomado")
        case .asNeeded:
            Button { take() } label: { PillMark(tint: item.tint.color, style: .add) }
                .buttonStyle(.plain)
                .help("Registrar agora")
        case .pending(let since):
            let late = store.lateDays(since: since) > 0
            Button { take() } label: { PillMark(tint: late ? .red : item.tint.color, style: .todo, progress: store.doseFraction(of: item)) }
                .buttonStyle(.plain)
                .help(item.tracksSite ? "Registrar e escolher o local" : "Marcar como tomado")
        case .later:
            // Fora do dia: abre a tela de registro pra confirmar, um clique solto não marca.
            Button { nav.screen = .log(item.id) } label: { PillMark(tint: item.tint.color, style: .later) }
                .buttonStyle(.plain)
                .help("Registrar uma dose fora do dia")
        case .counter:
            EmptyView()
        }
    }

    private func take() { nav.take(item, store: store) }

    // MARK: Textos

    private func detail(_ status: Status) -> String? {
        switch status {
        case .pending:
            if item.tracksSite { return "Sugestão: \(store.suggestedSite(for: item).label.lowercased())" }
            return store.progress(of: item).map { "\($0.taken) de \($0.total) hoje" }
        case .done(let intake):
            if let site = intake.site { return site.label }
            if item.dosesPerDay > 1 {
                return "Doses às " + Format.list(store.intakesToday(of: item).map { Format.time($0.date) })
            }
            let streak = store.streak(of: item)
            return item.schedule == .daily && streak > 1 ? "\(streak) dias seguidos" : nil
        case .later(_, let last):
            guard let last else { return nil }
            let site = last.site.map { ", \($0.short)" } ?? ""
            return "Última em \(Format.date(last.date))\(site)"
        case .asNeeded(let today):
            return today.last.map { "Última às \(Format.time($0.date))" }
        case .counter:
            return nil
        }
    }

    @ViewBuilder private func trailing(_ status: Status) -> some View {
        switch status {
        case .pending(let since):
            let late = store.lateDays(since: since)
            if late > 0 {
                Text("\(Format.dayCount(late)) de atraso").font(.callout.weight(.medium)).foregroundStyle(.red)
            } else if let next = store.nextTime(of: item, since: since) {
                let due = next.on(since)
                Text(wide ? (store.now >= due ? "desde \(next.label)" : Format.until(due, now: store.now)) : next.label)
                    .font(.callout).monospacedDigit()
                    .foregroundStyle(store.now >= due ? Grafite.warn : Grafite.muted)
            }
        case .done(let intake):
            Text(wide ? "feito às \(Format.time(intake.date))" : Format.time(intake.date)).font(.callout).monospacedDigit()
                .foregroundStyle(wide ? Grafite.accent : Grafite.muted)
        case .later(let next, _):
            Text(Format.day(next, now: store.now).capitalizedFirst).font(.callout).foregroundStyle(Grafite.muted)
        case .asNeeded(let today):
            if !today.isEmpty {
                Text("\(today.count)× hoje").font(.callout).monospacedDigit().foregroundStyle(Grafite.muted)
            }
        case .counter:
            EmptyView()
        }
    }
}

/// A cápsula que faz as vezes de checkbox, na cor do item.
struct PillMark: View {
    enum Style { case todo, done, later, add }
    let tint: Color
    let style: Style
    /// Doses já tomadas no dia, de 0 a 1 (só nos itens com mais de uma dose).
    var progress: Double = 0

    var body: some View {
        ZStack {
            switch style {
            case .todo:
                if progress > 0 {
                    Capsule().fill(tint).mask(alignment: .leading) {
                        Rectangle().frame(width: 30 * progress)
                    }
                } else {
                    // Meia cápsula tingida: lembra um comprimido e deixa claro que falta.
                    Capsule().fill(tint.opacity(0.22)).mask(alignment: .leading) {
                        Rectangle().frame(width: 15)
                    }
                }
                Capsule().strokeBorder(tint, lineWidth: 1.5)
            case .done:
                Capsule().fill(tint)
                Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
            case .later:
                Capsule().strokeBorder(tint.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5]))
            case .add:
                Capsule().fill(tint.opacity(0.16))
                Image(systemName: "plus").font(.system(size: 10, weight: .heavy)).foregroundStyle(tint)
            }
        }
        .frame(width: 30, height: 17)
        .contentShape(Capsule())
    }
}

// MARK: Menu ⋯

struct ItemMenu: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var nav: Nav
    let item: Item
    var hovering: Bool

    var body: some View {
        let last = store.last(item)
        let counter = item.schedule == .counter
        Menu {
            if counter {
                Button("Aconteceu agora, zerar") { store.take(item) }
                Button("Aconteceu em outra data…") { nav.screen = .log(item.id) }
            } else {
                Button("Registrar com outro horário…") { nav.screen = .log(item.id) }
            }
            if let last {
                Button("Desfazer registro de \(Format.day(last.date, now: store.now)) às \(Format.time(last.date))") {
                    store.delete(last)
                }
            }
            Divider()
            Button("Editar…") { nav.screen = .edit(item) }
        } label: {
            Image(systemName: "ellipsis").foregroundStyle(Grafite.ghostText)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(Grafite.ghostText)
        .fixedSize()
        .opacity(hovering ? 1 : 0.35)
    }
}

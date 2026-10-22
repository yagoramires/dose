import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var nav: Nav
    @EnvironmentObject private var reminders: Reminders

    var body: some View {
        let scheduled = store.active.filter { $0.schedule.isScheduled }
        // Primeiro o que falta, depois o que já foi, por último os semanais fora do dia.
        let ordered = scheduled.sorted { rank($0) < rank($1) }
        let asNeeded = store.active.filter { $0.schedule == .asNeeded }
        let missing = scheduled.filter { store.status(of: $0).isPending }.count
        let today = scheduled.filter { if case .later = store.status(of: $0) { false } else { true } }.count

        VStack(alignment: .leading, spacing: 0) {
            Header(title: Format.long(store.now).capitalizedFirst, subtitle: progress(missing: missing, of: today)) {
                IconButton(symbol: "plus", help: "Novo item") { nav.screen = .edit(nil) }
                IconButton(symbol: "clock.arrow.circlepath", help: "Histórico") { nav.screen = .history }
                IconButton(symbol: "gearshape", help: "Itens e ajustes") { nav.screen = .items }
            }
            Divider()

            if store.active.isEmpty {
                Welcome()
            }
            if !ordered.isEmpty {
                VStack(spacing: 0) {
                    ForEach(ordered) { ItemRow(item: $0) }
                }
                .padding(.vertical, 6)
            }
            if !asNeeded.isEmpty {
                if !ordered.isEmpty { Divider() }
                SectionTitle(text: "Quando precisar")
                VStack(spacing: 0) {
                    ForEach(asNeeded) { ItemRow(item: $0) }
                }
                .padding(.bottom, 6)
            }
            if !store.active.isEmpty {
                if !ordered.isEmpty || !asNeeded.isEmpty { Divider() }
                CounterSection()
            }
            if !reminders.authorized {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "bell.slash").foregroundStyle(.orange)
                    Text("Notificações desligadas, os lembretes não aparecem.").font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button("Ligar") { reminders.openSettings() }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
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

    private func progress(missing: Int, of total: Int) -> String? {
        guard total > 0 else { return nil }
        return missing == 0 ? "Tudo tomado hoje" : "Falta \(missing) de \(total)"
    }
}

/// Primeira abertura: nada vem pronto, cada um monta a sua lista.
private struct Welcome: View {
    @EnvironmentObject private var nav: Nav

    var body: some View {
        VStack(spacing: 10) {
            PillMark(tint: Tint.teal.color, style: .todo).scaleEffect(1.6).padding(.vertical, 8)
            Text("O que você toma?").font(.title3.weight(.semibold))
            Text("Adicione cada remédio ou suplemento com a frequência e os horários dele. Também dá pra contar dias sem alguma coisa.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Novo contador") { nav.screen = .newCounter }
                Button("Adicionar item") { nav.screen = .edit(nil) }
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
    @ViewState private var hovering = false

    var body: some View {
        let status = store.status(of: item)
        HStack(spacing: 12) {
            check(status)
            // O nome abre a edição (frequência, dose, lembrete); quem marca é a cápsula.
            Button { nav.screen = .edit(item) } label: {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(item.name).fontWeight(.medium)
                        if !item.dose.isEmpty {
                            Text(item.dose).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    if let detail = detail(status) {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
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
        .background(hovering ? Color.primary.opacity(0.05) : .clear)
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
            let late = Format.days(from: since, to: store.now) > 0
            Button { take() } label: { PillMark(tint: late ? .red : item.tint.color, style: .todo,
                                                      progress: store.progress(of: item).map { Double($0.taken) / Double($0.total) } ?? 0) }
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

    private func take() {
        if item.tracksSite {
            nav.screen = .log(item.id)
        } else {
            store.take(item)
        }
    }

    // MARK: Textos

    private func detail(_ status: Status) -> String? {
        switch status {
        case .pending:
            if item.tracksSite { return "Sugestão: \(store.suggestedSite(for: item).label.lowercased())" }
            return store.progress(of: item).map { "\($0.taken) de \($0.total) hoje" }
        case .done(let intake):
            if let site = intake.site { return site.label }
            if item.dosesPerDay > 1 {
                let today = store.intakes(of: item).filter { $0.date >= Calendar.current.startOfDay(for: store.now) }
                return "Doses às " + Format.list(today.map { Format.time($0.date) })
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
            let late = Format.days(from: since, to: store.now)
            if late > 0 {
                Text("\(late) \(late == 1 ? "dia" : "dias") de atraso").font(.callout.weight(.medium)).foregroundStyle(.red)
            } else if let next = store.nextTime(of: item, since: since) {
                Text(next.label).font(.callout).monospacedDigit()
                    .foregroundStyle(store.now >= next.on(since) ? Color.orange : Color.secondary)
            }
        case .done(let intake):
            Text(Format.time(intake.date)).font(.callout).monospacedDigit().foregroundStyle(.secondary)
        case .later(let next, _):
            Text(Format.day(next, now: store.now).capitalizedFirst).font(.callout).foregroundStyle(.secondary)
        case .asNeeded(let today):
            if !today.isEmpty {
                Text("\(today.count)× hoje").font(.callout).monospacedDigit().foregroundStyle(.secondary)
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
                    // Enche da esquerda pra direita conforme as doses do dia.
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
            Image(systemName: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .opacity(hovering ? 1 : 0.35)
    }
}

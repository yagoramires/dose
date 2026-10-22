import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var nav: Nav
    @EnvironmentObject private var reminders: Reminders

    var body: some View {
        let scheduled = store.active.filter { $0.schedule != .asNeeded }
        // Primeiro o que falta, depois o que já foi, por último os semanais fora do dia.
        let ordered = scheduled.sorted { rank($0) < rank($1) }
        let asNeeded = store.active.filter { $0.schedule == .asNeeded }
        let done = scheduled.filter { if case .done = store.status(of: $0) { true } else { false } }.count
        let today = scheduled.count - scheduled.filter { if case .later = store.status(of: $0) { true } else { false } }.count

        VStack(alignment: .leading, spacing: 0) {
            Header(title: "Hoje", subtitle: subtitle(done: done, of: today)) {
                IconButton(symbol: "clock.arrow.circlepath", help: "Histórico") { nav.screen = .history }
                IconButton(symbol: "gearshape", help: "Itens e ajustes") { nav.screen = .items }
            }
            Divider()

            if store.active.isEmpty {
                Text("Nenhum item. Adicione em ⚙︎.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(24)
            }
            if !ordered.isEmpty {
                VStack(spacing: 0) {
                    ForEach(ordered) { ItemRow(item: $0) }
                }
                .padding(.vertical, 4)
            }
            if !asNeeded.isEmpty {
                if !ordered.isEmpty { Divider() }
                SectionTitle(text: "Quando precisar")
                VStack(spacing: 0) {
                    ForEach(asNeeded) { ItemRow(item: $0) }
                }
                .padding(.bottom, 6)
            }
            if !reminders.authorized {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "bell.slash").foregroundStyle(.orange)
                    Text("Notificações desligadas: sem lembretes.").font(.callout)
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
        case .later, .asNeeded: 2
        }
    }

    private func subtitle(done: Int, of total: Int) -> String {
        let date = Format.long(store.now)
        guard total > 0 else { return date }
        return done == total ? "\(date) · tudo em dia ✓" : "\(date) · \(done) de \(total)"
    }
}

struct ItemRow: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var nav: Nav
    let item: Item
    @ViewState private var hovering = false

    var body: some View {
        let status = store.status(of: item)
        HStack(spacing: 10) {
            check(status)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.name).fontWeight(.medium)
                    if !item.dose.isEmpty {
                        Text(item.dose).font(.callout).foregroundStyle(.secondary)
                    }
                }
                if let detail = detail(status) {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            trailing(status)
            menu(status)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(hovering ? Color.primary.opacity(0.05) : .clear)
        .onHover { hovering = $0 }
    }

    // MARK: Bolinha da esquerda

    @ViewBuilder private func check(_ status: Status) -> some View {
        switch status {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.title2).foregroundStyle(.green)
                .help("Tomado")
        case .asNeeded:
            Button { take() } label: {
                Image(systemName: "plus.circle").font(.title2)
            }
            .buttonStyle(.borderless)
            .help("Registrar agora")
        case .pending(let since):
            Button { take() } label: {
                Image(systemName: "circle").font(.title2)
                    .foregroundStyle(Format.days(from: since, to: store.now) > 0 ? Color.red : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(item.tracksSite ? "Registrar e escolher o local" : "Marcar como tomado")
        case .later:
            // Fora do dia: abre a tela de registro pra confirmar, um clique solto não marca.
            Button { nav.screen = .log(item.id) } label: {
                Image(systemName: "circle.dashed").font(.title2).foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .help("Registrar uma dose fora do dia")
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
            return item.tracksSite ? "Sugestão: \(store.suggestedSite(for: item).label.lowercased())" : nil
        case .done(let intake):
            if let site = intake.site { return site.label }
            let streak = store.streak(of: item)
            return item.schedule == .daily && streak > 1 ? "\(streak) dias seguidos" : nil
        case .later(_, let last):
            guard let last else { return nil }
            let site = last.site.map { " · \($0.label.lowercased())" } ?? ""
            return "Última: \(Format.date(last.date))\(site)"
        case .asNeeded(let today):
            return today.last.map { "Última às \(Format.time($0.date))" }
        }
    }

    @ViewBuilder private func trailing(_ status: Status) -> some View {
        switch status {
        case .pending(let since):
            let late = Format.days(from: since, to: store.now)
            if late > 0 {
                Text("atrasado \(late) \(late == 1 ? "dia" : "dias")").font(.caption.weight(.medium)).foregroundStyle(.red)
            } else if let reminder = item.reminder {
                Text(reminder.label).font(.callout).monospacedDigit()
                    .foregroundStyle(store.now >= reminder.on(since) ? Color.orange : Color.secondary)
            }
        case .done(let intake):
            Text(Format.time(intake.date)).font(.callout).monospacedDigit().foregroundStyle(.green)
        case .later(let next, _):
            Text(Format.day(next, now: store.now)).font(.callout).foregroundStyle(.secondary)
        case .asNeeded(let today):
            if !today.isEmpty {
                Text("\(today.count)× hoje").font(.callout).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Menu ⋯

    private func menu(_ status: Status) -> some View {
        let last = store.last(item)
        return Menu {
            Button("Registrar com outro horário…") { nav.screen = .log(item.id) }
            if let last {
                Button("Desfazer dose de \(Format.day(last.date, now: store.now)) \(Format.time(last.date))") {
                    store.delete(last)
                }
            }
            Divider()
            Button("Editar \(item.name)…") { nav.screen = .edit(item) }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .opacity(hovering ? 1 : 0.35)
    }
}

import NeyKit
import SwiftUI

/// Tela de app (janela do NeyHub, ou do avulso no modo Janela): o popover com espaço, mesmos dados e ações.
/// Abas Hoje, Histórico e Itens; editar abre ao lado da lista, registrar e novo contador abrem por cima.
struct ScreenView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var nav: Nav
    @EnvironmentObject private var reminders: Reminders

    /// Aba de baixo: editar é da aba Itens; registrar e novo contador ficam sobre a aba de onde vieram.
    private var tab: Screen {
        switch nav.screen {
        case .today, .history, .items: nav.screen
        case .edit: .items
        case .log, .newCounter: nav.origin
        }
    }

    var body: some View {
        GeometryReader { geometry in
            // Abaixo disso as colunas empilham.
            let wide = geometry.size.width >= 700
            let inner = geometry.size.width - 44
            VStack(alignment: .leading, spacing: 14) {
                ReadOnlyBanner()
                header(wide: wide)
                ScrollView(showsIndicators: false) {
                    Group {
                        switch tab {
                        case .history: history
                        case .items: items(wide: wide, width: inner)
                        default: today(wide: wide, width: inner)
                        }
                    }
                    .frame(width: inner)
                    .padding(.bottom, 20)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
        }
        .frame(minWidth: 460, minHeight: 360)
        .foregroundStyle(Grafite.text)
        .background(Grafite.bg)
        .tint(Grafite.accent)
        .environment(\.colorScheme, .dark)
        .overlay { form }
    }

    // MARK: Cabeçalho

    @ViewBuilder private func header(wide: Bool) -> some View {
        let title = VStack(alignment: .leading, spacing: 2) {
            Text(Format.long(store.now).capitalizedFirst).font(.system(size: 18, weight: .bold)).foregroundStyle(Grafite.strong)
            if let summary { Text(summary).font(.system(size: 12)).foregroundStyle(Grafite.muted) }
        }
        let controls = HStack(spacing: 12) {
            tabs
            GPill(title: "+ Novo") { nav.screen = .edit(nil) }
        }
        if wide {
            HStack(alignment: .bottom, spacing: 12) { title; Spacer(minLength: 8); controls }
        } else {
            VStack(alignment: .leading, spacing: 10) { title; controls }
        }
    }

    /// "Falta 3 de 5 · 2 atrasados", com a mesma conta do popover.
    private var summary: String? {
        let scheduled = store.active.filter { $0.schedule.isScheduled }
        let today = scheduled.filter { if case .later = store.status(of: $0) { false } else { true } }.count
        guard today > 0 else { return nil }
        var missing = 0, late = 0
        for item in scheduled {
            guard case .pending(let since) = store.status(of: item) else { continue }
            missing += 1
            if Format.days(from: since, to: store.now) > 0 { late += 1 }
        }
        if missing == 0 { return "Tudo tomado hoje" }
        return "Falta \(missing) de \(today)" + (late > 0 ? " · \(late) \(late == 1 ? "atrasado" : "atrasados")" : "")
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach([(Screen.today, "Hoje"), (.history, "Histórico"), (.items, "Itens")], id: \.1) { screen, title in
                let on = tab == screen
                Button { nav.screen = screen } label: {
                    Text(title).font(.system(size: 12)).foregroundStyle(on ? Grafite.strong : Grafite.muted)
                        .padding(.horizontal, 11).padding(.vertical, 4)
                        .background(on ? Grafite.ghostBorder : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Grafite.card, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Grafite.cardBorder, lineWidth: 1))
    }

    // MARK: Hoje

    @ViewBuilder private func today(wide: Bool, width: CGFloat) -> some View {
        if store.active.isEmpty {
            ScreenCard { Welcome() }
        } else if wide {
            // 1,35 : 1, como no mockup.
            let left = (width - 14) * 1.35 / 2.35
            HStack(alignment: .top, spacing: 14) {
                agendaColumn.frame(width: left)
                sideColumn.frame(width: width - 14 - left)
            }
        } else {
            VStack(spacing: 12) { agendaColumn; sideColumn }
        }
    }

    private var agendaColumn: some View {
        let agenda = store.active.filter { $0.schedule.isScheduled }.sorted { order($0) < order($1) }
        let asNeeded = store.active.filter { $0.schedule == .asNeeded }
        return VStack(spacing: 12) {
            if !reminders.authorized { ScreenCard { NotificationsOff() } }
            if !agenda.isEmpty {
                ScreenCard("Agenda de hoje", note: "por horário") {
                    ForEach(agenda) { ItemRow(item: $0, wide: true) }
                }
            }
            if !asNeeded.isEmpty {
                ScreenCard("Quando precisar") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                        ForEach(asNeeded) { NeedChip(item: $0) }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    /// Atrasados no topo, depois por horário; sem horário no fim do dia e fora do dia por último.
    private func order(_ item: Item) -> (Int, Int) {
        let status = store.status(of: item)
        if case .later = status { return (2, 0) }
        if case .pending(let since) = status, Format.days(from: since, to: store.now) > 0 { return (0, 0) }
        return (1, store.clock(of: item).map { $0.hour * 60 + $0.minute } ?? 24 * 60)
    }

    private var sideColumn: some View {
        let scheduled = store.active.contains { $0.schedule.isScheduled }
        return VStack(spacing: 12) {
            ScreenCard { CounterSection() }
            if scheduled {
                ScreenCard("Últimos 7 dias", link: ("abrir Histórico →", { nav.screen = .history })) {
                    DayGrid(days: 7)
                    DayLegend()
                }
            }
        }
    }

    // MARK: Histórico

    private var history: some View {
        let sites = store.active.filter(\.tracksSite)
        return VStack(spacing: 12) {
            if store.active.contains(where: { $0.schedule.isScheduled }) || !sites.isEmpty {
                ScreenCard("Últimos 14 dias", note: "sequência atual") {
                    DayGrid(days: 14, streaks: true)
                    ForEach(sites) { item in
                        Line().padding(.horizontal, 14).padding(.top, 8)
                        Rotation(item: item)
                    }
                    DayLegend()
                }
            }
            ScreenCard("Registros") {
                if store.intakes.isEmpty {
                    Text("Nada registrado ainda.").foregroundStyle(Grafite.muted).padding(14)
                } else {
                    HistoryDays()
                }
            }
        }
    }

    // MARK: Itens

    @ViewBuilder private func items(wide: Bool, width: CGFloat) -> some View {
        let editing: Item?? = if case .edit(let item) = nav.screen { .some(item) } else { nil }
        let list = ScreenCard("Itens") { ItemList(selected: editing??.id) }
        let side = ScreenCard {
            if let editing {
                // Trocar de item recria o formulário (o rascunho é estado da view).
                EditView(item: editing).id(editing?.id.uuidString ?? "novo")
            } else {
                Text("Escolha um item para editar, ou + Novo.").foregroundStyle(Grafite.muted).padding(14)
            }
        }
        if wide {
            HStack(alignment: .top, spacing: 14) {
                list.frame(width: min(320, (width - 14) * 0.45))
                side.frame(width: width - 14 - min(320, (width - 14) * 0.45))
            }
        } else {
            VStack(spacing: 12) { side; list }
        }
    }

    // MARK: Por cima

    /// Registrar e novo contador: o mesmo formulário do popover, numa folha sobre a aba.
    @ViewBuilder private var form: some View {
        switch nav.screen {
        case .log(let id):
            if let item = store.item(id) { sheet { LogView(item: item) } }
        case .newCounter:
            sheet { NewCounterView() }
        default:
            EmptyView()
        }
    }

    private func sheet(@ViewBuilder _ content: () -> some View) -> some View {
        ZStack {
            Color.black.opacity(0.55).onTapGesture { nav.screen = nav.origin }
            content()
                .frame(width: 340)
                .background(Grafite.bg, in: RoundedRectangle(cornerRadius: Grafite.windowRadius))
                .overlay(RoundedRectangle(cornerRadius: Grafite.windowRadius).stroke(Grafite.border, lineWidth: 1))
        }
    }
}

/// Card da tela de app sem recuo próprio: as linhas do popover já trazem o delas.
struct ScreenCard<Content: View>: View {
    var title: String?
    var note: String?
    var link: (String, () -> Void)?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, note: String? = nil, link: (String, () -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.note = note; self.link = link; self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                HStack {
                    GSectionLabel(title)
                    Spacer()
                    if let note { Text(note).font(.system(size: 10)).foregroundStyle(Grafite.muted) }
                    if let link {
                        Button(action: link.1) { Text(link.0).font(.system(size: 10)).foregroundStyle(Grafite.accent) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 4)
            }
            content
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Grafite.card, in: RoundedRectangle(cornerRadius: Grafite.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Grafite.cardRadius).stroke(Grafite.cardBorder, lineWidth: 1))
    }
}

/// "Quando precisar" como botão grande: clicar registra agora, como a cápsula "+" do popover.
struct NeedChip: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var nav: Nav
    let item: Item

    var body: some View {
        let today = store.intakes(of: item).filter { $0.date >= Calendar.current.startOfDay(for: store.now) }
        HStack(alignment: .top, spacing: 4) {
            Button { nav.take(item, store: store) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("+").foregroundStyle(item.tint.color)
                        Text(item.name).foregroundStyle(Grafite.strong).lineLimit(1)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    Text(today.last.map { "\(today.count)× hoje · última \(Format.time($0.date))" } ?? "nenhum hoje")
                        .font(.system(size: 10)).foregroundStyle(Grafite.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Registrar agora")
            ItemMenu(item: item, hovering: true)
        }
        .padding(8)
        .background(Grafite.selected, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Grafite.cardBorder, lineWidth: 1))
    }
}

/// Grade de dias por item com horário: completo, parcial, esquecido. Com `streaks`, a sequência atual dos diários.
struct DayGrid: View {
    @EnvironmentObject private var store: Store
    let days: Int
    var streaks = false

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: store.now)
        let dates = (0..<days).reversed().map { calendar.date(byAdding: .day, value: -$0, to: today)! }
        let nameWidth: CGFloat = days <= 7 ? 96 : 120
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                Color.clear.frame(width: nameWidth, height: 1)
                ForEach(dates, id: \.self) { date in
                    Text(days <= 7 ? Format.weekdays[calendar.component(.weekday, from: date) - 1].prefix(1).uppercased()
                                   : "\(calendar.component(.day, from: date))")
                        .font(.system(size: 9)).foregroundStyle(Grafite.label).frame(maxWidth: .infinity)
                }
            }
            ForEach(store.active.filter { $0.schedule.isScheduled }) { item in
                HStack(spacing: 3) {
                    HStack(spacing: 4) {
                        Text(item.name).lineLimit(1)
                        // Mesmo corte do popover ("Sequências"): só a partir de 2 dias.
                        if streaks, item.schedule == .daily, case let streak = store.streak(of: item), streak > 1 {
                            Text("\(streak)").fontWeight(.bold).foregroundStyle(Grafite.accent)
                        }
                    }
                    .font(.system(size: 10))
                    .frame(width: nameWidth, alignment: .leading)
                    ForEach(dates, id: \.self) { date in
                        RoundedRectangle(cornerRadius: 3).fill(store.mark(of: item, on: date).color)
                            .frame(maxWidth: .infinity).frame(height: 14)
                            .help("\(item.name), \(Format.date(date))")
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }
}

/// ■ completo ■ parcial ■ esquecido
struct DayLegend: View {
    var body: some View {
        HStack(spacing: 10) {
            ForEach([(DayMark.done, "completo"), (.partial, "parcial"), (.missed, "esquecido")], id: \.1) { mark, label in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(mark.color).frame(width: 8, height: 8)
                    Text(label)
                }
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(Grafite.muted)
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }
}

/// "Última aplicação: há 8 dias, coxa esquerda · rodízio sugere abdômen direito"
struct Rotation: View {
    @EnvironmentObject private var store: Store
    let item: Item

    var body: some View {
        let last = store.intakes(of: item).last { $0.site != nil }
        let lastText = last.flatMap { intake in intake.site.map { "Última aplicação: \(Format.ago(intake.date, now: store.now)), \($0.label.lowercased())" } }
        VStack(alignment: .leading, spacing: 1) {
            Text(item.name).fontWeight(.semibold).foregroundStyle(Grafite.strong)
            Text("\(lastText ?? "Nenhuma aplicação registrada") · rodízio sugere \(store.suggestedSite(for: item).label.lowercased())")
                .font(.system(size: 10)).foregroundStyle(Grafite.muted)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }
}

extension DayMark {
    // As do mockup aprovado.
    var color: Color {
        switch self {
        case .done: Grafite.accent
        case .partial: Grafite.color(hex: "#5b7a1c") ?? .clear
        case .missed: Grafite.color(hex: "#3a1c1c") ?? .clear
        case .none: Grafite.color(hex: "#24262b") ?? .clear
        }
    }
}

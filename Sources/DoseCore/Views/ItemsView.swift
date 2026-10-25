import NeyKit
import ServiceManagement
import SwiftUI

struct ItemsView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var nav: Nav
    @EnvironmentObject private var shell: Shell
    /// Lido no onAppear e só no avulso: hospedado o SMAppService.mainApp é o NeyHub.
    @ViewState private var openAtLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Header(title: "Itens", back: { nav.screen = .today }) {
                IconButton(symbol: "plus", help: "Novo item") { nav.screen = .edit(nil) }
            }
            Line()
            ItemList()
            Line()
            VStack(alignment: .leading, spacing: 8) {
                if shell.state.showsUpdate {
                    HStack {
                        Text("Atualização pronta — entra ao sair").font(.system(size: 11)).foregroundStyle(Grafite.accent)
                        Spacer()
                        GPill(title: "Reiniciar agora") { shell.relaunch() }.accessibilityLabel("Reiniciar o Dose agora")
                    }
                }
                if shell.state.showsLoginItem {
                    SwitchRow(title: "Abrir ao iniciar o Mac", isOn: Binding(get: { openAtLogin }, set: { setOpenAtLogin($0) }))
                }
                HStack(spacing: 6) {
                    Chip(title: "Abrir pasta dos dados") {
                        NSWorkspace.shared.activateFileViewerSelecting([Store.defaultURL])
                    }
                    if shell.state.showsSettings { Chip(title: "Configurações…") { shell.showSettings() } }
                    Spacer()
                    if shell.state.showsQuit { Chip(title: "Sair do Dose") { NSApp.terminate(nil) } }
                }
            }
            .padding(14)
        }
        .onAppear { if shell.state.showsLoginItem { openAtLogin = SMAppService.mainApp.status == .enabled } }
    }

    private func setOpenAtLogin(_ on: Bool) {
        openAtLogin = on
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            debugLog("abrir ao iniciar: \(on)")
        } catch {
            debugLog("abrir ao iniciar falhou: \(error)")
            openAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// Lista dos itens; na tela de app, o que está aberto ao lado fica marcado.
struct ItemList: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var nav: Nav
    var selected: UUID?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(store.active) { item in
                Button { nav.screen = .edit(item) } label: {
                    HStack(spacing: 10) {
                        Circle().fill(item.tint.color).frame(width: 9, height: 9)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.dose.isEmpty ? item.title : "\(item.title), \(item.dose)")
                            Text(item.scheduleLabel + (item.tracksSite ? ", com local" : ""))
                                .font(.caption).foregroundStyle(Grafite.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Grafite.label)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(selected == item.id ? Grafite.selected : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

struct EditView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var nav: Nav
    private let isNew: Bool
    @ViewState private var draft: Item
    @ViewState private var confirmDelete = false

    private enum Kind: Hashable { case daily, weekdays, interval, asNeeded, counter }
    private var isCounter: Bool { draft.schedule == .counter }

    init(item: Item?) {
        isNew = item == nil
        _draft = ViewState(wrappedValue: item ?? Item(name: "", dose: "", schedule: .daily, times: [Clock(hour: 9, minute: 0)]))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Header(title: isNew ? "Novo item" : draft.title, back: { nav.screen = nav.origin })
            Line()
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    label(isCounter ? "Dias sem" : "Nome")
                    TextField("", text: $draft.name, prompt: Text(isCounter ? "comer doce" : "Vitamina C"))
                }
                if !isCounter {
                    GridRow {
                        label("Dose")
                        TextField("", text: $draft.dose, prompt: Text("5 g, 1 cápsula, 2,5 mg…"))
                    }
                }
                GridRow {
                    label("Frequência")
                    Picker("", selection: kind) {
                        Text("Todo dia").tag(Kind.daily)
                        Text("Dias da semana").tag(Kind.weekdays)
                        Text("A cada N dias").tag(Kind.interval)
                        Text("Quando precisar").tag(Kind.asNeeded)
                        Divider()
                        Text("Contador de dias sem…").tag(Kind.counter)
                    }
                    .labelsHidden()
                }
                if isCounter, isNew {
                    GridRow {
                        label("Última vez")
                        DatePicker("", selection: $draft.created, in: ...Date(), displayedComponents: .date)
                            .labelsHidden()
                    }
                }
                if case .weekdays(let days) = draft.schedule {
                    GridRow {
                        label("Dias")
                        HStack(spacing: 4) {
                            // Segunda primeiro, como no calendário brasileiro de parede.
                            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                                let on = days.contains(day)
                                Button { toggle(day) } label: {
                                    Text(Format.weekdays[day - 1].prefix(1).uppercased())
                                        .font(.callout.weight(.semibold))
                                        .frame(width: 26, height: 26)
                                        .foregroundStyle(on ? Color.white : Grafite.text)
                                        .background(Circle().fill(on ? draft.tint.color : Grafite.card))
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .help(Format.weekdays[day - 1].capitalized)
                            }
                        }
                    }
                }
                if case .interval(let every) = draft.schedule {
                    GridRow {
                        label("A cada")
                        Stepper(value: interval, in: 2...90) {
                            Text("\(every) dias").monospacedDigit()
                        }
                    }
                }
                if draft.schedule.isScheduled {
                    GridRow(alignment: .firstTextBaseline) {
                        label("Horários")
                        VStack(alignment: .leading, spacing: 6) {
                            // Cada horário é uma dose do dia.
                            ForEach(draft.times.indices, id: \.self) { index in
                                HStack(spacing: 6) {
                                    DatePicker("", selection: time(at: index), displayedComponents: .hourAndMinute)
                                        .labelsHidden()
                                    Button { draft.times.remove(at: index) } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Tirar esse horário")
                                    if index == 0 {
                                        Text(draft.times.count == 1 ? "1 dose por dia" : "\(draft.times.count) doses por dia")
                                            .font(.caption).foregroundStyle(Grafite.muted)
                                    }
                                }
                            }
                            Button {
                                // Próximo horário 3 h depois do último (pra 08:00 sugere 11:00).
                                let last = draft.times.max() ?? Clock(hour: 6, minute: 0)
                                draft.times.append(Clock(hour: min(23, last.hour + 3), minute: last.minute))
                            } label: {
                                Label(draft.times.isEmpty ? "Adicionar horário" : "Outra dose no dia", systemImage: "plus")
                                    .foregroundStyle(Grafite.accent)
                            }
                            .buttonStyle(.borderless)
                            if draft.times.isEmpty {
                                Text("Sem horário: 1 dose por dia, sem aviso.").font(.caption).foregroundStyle(Grafite.muted)
                            } else {
                                SwitchRow(title: "Avisar nesses horários", isOn: $draft.remind)
                            }
                        }
                    }
                }
                if !isCounter {
                    GridRow {
                        label("Local")
                        SwitchRow(title: "Pedir o local da aplicação", isOn: $draft.tracksSite)
                    }
                }
                GridRow {
                    label("Cor")
                    HStack(spacing: 6) {
                        ForEach(Tint.allCases, id: \.self) { tint in
                            Button { draft.tint = tint } label: {
                                Circle().fill(tint.color).frame(width: 18, height: 18)
                                    .overlay(Circle().strokeBorder(.primary.opacity(draft.tint == tint ? 0.8 : 0), lineWidth: 2)
                                        .padding(-3))
                            }
                            .buttonStyle(.plain)
                            .help(tint.rawValue)
                        }
                    }
                    .padding(.leading, 3)
                }
            }
            .padding(14)

            HStack {
                if !isNew {
                    FormButton(title: "Excluir", destructive: true) { confirmDelete = true }
                }
                Spacer()
                FormButton(title: "Cancelar") { nav.screen = nav.origin }
                FormButton(title: "Salvar", style: .primary) {
                    draft.name = draft.name.trimmingCharacters(in: .whitespaces)
                    draft.dose = draft.dose.trimmingCharacters(in: .whitespaces)
                    draft.times = Array(Set(draft.times)).sorted()
                    store.upsert(draft)
                    nav.screen = nav.origin
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding([.horizontal, .bottom], 14)
        }
        .onAppear {
            // Item novo ganha a primeira cor que ninguém usa ainda.
            guard isNew else { return }
            draft.tint = Tint.allCases.first { tint in !store.active.contains { $0.tint == tint } } ?? .teal
        }
        .confirmationDialog("Excluir \(draft.title)?", isPresented: $confirmDelete) {
            Button("Excluir", role: .destructive) {
                store.archive(draft)
                nav.screen = nav.origin
            }
        } message: {
            Text("O histórico de doses continua guardado.")
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).foregroundStyle(Grafite.muted).gridColumnAlignment(.trailing)
    }

    // MARK: Bindings que traduzem o formulário pro modelo

    private var kind: Binding<Kind> {
        Binding {
            switch draft.schedule {
            case .daily: .daily
            case .weekdays: .weekdays
            case .interval: .interval
            case .asNeeded: .asNeeded
            case .counter: .counter
            }
        } set: { kind in
            switch kind {
            case .daily: draft.schedule = .daily
            case .weekdays: draft.schedule = .weekdays([Calendar.current.component(.weekday, from: Date())])
            case .interval: draft.schedule = .interval(days: 2)
            case .asNeeded: draft.schedule = .asNeeded
            case .counter:
                draft.schedule = .counter
                draft.dose = ""
                draft.tracksSite = false
            }
            if !draft.schedule.isScheduled { draft.times = [] }
        }
    }

    /// Liga/desliga um dia; não deixa ficar sem nenhum.
    private func toggle(_ day: Int) {
        guard case .weekdays(var days) = draft.schedule else { return }
        if let index = days.firstIndex(of: day) {
            guard days.count > 1 else { return }
            days.remove(at: index)
        } else {
            days.append(day)
        }
        draft.schedule = .weekdays(days)
    }

    private var interval: Binding<Int> {
        Binding {
            if case .interval(let days) = draft.schedule { return days }
            return 2
        } set: {
            draft.schedule = .interval(days: $0)
        }
    }

    /// Horário de uma dose; confere o índice porque a linha pode ter acabado de ser removida.
    private func time(at index: Int) -> Binding<Date> {
        Binding {
            (draft.times.indices.contains(index) ? draft.times[index] : Clock(hour: 9, minute: 0)).on(Date())
        } set: {
            guard draft.times.indices.contains(index) else { return }
            let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
            draft.times[index] = Clock(hour: parts.hour ?? 9, minute: parts.minute ?? 0)
        }
    }
}

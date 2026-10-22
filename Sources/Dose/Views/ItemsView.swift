import ServiceManagement
import SwiftUI

struct ItemsView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var nav: Nav
    @ViewState private var openAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Header(title: "Itens", back: { nav.screen = .today }) {
                IconButton(symbol: "plus", help: "Novo item") { nav.screen = .edit(nil) }
            }
            Divider()
            VStack(spacing: 0) {
                ForEach(store.active) { item in
                    Button { nav.screen = .edit(item) } label: {
                        HStack(spacing: 10) {
                            Circle().fill(item.tint.color).frame(width: 9, height: 9)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.dose.isEmpty ? item.title : "\(item.title), \(item.dose)")
                                Text(item.scheduleLabel + (item.tracksSite ? ", com local" : ""))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Abrir ao iniciar o Mac", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, on in setOpenAtLogin(on) }
                HStack {
                    Button("Abrir pasta dos dados") {
                        NSWorkspace.shared.activateFileViewerSelecting([Store.defaultURL])
                    }
                    Spacer()
                    Button("Sair do Dose") { NSApp.terminate(nil) }
                }
            }
            .padding(14)
        }
    }

    private func setOpenAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            debugLog("abrir ao iniciar: \(on)")
        } catch {
            debugLog("abrir ao iniciar falhou: \(error)")
            openAtLogin = SMAppService.mainApp.status == .enabled
        }
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
        _draft = ViewState(wrappedValue: item ?? Item(name: "", dose: "", schedule: .daily, reminder: Clock(hour: 9, minute: 0)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Header(title: isNew ? "Novo item" : draft.title, back: { nav.screen = nav.origin })
            Divider()
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
                                        .foregroundStyle(on ? Color.white : Color.primary)
                                        .background(Circle().fill(on ? draft.tint.color : Color.primary.opacity(0.07)))
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
                    GridRow {
                        label("Lembrete")
                        HStack {
                            Toggle("", isOn: hasReminder).labelsHidden()
                            if draft.reminder != nil {
                                DatePicker("", selection: reminderTime, displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                            }
                            Spacer()
                        }
                    }
                }
                if !isCounter {
                    GridRow {
                        label("Local")
                        Toggle("Pedir o local da aplicação", isOn: $draft.tracksSite)
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
                    Button("Excluir", role: .destructive) { confirmDelete = true }
                }
                Spacer()
                Button("Cancelar") { nav.screen = nav.origin }
                Button("Salvar") {
                    draft.name = draft.name.trimmingCharacters(in: .whitespaces)
                    draft.dose = draft.dose.trimmingCharacters(in: .whitespaces)
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
        Text(text).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
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
            if !draft.schedule.isScheduled {
                draft.reminder = nil
            } else if draft.reminder == nil {
                draft.reminder = Clock(hour: 9, minute: 0)
            }
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

    private var hasReminder: Binding<Bool> {
        Binding { draft.reminder != nil } set: { draft.reminder = $0 ? Clock(hour: 9, minute: 0) : nil }
    }

    private var reminderTime: Binding<Date> {
        Binding {
            (draft.reminder ?? Clock(hour: 9, minute: 0)).on(Date())
        } set: {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
            draft.reminder = Clock(hour: parts.hour ?? 9, minute: parts.minute ?? 0)
        }
    }
}

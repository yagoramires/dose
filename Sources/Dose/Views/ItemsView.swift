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
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.dose.isEmpty ? item.name : "\(item.name) · \(item.dose)")
                                Text(item.scheduleLabel + (item.tracksSite ? " · com local" : ""))
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

    private enum Kind: Hashable { case daily, weekly, asNeeded }

    init(item: Item?) {
        isNew = item == nil
        _draft = ViewState(wrappedValue: item ?? Item(name: "", dose: "", schedule: .daily, reminder: Clock(hour: 9, minute: 0)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Header(title: isNew ? "Novo item" : draft.name, back: { nav.screen = .items })
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    label("Nome")
                    TextField("", text: $draft.name, prompt: Text("Vitamina C"))
                }
                GridRow {
                    label("Dose")
                    TextField("", text: $draft.dose, prompt: Text("5 g, 1 cápsula, 2,5 mg…"))
                }
                GridRow {
                    label("Frequência")
                    Picker("", selection: kind) {
                        Text("Todo dia").tag(Kind.daily)
                        Text("Uma vez por semana").tag(Kind.weekly)
                        Text("Quando precisar").tag(Kind.asNeeded)
                    }
                    .labelsHidden()
                }
                if case .weekly = draft.schedule {
                    GridRow {
                        label("Dia")
                        Picker("", selection: weekday) {
                            ForEach(1...7, id: \.self) { Text(Format.weekdays[$0 - 1].capitalized).tag($0) }
                        }
                        .labelsHidden()
                    }
                }
                if draft.schedule != .asNeeded {
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
                GridRow {
                    label("Local")
                    Toggle("Pedir o local da aplicação", isOn: $draft.tracksSite)
                }
            }
            .padding(14)

            HStack {
                if !isNew {
                    Button("Excluir", role: .destructive) { confirmDelete = true }
                }
                Spacer()
                Button("Cancelar") { nav.screen = .items }
                Button("Salvar") {
                    draft.name = draft.name.trimmingCharacters(in: .whitespaces)
                    draft.dose = draft.dose.trimmingCharacters(in: .whitespaces)
                    store.upsert(draft)
                    nav.screen = .items
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding([.horizontal, .bottom], 14)
        }
        .confirmationDialog("Excluir \(draft.name)?", isPresented: $confirmDelete) {
            Button("Excluir", role: .destructive) {
                store.archive(draft)
                nav.screen = .items
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
            case .weekly: .weekly
            case .asNeeded: .asNeeded
            }
        } set: { kind in
            switch kind {
            case .daily: draft.schedule = .daily
            case .weekly: draft.schedule = .weekly(weekday: Calendar.current.component(.weekday, from: Date()))
            case .asNeeded: draft.schedule = .asNeeded
            }
            if kind == .asNeeded { draft.reminder = nil }
        }
    }

    private var weekday: Binding<Int> {
        Binding {
            if case .weekly(let weekday) = draft.schedule { return weekday }
            return 1
        } set: {
            draft.schedule = .weekly(weekday: $0)
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

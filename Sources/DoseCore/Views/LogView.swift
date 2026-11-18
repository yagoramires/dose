import NeyKit
import SwiftUI

/// Registrar uma dose: horário (padrão agora) e, nos injetáveis, o local no mapa do corpo.
struct LogView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var nav: Nav
    let item: Item
    @ViewState private var date = Date()
    @ViewState private var site: Site?

    private var subtitle: String {
        if item.schedule == .counter { return "Quando foi a última vez" }
        return item.dose.isEmpty ? "Registrar dose" : "Registrar \(item.dose)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Header(title: item.title, subtitle: subtitle, back: { nav.screen = .today })
            Line()
            VStack(alignment: .leading, spacing: 14) {
                WhenPicker(item: item, date: $date)

                if item.tracksSite {
                    VStack(alignment: .leading, spacing: 8) {
                        LastSite(item: item)
                        SectionText(text: "Local desta aplicação")
                        BodyMap(item: item, selection: $site)
                        Text("Esquerdo e direito do seu corpo. A sugestão é o local usado há mais tempo.")
                            .font(.caption).foregroundStyle(Grafite.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack {
                    Spacer()
                    FormButton(title: "Cancelar") { nav.screen = .today }
                    FormButton(title: confirmTitle, style: .primary) {
                        store.take(item, at: date, site: site)
                        nav.screen = .today
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(item.tracksSite && site == nil)
                }
            }
            .padding(14)
        }
        .onAppear {
            if item.tracksSite, site == nil { site = store.suggestedSite(for: item) }
        }
    }

    /// Diz o que vai ser gravado: "Registrar agora", "Registrar ontem às 21:30".
    private var confirmTitle: String {
        let verb = item.schedule == .counter ? "Zerar" : "Registrar"
        if abs(date.timeIntervalSinceNow) < 60 { return "\(verb) agora" }
        return "\(verb) \(Format.day(date)) às \(Format.time(date))"
    }
}

/// Quando: atalhos de um clique, a última semana e o horário em passos de 15 min (ou digitado).
/// Mais longe que uma semana (contador zerado há tempo), o calendário do botão ao lado dos dias.
struct WhenPicker: View {
    @EnvironmentObject private var store: Store
    let item: Item
    @Binding var date: Date
    @ViewState private var typing = false
    @ViewState private var typed = ""
    @ViewState private var calendarOpen = false
    @FocusState private var focused: Bool

    private let calendar = Calendar.current
    /// Mesmo limite de antes: até 1 h no futuro (registrar um pouco antes de tomar).
    private var limit: Date { Date().addingTimeInterval(60 * 60) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionText(text: "Quando")
            HStack(spacing: 6) {
                quick("Agora", Date())
                // O último horário do item que já chegou hoje (ou chega dentro do limite).
                if let clock = item.times.sorted().last(where: { $0.on(Date()) <= limit }) {
                    quick("No horário, \(clock.label)", clock.on(Date()))
                }
                quick("Há 1 h", Date().addingTimeInterval(-60 * 60))
            }
            HStack(spacing: 4) {
                ForEach((0..<7).reversed(), id: \.self) { back in dayButton(back) }
                Button { calendarOpen = true } label: {
                    Image(systemName: "calendar").foregroundStyle(Grafite.muted).frame(width: 30, height: 44)
                        .background(Grafite.card, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Grafite.cardBorder, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Outro dia")
                .popover(isPresented: $calendarOpen) {
                    DatePicker("", selection: dayBinding, in: ...limit, displayedComponents: .date)
                        .datePickerStyle(.graphical).labelsHidden().padding(10)
                }
            }
            HStack(spacing: 14) {
                step(-15)
                timeField
                step(15)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
    }

    private func set(_ new: Date) { date = min(new, limit) }

    private var dayBinding: Binding<Date> {
        Binding(get: { date }, set: { day in
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            set(calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: day) ?? day)
        })
    }

    private func quick(_ title: String, _ value: Date) -> some View {
        let on = abs(date.timeIntervalSince(value)) < 60
        return Button { set(value) } label: {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(on ? Grafite.accent : Grafite.text)
                .padding(.horizontal, 9).frame(height: 26)
                .background(on ? Grafite.accent.opacity(0.14) : Grafite.card, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(on ? Grafite.accent.opacity(0.55) : Grafite.cardBorder, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dayButton(_ back: Int) -> some View {
        let day = calendar.date(byAdding: .day, value: -back, to: calendar.startOfDay(for: Date()))!
        let on = calendar.isDate(date, inSameDayAs: day)
        let next = calendar.date(byAdding: .day, value: 1, to: day)!
        let logged = store.intakes(of: item).contains { $0.date >= day && $0.date < next }
        return Button { dayBinding.wrappedValue = day } label: {
            VStack(spacing: 2) {
                Text(back == 0 ? "hoje" : day.formatted(.dateTime.weekday(.abbreviated)).lowercased().replacingOccurrences(of: ".", with: ""))
                    .font(.system(size: 9)).foregroundStyle(Grafite.ghostText)
                Text("\(calendar.component(.day, from: day))").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(on ? Grafite.accent : Grafite.text)
                Circle().fill(logged ? item.tint.color : .clear).frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity).frame(height: 44)
            .background(on ? Grafite.accent.opacity(0.14) : Grafite.card, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(on ? Grafite.accent.opacity(0.6) : Grafite.cardBorder, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(logged ? "Já tem registro nesse dia" : Format.date(day))
    }

    private func step(_ minutes: Int) -> some View {
        Button { set(date.addingTimeInterval(Double(minutes) * 60)) } label: {
            Image(systemName: minutes < 0 ? "minus" : "plus").font(.system(size: 12, weight: .semibold)).foregroundStyle(Grafite.text)
                .frame(width: 30, height: 30)
                .background(Grafite.card, in: Circle())
                .overlay(Circle().strokeBorder(Grafite.cardBorder, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(minutes < 0 ? "15 min antes" : "15 min depois")
    }

    /// O horário grande; um clique vira campo pra digitar "21:30" (ou "2130").
    @ViewBuilder private var timeField: some View {
        let font = Font.system(size: 34, weight: .light).monospacedDigit()
        if typing {
            TextField("hh:mm", text: $typed)
                .textFieldStyle(.plain).font(font).multilineTextAlignment(.center).frame(width: 110)
                .focused($focused)
                .onSubmit(commit)
                .onExitCommand { typing = false }
                .onChange(of: focused) { if !$0 { commit() } }
        } else {
            Button { typed = Format.time(date); typing = true; focused = true } label: {
                Text(Format.time(date)).font(font).foregroundStyle(Grafite.strong).frame(width: 110)
            }
            .buttonStyle(.plain)
            .help("Clique para digitar o horário")
        }
    }

    private func commit() {
        defer { typing = false }
        let digits = typed.filter(\.isNumber)
        guard digits.count >= 3, digits.count <= 4, let value = Int(digits) else { return }
        let hour = value / 100, minute = value % 100
        guard hour < 24, minute < 60, let new = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) else { return }
        set(new)
    }
}

/// Onde foi a aplicação anterior, pra não repetir o lugar.
struct LastSite: View {
    @EnvironmentObject private var store: Store
    let item: Item

    var body: some View {
        if let last = store.lastSiteIntake(of: item), let site = last.site {
            HStack(spacing: 10) {
                Image(systemName: "mappin.and.ellipse").font(.title3).foregroundStyle(item.tint.color)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Última aplicação").font(.caption).foregroundStyle(Grafite.muted)
                    Text(site.label).fontWeight(.semibold).foregroundStyle(Grafite.strong)
                    Text("\(Format.ago(last.date, now: store.now).capitalizedFirst), \(Format.day(last.date, now: store.now)) às \(Format.time(last.date))")
                        .font(.caption).foregroundStyle(Grafite.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: Grafite.cardRadius).fill(item.tint.color.opacity(0.12)))
        } else {
            Text("Nenhuma aplicação registrada ainda. Se já aplicou antes, mude a data em Quando e marque o local.")
                .font(.caption).foregroundStyle(Grafite.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct BodyMap: View {
    @EnvironmentObject private var store: Store
    let item: Item
    @Binding var selection: Site?

    var body: some View {
        let used = store.lastUse(of: item)
        let suggested = store.suggestedSite(for: item)
        let lastSite = store.lastSiteIntake(of: item)?.site
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Text("Esquerdo").font(.caption).foregroundStyle(Grafite.muted).frame(maxWidth: .infinity)
                Text("Direito").font(.caption).foregroundStyle(Grafite.muted).frame(maxWidth: .infinity)
            }
            ForEach(Site.rows, id: \.left) { row in
                GridRow {
                    Text(row.left.region).font(.callout)
                    cell(row.left, used: used[row.left], suggested: suggested == row.left, last: lastSite == row.left)
                    cell(row.right, used: used[row.right], suggested: suggested == row.right, last: lastSite == row.right)
                }
            }
        }
    }

    private func cell(_ site: Site, used: Date?, suggested: Bool, last: Bool) -> some View {
        let selected = selection == site
        return Button { selection = site } label: {
            VStack(spacing: 1) {
                Text(Format.ago(used, now: store.now)).font(.callout)
                if suggested {
                    Text("sugerido").font(.caption2.weight(.semibold))
                        .foregroundStyle(selected ? Grafite.onAccent.opacity(0.75) : Grafite.accent)
                } else if last {
                    Text("última").font(.caption2.weight(.semibold))
                        .foregroundStyle(selected ? Grafite.onAccent.opacity(0.75) : Grafite.warn)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .foregroundStyle(selected ? Grafite.onAccent : Grafite.text)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Grafite.accent : Grafite.card))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(suggested && !selected ? Grafite.accent : Grafite.cardBorder, lineWidth: suggested && !selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(site.label)
    }
}

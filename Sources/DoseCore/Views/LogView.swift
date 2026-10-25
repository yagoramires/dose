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
                DatePicker("Quando", selection: $date, in: ...Date().addingTimeInterval(60 * 60))
                    .datePickerStyle(.compact)

                if item.tracksSite {
                    VStack(alignment: .leading, spacing: 8) {
                        LastSite(item: item)
                        GSectionLabel("Local desta aplicação")
                        BodyMap(item: item, selection: $site)
                        Text("Esquerdo e direito do seu corpo. A sugestão é o local usado há mais tempo.")
                            .font(.caption).foregroundStyle(Grafite.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack {
                    Spacer()
                    FormButton(title: "Cancelar") { nav.screen = .today }
                    FormButton(title: item.schedule == .counter ? "Zerar contador" : "Registrar", style: .primary) {
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
}

/// Onde foi a aplicação anterior, pra não repetir o lugar.
struct LastSite: View {
    @EnvironmentObject private var store: Store
    let item: Item

    var body: some View {
        if let last = store.intakes(of: item).last(where: { $0.site != nil }), let site = last.site {
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
        let lastSite = store.intakes(of: item).last(where: { $0.site != nil })?.site
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Text("Esquerdo").font(.caption).foregroundStyle(Grafite.muted).frame(maxWidth: .infinity)
                Text("Direito").font(.caption).foregroundStyle(Grafite.muted).frame(maxWidth: .infinity)
            }
            ForEach(Site.rows, id: \.region) { row in
                GridRow {
                    Text(row.region).font(.callout)
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

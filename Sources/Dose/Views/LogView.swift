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
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                DatePicker("Quando", selection: $date, in: ...Date().addingTimeInterval(60 * 60))
                    .datePickerStyle(.compact)

                if item.tracksSite {
                    VStack(alignment: .leading, spacing: 8) {
                        LastSite(item: item)
                        Text("Local desta aplicação").font(.subheadline.weight(.medium))
                        BodyMap(item: item, selection: $site)
                        Text("Esquerdo e direito do seu corpo. A sugestão é o local usado há mais tempo.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack {
                    Spacer()
                    Button("Cancelar") { nav.screen = .today }
                    Button(item.schedule == .counter ? "Zerar contador" : "Registrar") {
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
                    Text("Última aplicação").font(.caption).foregroundStyle(.secondary)
                    Text(site.label).fontWeight(.semibold)
                    Text("\(Format.ago(last.date, now: store.now).capitalizedFirst), \(Format.day(last.date, now: store.now)) às \(Format.time(last.date))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(item.tint.color.opacity(0.12)))
        } else {
            Text("Nenhuma aplicação registrada ainda. Se já aplicou antes, mude a data em Quando e marque o local.")
                .font(.caption).foregroundStyle(.secondary)
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
                Text("Esquerdo").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Text("Direito").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
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
                        .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.accentColor)
                } else if last {
                    Text("última").font(.caption2.weight(.semibold))
                        .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.orange)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor : Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(suggested && !selected ? Color.accentColor : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(site.label)
    }
}

import SwiftUI

/// Registrar uma dose: horário (padrão agora) e, nos injetáveis, o local no mapa do corpo.
struct LogView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var nav: Nav
    let item: Item
    @ViewState private var date = Date()
    @ViewState private var site: Site?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Header(title: item.name, subtitle: item.dose.isEmpty ? "Registrar dose" : "Registrar \(item.dose)",
                   back: { nav.screen = .today })
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                DatePicker("Quando", selection: $date, in: ...Date().addingTimeInterval(60 * 60))
                    .datePickerStyle(.compact)

                if item.tracksSite {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Local da aplicação").font(.subheadline.weight(.medium))
                        BodyMap(item: item, selection: $site)
                        Text("Esquerdo e direito do seu corpo. A sugestão é o local usado há mais tempo.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack {
                    Spacer()
                    Button("Cancelar") { nav.screen = .today }
                    Button("Registrar") {
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

struct BodyMap: View {
    @EnvironmentObject private var store: Store
    let item: Item
    @Binding var selection: Site?

    var body: some View {
        let used = store.lastUse(of: item)
        let suggested = store.suggestedSite(for: item)
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Text("Esquerdo").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Text("Direito").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
            ForEach(Site.rows, id: \.region) { row in
                GridRow {
                    Text(row.region).font(.callout)
                    cell(row.left, used: used[row.left], suggested: suggested == row.left)
                    cell(row.right, used: used[row.right], suggested: suggested == row.right)
                }
            }
        }
    }

    private func cell(_ site: Site, used: Date?, suggested: Bool) -> some View {
        let selected = selection == site
        return Button { selection = site } label: {
            VStack(spacing: 1) {
                Text(Format.ago(used, now: store.now)).font(.callout)
                if suggested {
                    Text("sugerido").font(.caption2.weight(.semibold))
                        .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.accentColor)
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

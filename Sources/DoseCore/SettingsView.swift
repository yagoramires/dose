import NeyKit
import SwiftUI

/// Configurações (card no NeyHub, janela no avulso). Os itens e os lembretes ficam no popover.
struct SettingsView: View {
    @EnvironmentObject private var reminders: Reminders
    let version: String
    /// nil hospedado: o modo é do NeyHub.
    let presence: Presence?
    let onPresence: (Presence) -> Void
    @ViewState private var shown: Presence

    init(version: String, presence: Presence?, onPresence: @escaping (Presence) -> Void) {
        self.version = version; self.presence = presence; self.onPresence = onPresence
        _shown = ViewState(wrappedValue: presence ?? Presence(screen: false, menuBar: true))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dose").font(.system(size: 16, weight: .bold)).foregroundStyle(Grafite.strong)
            Text("Remédios, suplementos e contadores · \(version)").font(.system(size: 12)).foregroundStyle(Grafite.muted)
                .padding(.bottom, 6)
            if presence != nil {
                GCard {
                    VStack(alignment: .leading, spacing: 6) {
                        title("Onde aparece")
                        mode("Janela", note: "Ícone no Dock e a tela do Dose.", \.screen)
                        mode("Barra de menus", note: "A pílula com o que falta hoje.", \.menuBar)
                        Text("Os lembretes chegam em qualquer modo, enquanto o Dose estiver aberto.")
                            .font(.system(size: 11)).foregroundStyle(Grafite.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            GCard {
                HStack {
                    title("Notificações")
                    Spacer()
                    if reminders.authorized {
                        Text("Ligadas").font(.system(size: 11)).foregroundStyle(Grafite.accent)
                    } else {
                        Text("Desligadas").font(.system(size: 11)).foregroundStyle(Grafite.warn)
                        GPill(title: "Ligar") { reminders.openSettings() }
                    }
                }
            }
            Chip(title: "Abrir pasta dos dados") { NSWorkspace.shared.activateFileViewerSelecting([Store.defaultURL]) }
        }
        .padding(18)
        .frame(minWidth: 420, maxWidth: 520, alignment: .leading)
        .grafiteWindow()
    }

    /// Desligar os dois não vale: o outro volta a ligar (`normalized`).
    private func mode(_ label: String, note: String, _ key: WritableKeyPath<Presence, Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 12))
                Text(note).font(.system(size: 11)).foregroundStyle(Grafite.muted)
            }
            Spacer()
            GSwitch(isOn: Binding(get: { shown[keyPath: key] }, set: {
                var next = shown
                next[keyPath: key] = $0
                next = next.normalized(hasScreen: true)
                shown = next
                onPresence(next)
            }), label: label)
        }
    }

    private func title(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(Grafite.strong)
    }
}

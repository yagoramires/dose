import NeyKit
import SwiftUI

enum Screen: Equatable {
    case today
    case history
    case items
    /// nil = item novo.
    case edit(Item?)
    /// Registrar com outro horário e/ou escolher o local.
    case log(UUID)
    case newCounter
}

final class Nav: ObservableObject {
    @Published var screen: Screen = .today {
        didSet { if [.today, .history, .items].contains(oldValue) { origin = oldValue } }
    }
    /// Tela de lista de onde se abriu um formulário: é pra lá que o voltar/salvar leva.
    private(set) var origin: Screen = .today

    /// Marcar pela cápsula: com local, abre o registro pra escolher o lugar; senão marca agora.
    func take(_ item: Item, store: Store) {
        if item.tracksSite { screen = .log(item.id) } else { store.take(item) }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var nav: Nav

    var body: some View {
        Group {
            switch nav.screen {
            case .today: TodayView()
            case .history: HistoryView()
            case .items: ItemsView()
            case .edit(let item): EditView(item: item)
            case .newCounter: NewCounterView()
            case .log(let id):
                if let item = store.item(id) { LogView(item: item) } else { TodayView() }
            }
        }
        .frame(width: 340)
        .tint(Grafite.accent)
        .grafiteWindow()
    }
}

// MARK: Peças comuns

struct Header<Trailing: View>: View {
    var title: String
    var subtitle: String?
    var back: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            if let back {
                Button(action: back) {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold)).foregroundStyle(Grafite.ghostText)
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .help("Voltar")
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(Grafite.strong)
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(Grafite.muted)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

extension Header where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, back: (() -> Void)? = nil) {
        self.init(title: title, subtitle: subtitle, back: back) { EmptyView() }
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).foregroundStyle(Grafite.ghostText).frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

struct SectionTitle: View {
    let text: String

    var body: some View {
        GSectionLabel(text)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }
}

/// Divisória no tom da borda do Grafite (o Divider do sistema some no fundo escuro).
struct Line: View {
    var body: some View { Rectangle().fill(Grafite.border).frame(height: 1) }
}

/// Botão discreto do rodapé, o mesmo do Aero.
struct Chip: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 10)).foregroundStyle(Grafite.muted).fixedSize()
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Grafite.card, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

/// Botões dos formulários: GPill com o apagado de quando não dá pra confirmar. `destructive`: contorno vermelho (Excluir).
struct FormButton: View {
    @Environment(\.isEnabled) private var enabled
    let title: String
    var style: GPill.Style = .ghost
    var destructive = false
    let action: () -> Void

    var body: some View {
        Group {
            if destructive {
                Button(action: action) {
                    Text(title).font(.system(size: 10, weight: .bold)).foregroundStyle(.red)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .overlay(Capsule().stroke(Color.red.opacity(0.5), lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            } else {
                GPill(title: title, style: style, action: action)
            }
        }
        .opacity(enabled ? 1 : 0.4)
    }
}

/// Texto à esquerda e interruptor do Grafite à direita.
struct SwitchRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            GSwitch(isOn: $isOn, label: title)
        }
    }
}

extension Grafite {
    // O Grafite não tem cor de alerta; as mesmas do Aero (mockup aprovado).
    static let warn = color(hex: "#ffb03d") ?? .orange
    static let warnBg = color(hex: "#2a2110") ?? .clear
    static let warnBorder = color(hex: "#5a4416") ?? .clear
}

extension Tint {
    /// Cores do sistema: se ajustam sozinhas ao modo escuro.
    var color: Color { Color(nsColor: nsColor) }

    private var nsColor: NSColor {
        switch self {
        case .teal: .systemTeal
        case .orange: .systemOrange
        case .purple: .systemPurple
        case .pink: .systemPink
        case .blue: .systemBlue
        case .green: .systemGreen
        case .yellow: .systemYellow
        case .brown: .systemBrown
        }
    }
}

extension String {
    /// "quinta-feira, 22 de outubro" → "Quinta-feira, 22 de outubro"
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

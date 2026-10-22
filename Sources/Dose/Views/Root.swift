import SwiftUI

enum Screen: Equatable {
    case today
    case history
    case items
    /// nil = item novo.
    case edit(Item?)
    /// Registrar com outro horário e/ou escolher o local.
    case log(UUID)
}

final class Nav: ObservableObject {
    @Published var screen: Screen = .today
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
            case .log(let id):
                if let item = store.item(id) { LogView(item: item) } else { TodayView() }
            }
        }
        .frame(width: 340)
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
                    Image(systemName: "chevron.left").font(.body.weight(.semibold))
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .help("Voltar")
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
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
            Image(systemName: symbol).frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }
}

/// O mesmo que @State. No SDK atual @State virou macro, e o plugin dele só vem com o Xcode;
/// como o build usa só as CommandLineTools, embrulhamos o State à mão.
@propertyWrapper
struct ViewState<Value>: DynamicProperty {
    private var state: State<Value>

    init(wrappedValue: Value) {
        state = State(initialValue: wrappedValue)
    }

    var wrappedValue: Value {
        get { state.wrappedValue }
        nonmutating set { state.wrappedValue = newValue }
    }

    var projectedValue: Binding<Value> { state.projectedValue }
}

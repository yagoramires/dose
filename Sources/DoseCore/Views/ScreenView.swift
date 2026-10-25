import NeyKit
import SwiftUI

// shortcut: só o lugar da tela de app; a tela de verdade entra depois do mockup aprovado (Task 13 parte B).
struct ScreenView: View {
    var body: some View {
        Text("Tela do Dose")
            .font(.system(size: 13))
            .foregroundStyle(Grafite.muted)
            .frame(minWidth: 480, maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
            .background(Grafite.bg)
            .environment(\.colorScheme, .dark)
    }
}

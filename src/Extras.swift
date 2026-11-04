import SwiftUI

/// Extension point. The public build ships this inert version;
/// a separate private build may replace this file.
@MainActor final class ExtraAccess: ObservableObject {
    @Published var revision = 0
    @Published var panelVisible = false
    nonisolated static var grantsPlus: Bool { false }
    var busy: Bool { false }
    var notice: String { "" }
    func intercept(_ input: String) async -> Bool { false }
    func handleExit() -> Bool { false }
}

struct ExtraPanel: View {
    @ObservedObject var extras: ExtraAccess
    let light: Bool
    let opacity: Double
    let surface: Color
    var body: some View { EmptyView() }
}

struct ExtraOverlay: View {
    @ObservedObject var extras: ExtraAccess
    var body: some View { EmptyView() }
}

struct ExtraTitle: View {
    @ObservedObject var extras: ExtraAccess
    var body: some View { Text("STRÖM") }
}

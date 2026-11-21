import Foundation
import Combine

/// Observable holder for the live tunnel session statistics.
///
/// Kept separate from `AppState` on purpose: the stats refresh once per second while
/// connected, and publishing them through the app-wide `AppState` would re-render every
/// screen (Nodes, Settings, sheets) once per second for no reason. Only the Home screen
/// observes this model.
@MainActor
final class SessionStatsModel: ObservableObject {
    @Published var stats = TunnelSessionStats()

    func reset() {
        stats = TunnelSessionStats()
    }
}

import Foundation

/// One live Terminal tab as the notch lists it.
struct NotchTerminalSession: Identifiable, Sendable, Equatable {
    let id: UUID
    let title: String
    let directory: String
    let isRunning: Bool

    static func runningCount(in sessions: [NotchTerminalSession]) -> Int {
        sessions.count(where: \.isRunning)
    }

    /// Running sessions first: they are the ones worth a glance.
    static func ordered(_ sessions: [NotchTerminalSession]) -> [NotchTerminalSession] {
        sessions.filter(\.isRunning) + sessions.filter { !$0.isRunning }
    }
}

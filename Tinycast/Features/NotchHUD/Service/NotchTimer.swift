import Foundation
import Observation

/// One countdown started from the notch; nothing is scheduled while none is running.
@MainActor
@Observable
final class NotchTimer {
    private(set) var end: Date?

    @ObservationIgnored var onFinished: (() -> Void)?
    @ObservationIgnored private var completion: Task<Void, Never>?

    func start(minutes: Int) {
        let end = NotchTimerPreset.end(afterMinutes: minutes, from: Date())
        completion?.cancel()
        self.end = end
        completion = Task { [weak self] in
            // The continuous clock keeps counting through sleep, so a lid-closed timer ends on wake.
            try? await Task.sleep(for: .seconds(max(end.timeIntervalSinceNow, 0)))
            guard !Task.isCancelled, let self else { return }
            self.completion = nil
            self.end = nil
            self.onFinished?()
        }
    }

    func cancel() {
        completion?.cancel()
        completion = nil
        if end != nil { end = nil }
    }
}

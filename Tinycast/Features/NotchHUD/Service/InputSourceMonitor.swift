import Carbon.HIToolbox
import Foundation

/// Reports the keyboard input source each time the user lands on a different one.
@MainActor
final class InputSourceMonitor {
    var onChange: ((String) -> Void)?

    private var token: NotificationToken?
    private var lastSourceID: String?

    func start() {
        guard token == nil else { return }
        lastSourceID = InputSourceSwitcher.currentOption()?.id
        let center = DistributedNotificationCenter.default()
        let name = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
        token = NotificationToken(
            center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.sourceDidChange()
                }
            },
            center: center)
    }

    func stop() {
        token = nil
        lastSourceID = nil
    }

    private func sourceDidChange() {
        // TIS posts on every app switch too; only a different source is worth announcing.
        guard let current = InputSourceSwitcher.currentOption(), current.id != lastSourceID else { return }
        lastSourceID = current.id
        onChange?(current.title)
    }
}

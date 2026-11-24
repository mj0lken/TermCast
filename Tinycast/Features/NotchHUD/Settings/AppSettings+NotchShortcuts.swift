import Foundation

extension AppSettings {
    /// A shortcut whose feature is off is drawn nowhere, and gives its slot to the next one.
    func isAvailable(_ shortcut: NotchShortcut) -> Bool {
        switch shortcut {
        case .clipboard: clipboardEnabled
        case .notebook: notesEnabled
        case .windowManagement: windowManagementEnabled
        case .snippets: snippetsEnabled
        case .camera, .timer, .emoji, .settings: true
        }
    }
}

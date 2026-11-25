import Foundation

extension AppSettings {
    /// A shortcut whose feature is off is drawn nowhere, and its place stays empty.
    func isAvailable(_ shortcut: NotchShortcut) -> Bool {
        switch shortcut {
        case .clipboard: clipboardEnabled
        case .notebook: notesEnabled
        case .windowManagement: windowManagementEnabled
        case .snippets: snippetsEnabled
        case .camera, .timer, .emoji, .settings: true
        case .gap: false
        }
    }
}

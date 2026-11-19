import Foundation

/// The modifier held while the picker is open; the key pressed with it is fixed per scope.
enum WindowPickerChord: String, CaseIterable, Identifiable, Sendable {
    case off, command, option, control

    var id: String { rawValue }

    var modifier: WindowPickerKeyEngine.Modifiers? {
        switch self {
        case .off: nil
        case .command: .command
        case .option: .option
        case .control: .control
        }
    }

    var symbol: String? {
        switch self {
        case .off: nil
        case .command: "⌘"
        case .option: "⌥"
        case .control: "⌃"
        }
    }
}

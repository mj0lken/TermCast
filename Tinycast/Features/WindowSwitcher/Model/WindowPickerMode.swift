import Foundation

/// How the picker arranges its windows. Left ⇧ walks the three in this order.
enum WindowPickerMode: String, CaseIterable, Identifiable, Sendable {
    case windows, stacks, groups

    var id: String { rawValue }

    var next: WindowPickerMode {
        switch self {
        case .windows: .stacks
        case .stacks: .groups
        case .groups: .windows
        }
    }

    var title: String {
        switch self {
        case .windows: String(localized: "Windows")
        case .stacks: String(localized: "Stacks")
        case .groups: String(localized: "Groups")
        }
    }
}

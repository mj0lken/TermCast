import Foundation

enum HyperScrollZone: String, CaseIterable, Identifiable, Sendable {
    case screenBrightness
    case keyboardBrightness
    case volume

    var id: String { rawValue }

    static func zone(atNormalizedX x: Double) -> Self {
        if x < 1.0 / 3.0 { return .screenBrightness }
        if x < 2.0 / 3.0 { return .keyboardBrightness }
        return .volume
    }

    var title: String {
        switch self {
        case .screenBrightness: String(localized: "Screen")
        case .keyboardBrightness: String(localized: "Keyboard")
        case .volume: String(localized: "Volume")
        }
    }

    var subtitle: String {
        switch self {
        case .screenBrightness: String(localized: "Brightness")
        case .keyboardBrightness: String(localized: "Backlight")
        case .volume: String(localized: "Sound")
        }
    }

    var zoneSummary: String {
        switch self {
        case .screenBrightness:
            String(localized: "Left third — scroll vertically to adjust screen brightness.")
        case .keyboardBrightness:
            String(localized: "Middle third — scroll vertically to adjust keyboard backlight.")
        case .volume:
            String(localized: "Right third — scroll vertically (or spin a mouse wheel) to adjust volume.")
        }
    }

    var diagramSymbol: String {
        switch self {
        case .screenBrightness: "sun.max.fill"
        case .keyboardBrightness: "light.max"
        case .volume: "speaker.wave.2.fill"
        }
    }
}

import Foundation

struct TerminalRGB: Equatable, Hashable, Sendable {
    let r: UInt8
    let g: UInt8
    let b: UInt8

    init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(hex: UInt32) {
        self.r = UInt8((hex >> 16) & 0xFF)
        self.g = UInt8((hex >> 8) & 0xFF)
        self.b = UInt8(hex & 0xFF)
    }
}

struct TerminalPalette16: Equatable, Sendable {
    let foreground: TerminalRGB
    let ansi: [TerminalRGB]
}

struct TerminalChromeColors: Equatable, Sendable {
    let textPrimary: TerminalRGB
    let textSecondary: TerminalRGB
    let textTertiary: TerminalRGB
    let selectionFill: TerminalRGB
    let selectionOpacity: Double
    let hoverOpacity: Double
    let borderOpacity: Double
    let separatorOpacity: Double
}

enum TerminalColorTheme: String, CaseIterable, Codable, Sendable {
    case standard = "default"
    case paper
    case slate
    case midnight

    static func resolve(stored: String?) -> TerminalColorTheme {
        guard let stored else { return .standard }
        if let exact = TerminalColorTheme(rawValue: stored) {
            return exact
        }
        switch stored {
        case "daylight":
            return .paper
        case "tokyoNight", "obsidian", "ghostty":
            return .midnight
        default:
            return .standard
        }
    }

    var displayName: String {
        switch self {
        case .standard: String(localized: "Default")
        case .paper: String(localized: "Paper")
        case .slate: String(localized: "Slate")
        case .midnight: String(localized: "Midnight")
        }
    }

    var overridesIsDark: Bool? {
        switch self {
        case .standard:
            nil
        case .paper:
            false
        case .slate, .midnight:
            true
        }
    }

    func effectiveIsDark(systemIsDark: Bool) -> Bool {
        overridesIsDark ?? systemIsDark
    }

    var surfaceBackground: TerminalRGB? {
        switch self {
        case .standard:
            nil
        case .paper:
            TerminalRGB(hex: 0xF6F2E9)
        case .slate:
            TerminalRGB(hex: 0x2E3440)
        case .midnight:
            TerminalRGB(hex: 0x212534)
        }
    }

    var tabBarBackground: TerminalRGB? {
        switch self {
        case .standard:
            nil
        case .paper:
            TerminalRGB(hex: 0xEDE7DA)
        case .slate:
            TerminalRGB(hex: 0x272C37)
        case .midnight:
            TerminalRGB(hex: 0x1B1E2B)
        }
    }

    var chromeColors: TerminalChromeColors? {
        switch self {
        case .standard:
            nil
        case .paper:
            TerminalChromeColors(
                textPrimary: TerminalRGB(hex: 0x2D261E),
                textSecondary: TerminalRGB(hex: 0x6E6253),
                textTertiary: TerminalRGB(hex: 0x8C7E6D),
                selectionFill: TerminalRGB(hex: 0x2D261E),
                selectionOpacity: 0.09,
                hoverOpacity: 0.05,
                borderOpacity: 0.14,
                separatorOpacity: 0.10)
        case .slate:
            TerminalChromeColors(
                textPrimary: TerminalRGB(hex: 0xECEFF4),
                textSecondary: TerminalRGB(hex: 0xB8C2D1),
                textTertiary: TerminalRGB(hex: 0x8692A6),
                selectionFill: TerminalRGB(hex: 0xECEFF4),
                selectionOpacity: 0.12,
                hoverOpacity: 0.07,
                borderOpacity: 0.16,
                separatorOpacity: 0.10)
        case .midnight:
            TerminalChromeColors(
                textPrimary: TerminalRGB(hex: 0xE6ECFF),
                textSecondary: TerminalRGB(hex: 0xA9B4D0),
                textTertiary: TerminalRGB(hex: 0x7883A0),
                selectionFill: TerminalRGB(hex: 0xE6ECFF),
                selectionOpacity: 0.12,
                hoverOpacity: 0.07,
                borderOpacity: 0.16,
                separatorOpacity: 0.10)
        }
    }

    func palette(isDark: Bool) -> TerminalPalette16 {
        switch self {
        case .standard:
            if isDark {
                return TerminalPalette16(
                    foreground: TerminalRGB(hex: 0xECEFF4),
                    ansi: [
                        TerminalRGB(hex: 0x6E7681), TerminalRGB(hex: 0xFF7B72),
                        TerminalRGB(hex: 0x56D364), TerminalRGB(hex: 0xE3B341),
                        TerminalRGB(hex: 0x79C0FF), TerminalRGB(hex: 0xD2A8FF),
                        TerminalRGB(hex: 0x56D4DD), TerminalRGB(hex: 0xD0D7DE),
                        TerminalRGB(hex: 0x8B949E), TerminalRGB(hex: 0xFFA198),
                        TerminalRGB(hex: 0x7EE787), TerminalRGB(hex: 0xF2CC60),
                        TerminalRGB(hex: 0xA5D6FF), TerminalRGB(hex: 0xE2C5FF),
                        TerminalRGB(hex: 0x76E3EA), TerminalRGB(hex: 0xFFFFFF)
                    ])
            }
            return TerminalPalette16(
                foreground: TerminalRGB(hex: 0x1F2328),
                ansi: [
                    TerminalRGB(hex: 0x57606A), TerminalRGB(hex: 0xCF222E),
                    TerminalRGB(hex: 0x1A7F37), TerminalRGB(hex: 0x9A6700),
                    TerminalRGB(hex: 0x0969DA), TerminalRGB(hex: 0x8250DF),
                    TerminalRGB(hex: 0x0E7490), TerminalRGB(hex: 0x424A53),
                    TerminalRGB(hex: 0x6E7781), TerminalRGB(hex: 0xA40E26),
                    TerminalRGB(hex: 0x15803D), TerminalRGB(hex: 0x854D0E),
                    TerminalRGB(hex: 0x0550AE), TerminalRGB(hex: 0x6639BA),
                    TerminalRGB(hex: 0x0E7490), TerminalRGB(hex: 0x1F2328)
                ])
        case .paper:
            return TerminalPalette16(
                foreground: TerminalRGB(hex: 0x2D261E),
                ansi: [
                    TerminalRGB(hex: 0x6E6253), TerminalRGB(hex: 0xC23B22),
                    TerminalRGB(hex: 0x3A6B1E), TerminalRGB(hex: 0xA66300),
                    TerminalRGB(hex: 0x1F569E), TerminalRGB(hex: 0x84308E),
                    TerminalRGB(hex: 0x136F63), TerminalRGB(hex: 0x4A4035),
                    TerminalRGB(hex: 0x7D7060), TerminalRGB(hex: 0xA62613),
                    TerminalRGB(hex: 0x2D5A14), TerminalRGB(hex: 0x8A4F00),
                    TerminalRGB(hex: 0x17437D), TerminalRGB(hex: 0x6E2278),
                    TerminalRGB(hex: 0x0D5C52), TerminalRGB(hex: 0x1F1A14)
                ])
        case .slate:
            return TerminalPalette16(
                foreground: TerminalRGB(hex: 0xE5E9F0),
                ansi: [
                    TerminalRGB(hex: 0x616E88), TerminalRGB(hex: 0xD57780),
                    TerminalRGB(hex: 0xA3BE8C), TerminalRGB(hex: 0xEBCB8B),
                    TerminalRGB(hex: 0x81A1C1), TerminalRGB(hex: 0xB48EAD),
                    TerminalRGB(hex: 0x88C0D0), TerminalRGB(hex: 0xD8DEE9),
                    TerminalRGB(hex: 0x7B88A1), TerminalRGB(hex: 0xEA868F),
                    TerminalRGB(hex: 0xB5D19C), TerminalRGB(hex: 0xF2D69B),
                    TerminalRGB(hex: 0x96B5D3), TerminalRGB(hex: 0xC9A3C2),
                    TerminalRGB(hex: 0x9BD0DF), TerminalRGB(hex: 0xECEFF4)
                ])
        case .midnight:
            return TerminalPalette16(
                foreground: TerminalRGB(hex: 0xD8E0F8),
                ansi: [
                    TerminalRGB(hex: 0x5A638C), TerminalRGB(hex: 0xF7768E),
                    TerminalRGB(hex: 0x73DACA), TerminalRGB(hex: 0xE0AF68),
                    TerminalRGB(hex: 0x7AA2F7), TerminalRGB(hex: 0xBB9AF7),
                    TerminalRGB(hex: 0x7DCFFF), TerminalRGB(hex: 0xC0CAF5),
                    TerminalRGB(hex: 0x737CAA), TerminalRGB(hex: 0xFF8FA3),
                    TerminalRGB(hex: 0x8AE8D8), TerminalRGB(hex: 0xECC484),
                    TerminalRGB(hex: 0x94B6FF), TerminalRGB(hex: 0xCEB4FF),
                    TerminalRGB(hex: 0x99DCFF), TerminalRGB(hex: 0xF0F4FF)
                ])
        }
    }

    func color256(_ index: Int, isDark: Bool) -> TerminalRGB {
        let clamped = max(0, min(255, index))
        if clamped < 16 {
            return palette(isDark: isDark).ansi[clamped]
        }
        if clamped < 232 {
            let offset = clamped - 16
            let rStep = offset / 36
            let gStep = (offset / 6) % 6
            let bStep = offset % 6
            let ramp: [UInt8] = [0, 95, 135, 175, 215, 255]
            return TerminalRGB(ramp[rStep], ramp[gStep], ramp[bStep])
        }
        let gray = UInt8(8 + (clamped - 232) * 10)
        return TerminalRGB(gray, gray, gray)
    }
}

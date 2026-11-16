import SwiftUI

struct NotchHUDStyle: Equatable {
    var showsPercentage = true
    var tintsAccent = false

    var fill: Color { tintsAccent ? Color.accentColor : Theme.Colors.textPrimary }
}

extension EnvironmentValues {
    @Entry var notchHUDStyle = NotchHUDStyle()
}

struct NotchHUDView: View {
    let state: NotchHUDState

    var body: some View {
        Group {
            switch state.layout.mode {
            case .notched(
                let notchOriginX,
                let notchWidth,
                let notchHeight,
                let leftWingWidth,
                let rightWingWidth,
                let earRadius,
                let innerCornerRadius
            ):
                NotchedInlineWingsContent(
                    metric: state.metric,
                    isExpanded: state.isExpanded,
                    notchOriginX: notchOriginX,
                    notchWidth: notchWidth,
                    notchHeight: notchHeight,
                    leftWingWidth: leftWingWidth,
                    rightWingWidth: rightWingWidth,
                    trackWidth: state.layout.trackWidth,
                    earRadius: earRadius,
                    innerCornerRadius: innerCornerRadius)

            case .floatingPill(let baseWidth, let cornerRadius):
                FloatingIslandPillContent(
                    metric: state.metric,
                    isExpanded: state.isExpanded,
                    pillWidth: baseWidth,
                    pillHeight: state.layout.panelFrame.height,
                    cornerRadius: cornerRadius,
                    trackWidth: state.layout.trackWidth)
            }
        }
        .frame(
            width: state.layout.panelFrame.width,
            height: state.layout.panelFrame.height,
            alignment: .topLeading)
        .environment(\.colorScheme, .dark)
        .environment(\.notchHUDStyle, state.style)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        switch state.metric {
        case .volume(_, let muted):
            if muted { return String(localized: "Muted") }
            return String(localized: "Volume \(state.metric.percentageText())")
        case .screenBrightness:
            return String(localized: "Brightness \(state.metric.percentageText())")
        case .keyboardBacklight(_, let suppressed):
            if suppressed { return String(localized: "Keyboard brightness unavailable") }
            return String(localized: "Keyboard brightness \(state.metric.percentageText())")
        case .audioDeviceConnected(let name, _, _, _):
            return String(localized: "\(name) connected")
        case .battery(let percentage, let isPluggedIn):
            if isPluggedIn {
                return String(localized: "Charging \(percentage)%")
            }
            return String(localized: "Battery \(percentage)%")
        }
    }
}

private struct NotchedInlineWingsContent: View {
    let metric: NotchHUDMetric
    let isExpanded: Bool
    let notchOriginX: CGFloat
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let leftWingWidth: CGFloat
    let rightWingWidth: CGFloat
    let trackWidth: CGFloat
    let earRadius: CGFloat
    let innerCornerRadius: CGFloat

    private var activeLeft: CGFloat { isExpanded ? leftWingWidth : 0 }
    private var activeRight: CGFloat { isExpanded ? rightWingWidth : 0 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            let wingShape = NotchWingShape(
                notchOriginX: notchOriginX,
                notchWidth: notchWidth,
                leftExtension: activeLeft,
                rightExtension: activeRight,
                earRadius: earRadius,
                innerCornerRadius: innerCornerRadius)

            wingShape
                .fill(Theme.Colors.notchHardwareBlack)

            wingShape
                .stroke(
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.14)],
                        startPoint: .top,
                        endPoint: .bottom),
                    lineWidth: Theme.Size.hairline)

            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    NotchHUDGlyph(symbol: metric.symbol)
                    Spacer(minLength: 0)
                }
                .frame(width: leftWingWidth, height: notchHeight)
                .opacity(isExpanded ? 1 : 0)
                .offset(x: isExpanded ? 0 : 8)

                Color.clear
                    .frame(width: notchWidth, height: notchHeight)

                HStack(spacing: Theme.Spacing.sm) {
                    NotchHUDRightReadout(metric: metric, trackWidth: trackWidth)
                }
                .padding(.leading, Theme.Spacing.sm)
                .padding(.trailing, Theme.Spacing.md)
                .frame(width: rightWingWidth, height: notchHeight, alignment: .leading)
                .opacity(isExpanded ? 1 : 0)
                .offset(x: isExpanded ? 0 : -8)
            }
            .offset(x: notchOriginX - leftWingWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(Theme.NotchMotion.wing, value: isExpanded)
        .animation(Theme.NotchMotion.wing, value: leftWingWidth)
        .animation(Theme.NotchMotion.wing, value: rightWingWidth)
    }
}

private struct FloatingIslandPillContent: View {
    let metric: NotchHUDMetric
    let isExpanded: Bool
    let pillWidth: CGFloat
    let pillHeight: CGFloat
    let cornerRadius: CGFloat
    let trackWidth: CGFloat

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            NotchHUDGlyph(symbol: metric.symbol)
            Spacer(minLength: Theme.Spacing.xs)
            NotchHUDRightReadout(metric: metric, trackWidth: trackWidth)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(width: pillWidth, height: pillHeight)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.Colors.notchHardwareBlack)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.Colors.cardStroke, lineWidth: Theme.Size.hairline)
        )
        .scaleEffect(
            x: isExpanded ? 1 : 0.84,
            y: isExpanded ? 1 : 0.72,
            anchor: .top)
        .opacity(isExpanded ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Theme.NotchMotion.wing, value: isExpanded)
        .animation(Theme.NotchMotion.wing, value: pillWidth)
    }
}

private struct NotchHUDGlyph: View {
    let symbol: String

    var body: some View {
        SymbolImage(name: symbol, size: Theme.Size.notchHUDIcon, monochrome: true)
            .foregroundStyle(Theme.Colors.textPrimary)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: Theme.Size.menuIcon, height: Theme.Size.menuIcon)
    }
}

private struct NotchHUDRightReadout: View {
    @Environment(\.notchHUDStyle) private var style
    let metric: NotchHUDMetric
    let trackWidth: CGFloat

    var body: some View {
        switch metric {
        case .audioDeviceConnected(let name, _, _, _):
            Text(verbatim: name)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .battery(let percentage, let isPluggedIn):
            Text(
                isPluggedIn
                    ? String(localized: "Charging · \(percentage)%")
                    : String(localized: "On Battery · \(percentage)%")
            )
            .font(.caption.monospacedDigit().weight(.medium))
            .foregroundStyle(isPluggedIn ? Theme.Colors.success : Theme.Colors.textPrimary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

        case .volume, .screenBrightness, .keyboardBacklight:
            NotchHUDLevelBar(
                level: metric.effectiveLevel,
                trackWidth: style.showsPercentage
                    ? trackWidth : trackWidth + Theme.Size.notchHUDReadoutWidth)
            if style.showsPercentage {
                Text(verbatim: metric.percentageText())
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .frame(width: Theme.Size.notchHUDReadoutWidth, alignment: .trailing)
            }
        }
    }
}

private struct NotchHUDLevelBar: View {
    @Environment(\.notchHUDStyle) private var style
    let level: Double
    let trackWidth: CGFloat

    var body: some View {
        let clamped = CGFloat(NotchHUDMetric.clamp(level))
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Theme.Colors.controlSurface)
                .frame(width: trackWidth, height: Theme.Size.notchHUDTrackHeight)

            Capsule()
                .fill(style.fill)
                .frame(
                    width: max(trackWidth * clamped, clamped > 0 ? Theme.Size.notchHUDTrackHeight : 0),
                    height: Theme.Size.notchHUDTrackHeight)
        }
        .frame(width: trackWidth, height: Theme.Size.notchHUDTrackHeight)
        .animation(Theme.NotchMotion.bar, value: clamped)
        .animation(Theme.NotchMotion.wing, value: trackWidth)
    }
}

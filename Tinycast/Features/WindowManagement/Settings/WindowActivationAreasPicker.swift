import SwiftUI

/// Interactive screen-edge diagram for inspecting and toggling Magnet-style activation areas.
struct WindowActivationAreasPicker: View {
    @Environment(AppSettings.self) private var settings
    @State private var hoveredZone: WindowActivationZone?

    private static let diagramAspect: CGFloat = 16 / 10
    private static let diagramHeight: CGFloat = 176
    private static let virtualScreen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    var body: some View {
        let disabled = disabledZones
        let options = WindowDragSnap.Options(
            edgeWidth: settings.windowActivationEdgeWidth,
            areaScale: settings.windowActivationAreaScale,
            disabledZones: [])
        let allPills = WindowDragSnap.activationPills(
            in: [
                WindowPlacementEngine.Screen(
                    id: 1, frame: Self.virtualScreen, visibleFrame: Self.virtualScreen)
            ], options: options)
        let activeZone = hoveredZone
        let enabledCount = WindowActivationZone.allCases.count - disabled.count

        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            GeometryReader { proxy in
                let size = fittedSize(in: proxy.size)
                let origin = CGPoint(
                    x: (proxy.size.width - size.width) / 2,
                    y: (proxy.size.height - size.height) / 2)
                let scale = size.width / Self.virtualScreen.width

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(Theme.Colors.layoutPreviewGround)
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                .strokeBorder(Theme.Colors.border, lineWidth: Theme.Size.hairline)
                        }
                        .frame(width: size.width, height: size.height)
                        .offset(x: origin.x, y: origin.y)

                    if let activeZone, !disabled.contains(activeZone),
                        let preview = previewFrame(for: activeZone.command)
                    {
                        let shape = RoundedRectangle(
                            cornerRadius: Theme.Radius.thumbnail, style: .continuous)
                        shape
                            .fill(Theme.Colors.snapPreviewFill)
                            .overlay {
                                shape.strokeBorder(
                                    Theme.Colors.snapPreviewStroke,
                                    lineWidth: Theme.Size.contextRingStroke)
                            }
                            .frame(
                                width: max(2, preview.width * scale),
                                height: max(2, preview.height * scale)
                            )
                            .offset(
                                x: origin.x + preview.minX * scale,
                                y: origin.y + preview.minY * scale)
                            .allowsHitTesting(false)
                    }

                    ForEach(allPills) { pill in
                        zoneButton(
                            for: pill, isDisabled: disabled.contains(pill.zone),
                            isHighlighted: activeZone?.command == pill.zone.command,
                            origin: origin, scale: scale)
                    }
                }
            }
            .frame(height: Self.diagramHeight)

            HStack(spacing: Theme.Spacing.md) {
                if let activeZone {
                    WindowCommandIcon(id: activeZone.command)
                        .foregroundStyle(.secondary)
                    Text(verbatim: activeZone.title)
                        .font(.caption.weight(.medium))
                    if disabled.contains(activeZone) {
                        Text("Off")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("\(enabledCount) of \(WindowActivationZone.allCases.count) areas active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: Theme.Spacing.sm)

                if !disabled.isEmpty {
                    Button("Enable All") {
                        settings.windowDisabledActivationAreas = []
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private var disabledZones: Set<WindowActivationZone> {
        Set(settings.windowDisabledActivationAreas.compactMap(WindowActivationZone.init(rawValue:)))
    }

    private func toggle(_ zone: WindowActivationZone) {
        var set = disabledZones
        if set.contains(zone) {
            set.remove(zone)
        } else {
            set.insert(zone)
        }
        settings.windowDisabledActivationAreas =
            WindowActivationZone.allCases.filter(set.contains).map(\.rawValue)
    }

    private func fittedSize(in container: CGSize) -> CGSize {
        guard container.width > 0, container.height > 0 else { return .zero }
        let widthLimited = CGSize(
            width: container.width, height: container.width / Self.diagramAspect)
        if widthLimited.height <= container.height { return widthLimited }
        return CGSize(width: container.height * Self.diagramAspect, height: container.height)
    }

    private func previewFrame(for command: WindowCommand.ID) -> CGRect? {
        let screen = WindowPlacementEngine.Screen(
            id: 1, frame: Self.virtualScreen, visibleFrame: Self.virtualScreen)
        return WindowPlacementEngine.placement(
            for: WindowPlacementEngine.Input(
                command: command, windowFrame: CGRect(x: 600, y: 400, width: 200, height: 150),
                screens: [screen], gap: CGFloat(settings.windowGap),
                fitTightlyToEdges: settings.windowFitTightlyToEdges)
        )?.frame
    }

    @ViewBuilder
    private func zoneButton(
        for pill: WindowDragSnap.Pill, isDisabled: Bool, isHighlighted: Bool,
        origin: CGPoint, scale: CGFloat
    ) -> some View {
        let width = max(8, pill.frame.width * scale)
        let height = max(8, pill.frame.height * scale)
        let capsule = Capsule(style: .continuous)

        Button {
            toggle(pill.zone)
        } label: {
            capsule
                .fill(pillFill(isDisabled: isDisabled, isHighlighted: isHighlighted))
                .overlay {
                    capsule.strokeBorder(
                        pillStroke(isDisabled: isDisabled, isHighlighted: isHighlighted),
                        lineWidth: 1)
                }
                .frame(width: width, height: height)
                .contentShape(Rectangle().inset(by: -3))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredZone = pill.zone
            } else if hoveredZone == pill.zone {
                hoveredZone = nil
            }
        }
        .offset(
            x: origin.x + pill.frame.minX * scale - max(0, (8 - pill.frame.width * scale) / 2),
            y: origin.y + pill.frame.minY * scale - max(0, (8 - pill.frame.height * scale) / 2)
        )
        .accessibilityLabel(pill.zone.title)
        .accessibilityValue(isDisabled ? Text("Off") : Text("On"))
    }

    private func pillFill(isDisabled: Bool, isHighlighted: Bool) -> Color {
        if isDisabled {
            return Theme.Colors.layoutPreviewWindow.opacity(0.28)
        }
        return isHighlighted ? Color.accentColor : Color.accentColor.opacity(0.72)
    }

    private func pillStroke(isDisabled: Bool, isHighlighted: Bool) -> Color {
        if isDisabled {
            return Theme.Colors.border
        }
        return isHighlighted ? Theme.Colors.snapPillArmedStroke : Color.accentColor
    }
}

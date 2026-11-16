import SwiftUI

/// Visual map of the three horizontal trackpad scroll zones and mouse-wheel fallback.
struct HyperKeyTrackpadDiagramView: View {
    let keyTitle: String?
    let isActive: Bool

    @State private var hoveredZone: HyperScrollZone?

    private static let trackpadHeight: CGFloat = 116
    private static let trackpadMaxWidth: CGFloat = 380
    private static let zoneIconSize: CGFloat = 17
    private static let arrowIconSize: CGFloat = 10
    private static let dividerDash: [CGFloat] = [4, 4]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            gestureHeader

            HStack {
                Spacer(minLength: 0)
                trackpadSurface
                    .frame(maxWidth: Self.trackpadMaxWidth)
                    .frame(height: Self.trackpadHeight)
                Spacer(minLength: 0)
            }

            captionRow
        }
        .padding(.vertical, Theme.Spacing.xs)
        .settingsEnabled(isActive)
    }

    private var gestureHeader: some View {
        HStack(spacing: Theme.Spacing.sm) {
            KeyCapChip(text: "✦", style: .outline)
            if let keyTitle {
                Text(keyTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
            } else {
                Text("Hyper Key")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
            }
            Text(verbatim: "+")
                .font(.caption)
                .foregroundStyle(.secondary)
            SymbolImage(name: "arrow.up.and.down", size: Self.arrowIconSize)
                .foregroundStyle(.secondary)
            Text("Two-finger vertical scroll")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var trackpadSurface: some View {
        let outerShape = RoundedRectangle(cornerRadius: Theme.Radius.codeBlock, style: .continuous)
        return ZStack {
            outerShape
                .fill(Theme.Colors.layoutPreviewGround)
                .overlay {
                    outerShape.strokeBorder(Theme.Colors.border, lineWidth: Theme.Size.hairline)
                }

            HStack(spacing: 0) {
                ForEach(Array(HyperScrollZone.allCases.enumerated()), id: \.element.id) { index, zone in
                    zoneColumn(zone)
                    if index < HyperScrollZone.allCases.count - 1 {
                        ZoneDivider(dash: Self.dividerDash)
                    }
                }
            }
            .padding(Theme.Spacing.xs)
        }
    }

    private func zoneColumn(_ zone: HyperScrollZone) -> some View {
        let isHovered = hoveredZone == zone
        let highlight = RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)

        return VStack(spacing: Theme.Spacing.xs) {
            SymbolImage(name: "chevron.compact.up", size: Self.arrowIconSize)
                .foregroundStyle(isHovered ? Color.accentColor : Theme.Colors.textTertiary)

            SymbolImage(name: zone.diagramSymbol, size: Self.zoneIconSize)
                .foregroundStyle(isHovered ? Color.accentColor : Color.primary)
                .frame(height: Theme.Size.rowIcon)

            Text(zone.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(zone.subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            SymbolImage(name: "chevron.compact.down", size: Self.arrowIconSize)
                .foregroundStyle(isHovered ? Color.accentColor : Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, Theme.Spacing.xs)
        .padding(.horizontal, Theme.Spacing.sm)
        .background {
            if isHovered {
                highlight
                    .fill(Theme.Colors.snapPreviewFill)
                    .overlay {
                        highlight.strokeBorder(
                            Theme.Colors.snapPreviewStroke,
                            lineWidth: Theme.Size.hairline)
                    }
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredZone = zone
            } else if hoveredZone == zone {
                hoveredZone = nil
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(zone.zoneSummary)
    }

    private var captionRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let hoveredZone {
                SymbolImage(name: hoveredZone.diagramSymbol, size: 12)
                    .foregroundStyle(.secondary)
                Text(hoveredZone.zoneSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                SymbolImage(name: "computermouse", size: 12)
                    .foregroundStyle(.secondary)
                Text("Zone locks on touch-down · External mouse wheel adjusts volume")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: Theme.Size.checkbox, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private struct ZoneDivider: View {
        let dash: [CGFloat]

        var body: some View {
            GeometryReader { geometry in
                Path { path in
                    path.move(to: CGPoint(x: 0.5, y: Theme.Spacing.sm))
                    path.addLine(to: CGPoint(x: 0.5, y: max(Theme.Spacing.sm, geometry.size.height - Theme.Spacing.sm)))
                }
                .stroke(
                    Theme.Colors.border,
                    style: StrokeStyle(lineWidth: Theme.Size.hairline, dash: dash))
            }
            .frame(width: Theme.Size.hairline)
            .accessibilityHidden(true)
        }
    }
}

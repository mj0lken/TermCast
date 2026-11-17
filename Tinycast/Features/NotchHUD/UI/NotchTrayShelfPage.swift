import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Shelf page: an AirDrop target beside the staged files, links and text.
struct NotchShelfBodyView: View {
    let shelfStore: NotchShelfStore

    @State private var isTargetingAirDrop = false
    @State private var isTargetingShelf = false

    private static let dropTypes: [UTType] = [.fileURL, .url, .plainText]

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button {
                shelfStore.airDropAllStaged()
            } label: {
                VStack(spacing: Theme.Spacing.sm) {
                    ZStack {
                        Circle()
                            .fill(
                                isTargetingAirDrop
                                    ? Color.accentColor.opacity(0.28)
                                    : Theme.Colors.controlSurface)
                            .frame(width: 54, height: 54)
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                    Text("AirDrop")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .frame(width: 124)
                .frame(maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            isTargetingAirDrop ? Color.accentColor : Theme.Colors.border,
                            style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onDrop(of: Self.dropTypes, isTargeted: $isTargetingAirDrop) { providers in
                shelfStore.airDrop(providers: providers)
                return true
            }

            ZStack(alignment: .topTrailing) {
                Group {
                    if shelfStore.items.isEmpty {
                        VStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "tray.and.arrow.down")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(Theme.Colors.textTertiary)
                            Text("Drop files, links or text here")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView(.horizontal) {
                            HStack(spacing: Theme.Spacing.md) {
                                ForEach(shelfStore.items) { item in
                                    NotchShelfCardView(
                                        item: item,
                                        shelfStore: shelfStore)
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                            .frame(maxHeight: .infinity)
                        }
                        .scrollIndicators(.never)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            isTargetingShelf ? Color.accentColor : Theme.Colors.border,
                            style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                )
                .onDrop(of: Self.dropTypes, isTargeted: $isTargetingShelf) { providers in
                    shelfStore.ingestDrop(providers: providers)
                    return true
                }

                if !shelfStore.items.isEmpty {
                    Button {
                        shelfStore.clear()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .padding(6)
                            .background(Circle().fill(Theme.Colors.controlSurface))
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .accessibilityLabel(String(localized: "Clear Shelf"))
                }
            }
        }
    }
}

private struct NotchShelfCardView: View {
    let item: NotchShelfItem
    let shelfStore: NotchShelfStore

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 6) {
                shelfIcon
                    .frame(width: 44, height: 48)

                Text(verbatim: item.displayTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: 98)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isHovering ? Theme.Colors.controlSurface : .clear)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                shelfStore.open(item)
            }
            .onDrag {
                shelfStore.itemProvider(for: item)
            }

            if isHovering {
                Button {
                    shelfStore.remove(id: item.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Colors.textPrimary, Theme.Colors.notchHardwareBlack)
                }
                .buttonStyle(.plain)
                .offset(x: 2, y: -2)
            }
        }
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var shelfIcon: some View {
        switch item.kind {
        case .file(let url):
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .scaledToFit()
        case .link:
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 36, height: 44)
                Image(systemName: "link")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black)
            }
        case .text:
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.Colors.controlHover)
                    .frame(width: 36, height: 44)
                Image(systemName: "text.alignleft")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
        }
    }
}

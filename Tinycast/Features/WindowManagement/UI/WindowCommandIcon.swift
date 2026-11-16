import AppKit
import SwiftUI

/// Template schematic glyph for fractional window tiles, backed by `WindowTileGlyph`.
struct WindowCommandIcon: View {
    private enum Source {
        case command(WindowCommand.ID, fallbackSymbol: String)
        case customSize(CustomWindowSize)
    }

    private let source: Source

    init(command: WindowCommand) {
        source = .command(command.id, fallbackSymbol: command.sfSymbol)
    }

    init(id: WindowCommand.ID) {
        let symbol = WindowCommandCatalog.command(id: id)?.sfSymbol ?? "macwindow"
        source = .command(id, fallbackSymbol: symbol)
    }

    init(size: CustomWindowSize) {
        source = .customSize(size)
    }

    var body: some View {
        switch source {
        case .command(let id, let fallbackSymbol):
            if let image = Self.tileImage(for: id) {
                Image(nsImage: image)
            } else {
                Image(systemName: fallbackSymbol)
            }
        case .customSize(let size):
            if let cell = size.gridCell {
                Image(nsImage: Self.tileImage(for: cell))
            } else {
                Image(systemName: CustomWindowSize.sfSymbol)
            }
        }
    }

    @MainActor private static var commandCache: [WindowCommand.ID: NSImage] = [:]

    @MainActor static func tileImage(for id: WindowCommand.ID) -> NSImage? {
        if let cached = commandCache[id] { return cached }
        guard let rect = WindowPlacementEngine.tilePreviewRect(for: id) else { return nil }
        let image = WindowTileGlyph.templateImage(for: WindowTileIcon(unitRect: rect))
        commandCache[id] = image
        return image
    }

    @MainActor static func tileImage(for cell: CustomWindowSize.GridCell) -> NSImage {
        WindowTileGlyph.templateImage(for: WindowTileIcon(unitRect: cell.unitRect))
    }
}

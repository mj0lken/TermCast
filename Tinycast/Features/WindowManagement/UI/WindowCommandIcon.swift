import AppKit
import SwiftUI

/// Template schematic glyph for fractional window tiles, matching SF Symbols' 18×14 rectangle box.
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
        let image = makeTemplateImage(unitRect: rect)
        commandCache[id] = image
        return image
    }

    @MainActor static func tileImage(for cell: CustomWindowSize.GridCell) -> NSImage {
        let unit = CGRect(
            x: cell.x0, y: cell.y0, width: cell.x1 - cell.x0, height: cell.y1 - cell.y0)
        return makeTemplateImage(unitRect: unit)
    }

    private static func makeTemplateImage(unitRect: CGRect) -> NSImage {
        let clamped = unitRect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        let image = NSImage(size: NSSize(width: 18, height: 14), flipped: true) { _ in
            let outer = NSRect(x: 1.5, y: 1.5, width: 15, height: 11)
            let border = NSBezierPath(roundedRect: outer, xRadius: 2, yRadius: 2)
            border.lineWidth = 1.15
            NSColor.black.setStroke()
            border.stroke()

            guard !clamped.isNull else { return true }
            let inner = NSRect(x: 3.4, y: 3.4, width: 11.2, height: 7.2)
            let tileRect = NSRect(
                x: inner.minX + clamped.minX * inner.width,
                y: inner.minY + clamped.minY * inner.height,
                width: max(1.8, clamped.width * inner.width),
                height: max(1.8, clamped.height * inner.height))
            NSColor.black.setFill()
            NSBezierPath(roundedRect: tileRect, xRadius: 0.9, yRadius: 0.9).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}

import AppKit

extension NSWindow.Level {
    /// Above `.modalPanel`, where other apps' open panels and sheets-as-windows sit.
    static let palette = NSWindow.Level(rawValue: NSWindow.Level.modalPanel.rawValue + 1)
    /// One step under the palette, so guides clear other apps but not the dragged panel.
    static let paletteDropGuide = NSWindow.Level(rawValue: palette.rawValue - 1)
    /// Above the palette, so a confirmation is never buried under its trigger.
    static let dialog = NSWindow.Level(rawValue: palette.rawValue + 1)
    /// Above `.statusBar`, so the closed notch's live wings clear the menu bar across every Space.
    static let notchLiveActivity = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
    /// One step over the live wings, so a HUD or the open tray always covers them.
    static let notchHUD = NSWindow.Level(rawValue: notchLiveActivity.rawValue + 1)
}

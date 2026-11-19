import CoreGraphics
import ScreenCaptureKit

/// Captures window previews through ScreenCaptureKit, one at a time, already at tile size.
enum WindowThumbnailProvider {
    /// Delivers in the order asked, so the tiles nearest the selection fill in first.
    @concurrent
    static func capture(
        windowIDs: [CGWindowID], pixelSize: CGSize,
        deliver: @MainActor @Sendable (CGWindowID, CGImage) -> Void
    ) async {
        guard
            let content = try? await SCShareableContent.excludingDesktopWindows(
                true, onScreenWindowsOnly: false)
        else { return }
        let windows = Dictionary(
            content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        for id in windowIDs {
            guard !Task.isCancelled else { return }
            guard let window = windows[id], window.frame.width > 1, window.frame.height > 1
            else { continue }
            let configuration = SCStreamConfiguration()
            let fitted = fit(window.frame.size, into: pixelSize)
            configuration.width = Int(fitted.width)
            configuration.height = Int(fitted.height)
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true
            let filter = SCContentFilter(desktopIndependentWindow: window)
            guard
                let image = try? await SCScreenshotManager.captureImage(
                    contentFilter: filter, configuration: configuration)
            else { continue }
            await deliver(id, image)
        }
    }

    private static func fit(_ size: CGSize, into bounds: CGSize) -> CGSize {
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        return CGSize(
            width: max((size.width * scale).rounded(), 1),
            height: max((size.height * scale).rounded(), 1))
    }
}

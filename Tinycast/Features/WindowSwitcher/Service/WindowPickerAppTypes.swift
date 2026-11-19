import AppKit

/// What kind of app a window belongs to, as the system names it: "Developer Tools", "Music".
@MainActor
final class WindowPickerAppTypes {
    /// An app's category never changes while it runs, and Spotlight is not free to ask.
    private var names: [URL: String] = [:]
    /// Spotlight publishes the category's display name under this key but exports no constant.
    private static let attribute = "kMDItemAppStoreCategory" as CFString

    /// Empty for an app that declares no category; the picker files those under "Other".
    func name(for app: NSRunningApplication) -> String {
        guard let url = app.bundleURL else { return "" }
        if let known = names[url] { return known }
        let item = MDItemCreateWithURL(nil, url as CFURL)
        let name = item.flatMap { MDItemCopyAttribute($0, Self.attribute) as? String } ?? ""
        names[url] = name
        return name
    }
}

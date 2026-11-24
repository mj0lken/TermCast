import SwiftUI

/// The open notch's header buttons: which ones, in what order, and as many as the header holds.
struct NotchShortcutsSection: View {
    @Environment(AppSettings.self) private var settings

    private var limit: Int { NotchShortcut.limit(showsBattery: settings.notchShowsBattery) }

    var body: some View {
        Section {
            NotchShortcutBoard()
        } header: {
            SettingsSectionHeader(.notchShortcuts)
        } footer: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(
                    """
                    The header holds \(limit) shortcuts beside the notch. The battery indicator takes one \
                    slot while it shows.
                    """)
                Text("Two more fit against each side of the notch. Those on the right share the row’s room.")
                Text("A shortcut appears here only while its feature is on.")
            }
        }
    }
}

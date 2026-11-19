import SwiftUI

/// The Hyper Key and the trackpad sliders it drives: one pane, since the second needs the first.
struct HyperKeySettingsView: View {
    var body: some View {
        Form {
            HyperKeySettingsSection()
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.hyperKey)
    }
}

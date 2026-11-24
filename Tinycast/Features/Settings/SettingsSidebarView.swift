import SwiftUI

struct SettingsSidebarView: View {
    @Environment(SettingsNavigationState.self) private var navigation
    @State private var query = ""
    @State private var highlighted: SettingsSearchEntry.ID?
    @State private var searching = false

    private var results: [SettingsSearchEntry] { SettingsSearchCatalog.results(for: query) }

    var body: some View {
        VStack(spacing: 0) {
            if query.isEmpty {
                browse
            } else {
                found
            }
            SettingsSidebarActions()
        }
        .searchable(text: $query, isPresented: $searching, placement: .sidebar, prompt: "Search")
        .onExitCommand { query = "" }
        .background(focusShortcut)
    }

    private var browse: some View {
        List(selection: selection) {
            ForEach(SettingsSection.allCases) { section in
                Section(section.title) {
                    ForEach(section.tabs) { tab in
                        Label {
                            Text(tab.title)
                        } icon: {
                            SettingsTabIcon(tab: tab)
                        }
                        .tag(tab)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        // Pin the style before mounting; the implicit sidebar style paints icons a frame late.
        .labelStyle(.titleAndIcon)
    }

    @ViewBuilder private var found: some View {
        if results.isEmpty {
            // Greedy: a finite max height here becomes a constraint that shrinks the whole window.
            ContentUnavailableView.search(text: query)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // A second `List`, so result IDs and `SettingsTab` never share a selection namespace.
            List(selection: $highlighted) {
                Section("Results") {
                    ForEach(results) { entry in
                        SettingsSearchResultRow(entry: entry).tag(entry.id)
                    }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: highlighted) { _, id in
                guard let entry = results.first(where: { $0.id == id }) else { return }
                navigation.select(entry.tab, revealing: entry.target)
            }
        }
    }

    /// ⌘F with no menu item to hang it on; zero-sized so it only ever contributes the shortcut.
    private var focusShortcut: some View {
        Button("Search Settings") { searching = true }
            .keyboardShortcut("f", modifiers: .command)
            .buttonStyle(.plain)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }

    /// `List` hands back an optional selection; routing it through `select` records history.
    private var selection: Binding<SettingsTab?> {
        Binding(
            get: { navigation.tab },
            set: { if let tab = $0 { navigation.select(tab) } }
        )
    }
}

/// Actions, not panes: outside both lists, so neither can ever select one.
private struct SettingsSidebarActions: View {
    @Environment(MainAppLink.self) private var mainApp

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: Theme.Spacing.xxs) {
                Button {
                    mainApp.send(.checkForUpdates)
                } label: {
                    Label("Check for Updates…", systemImage: "arrow.down.circle")
                }
                Button {
                    mainApp.send(.quit)
                } label: {
                    Label("Quit \(Bundle.main.appDisplayName)", systemImage: "power")
                }
            }
            .buttonStyle(SettingsSidebarActionStyle())
            .padding(Theme.Spacing.lg)
        }
    }
}

private struct SettingsSidebarActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SettingsSidebarActionRow(configuration: configuration)
    }
}

private struct SettingsSidebarActionRow: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .labelStyle(SettingsSidebarActionLabelStyle())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
            .background(
                fill, in: RoundedRectangle(cornerRadius: Theme.Radius.barControl, style: .continuous)
            )
            .contentShape(.rect)
            .onHover { isHovered = $0 }
    }

    private var fill: Color {
        if configuration.isPressed { return Theme.Colors.selection }
        return isHovered ? Theme.Colors.rowHover : .clear
    }
}

private struct SettingsSidebarActionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            configuration.icon
                .foregroundStyle(.secondary)
                .frame(width: Theme.Size.settingsRowIcon + Theme.Spacing.xxs)
            configuration.title.lineLimit(1)
        }
    }
}

private struct SettingsSearchResultRow: View {
    let entry: SettingsSearchEntry

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(entry.title).lineLimit(1)
                Text(entry.breadcrumb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } icon: {
            SettingsTabIcon(tab: entry.tab)
        }
        // Centred, not first-baseline: the tile sits against a two-line title and breadcrumb.
        .labelStyle(CenteredLabelStyle())
    }
}

private struct CenteredLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center) {
            configuration.icon
            configuration.title
        }
    }
}

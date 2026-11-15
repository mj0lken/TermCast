import SwiftUI

@MainActor
enum AIModelMenu {
    /// Every model configured for chat; selecting one moves this chat and the default with it.
    static func models(coordinator: AIChatCoordinator, chat: AIChatState) -> PopoverMenuContent {
        let groups = coordinator.modelGroups
        let loading = coordinator.isModelCatalogLoading
        var items = groups.flatMap { group in
            group.options.enumerated().map { index, option in
                PopoverMenuItem(
                    title: option.title, icon: option.menuIcon,
                    sectionTitle: index == 0 ? group.title : nil
                ) {
                    coordinator.selectModel(option, in: chat)
                }
            }
        }
        if loading {
            items.insert(
                PopoverMenuItem(
                    title: String(localized: "Loading models…"), icon: .blank, isLoading: true
                ) {}, at: 0)
        }
        guard !items.isEmpty else {
            return PopoverMenuContent(items: [
                PopoverMenuItem(
                    title: String(localized: "Configure AI"), systemImage: "slider.horizontal.3"
                ) {
                    coordinator.showSettings()
                }
            ])
        }
        return PopoverMenuContent(items: items)
    }

    static func reasoning(coordinator: AIChatCoordinator, chat: AIChatState) -> PopoverMenuContent {
        let selected = coordinator.model(for: chat)?.effort
        return PopoverMenuContent(
            items: coordinator.reasoningEfforts(for: chat).map { effort in
                PopoverMenuItem(
                    title: effort.title, icon: .blank,
                    detail: effort.id == selected ? "✓" : nil
                ) {
                    coordinator.selectReasoningEffort(effort, in: chat)
                }
            })
    }

    /// Quick AI's `+` menu: files, screenshots, clipboard images, web search and MCP servers.
    static func addContext(
        coordinator: AIChatCoordinator, quickAI: QuickAICoordinator, chat: AIChatState
    ) -> PopoverMenuContent {
        let can = coordinator.capabilities(for: chat)
        var items: [PopoverMenuItem] = [
            PopoverMenuItem(
                title: String(localized: "Attach Files…"), systemImage: "paperclip",
                shortcut: "⇧⌘A"
            ) {
                quickAI.chooseFiles()
            }
        ]
        if can.images {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Capture Screenshot"),
                    systemImage: "camera.viewfinder", shortcut: "⇧⌘S"
                ) {
                    quickAI.captureScreenshot()
                })
            if coordinator.hasClipboardImage {
                items.append(
                    PopoverMenuItem(
                        title: String(localized: "Paste from Clipboard"),
                        systemImage: "photo.on.rectangle"
                    ) {
                        quickAI.pasteClipboardImage()
                    })
            }
        }
        var separated = false
        if can.webSearch {
            let enabled = coordinator.aiSettings.webSearchEnabled
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Web Search"), icon: .symbol("globe"),
                    startsSection: true, detail: enabled ? "✓" : nil
                ) {
                    coordinator.aiSettings.webSearchEnabled.toggle()
                })
            separated = true
        }
        let servers = coordinator.mcpServers
        if can.tools, !servers.isEmpty {
            let scope = chat.toolScope
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Use Tools"), icon: .symbol("wrench.and.screwdriver"),
                    startsSection: !separated, detail: scope.isEnabled ? "✓" : nil
                ) {
                    coordinator.setToolsEnabled(!scope.isEnabled, in: chat)
                })
            if scope.isEnabled {
                let allowed = servers.filter { scope.allows($0.slug) }
                for (index, server) in allowed.enumerated() {
                    let label = server.name.isEmpty ? server.slug : server.name
                    items.append(
                        PopoverMenuItem(
                            title: "@\(server.slug)", icon: .symbol("at"),
                            sectionTitle: index == 0 ? String(localized: "Mentions") : nil,
                            detail: label == server.slug ? nil : label
                        ) {
                            quickAI.mentionServer(server.slug)
                        })
                }
            }
        }
        return PopoverMenuContent(header: String(localized: "Add Context"), items: items)
    }

    /// One row per staged file, its ✕ beside the name: picking one takes that file back alone.
    static func attachments(coordinator: AIChatCoordinator, chat: AIChatState) -> PopoverMenuContent {
        var items = chat.pendingAttachments.map { attachment in
            PopoverMenuItem(
                title: attachment.name, icon: attachment.menuIcon, detail: "✕"
            ) {
                coordinator.removeAttachment(attachment.id, in: chat)
            }
        }
        if items.count > 1 {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Remove All"), systemImage: "xmark.circle",
                    startsSection: true
                ) {
                    coordinator.clearAttachments(in: chat)
                })
        }
        return PopoverMenuContent(header: String(localized: "Attached"), items: items)
    }

    static func modelHighlight(coordinator: AIChatCoordinator, chat: AIChatState) -> Int {
        let options = coordinator.modelOptions
        // With nothing to choose yet, the loading row is the only row the menu has.
        guard !options.isEmpty else { return 0 }
        let offset = coordinator.isModelCatalogLoading ? 1 : 0
        let selectedIndex =
            coordinator.model(for: chat).flatMap { selected in
                options.firstIndex(where: { $0.matches(selected) })
            } ?? 0
        return offset + selectedIndex
    }

    static func reasoningHighlight(coordinator: AIChatCoordinator, chat: AIChatState) -> Int {
        let selected = coordinator.model(for: chat)?.effort
        return coordinator.reasoningEfforts(for: chat).firstIndex { $0.id == selected } ?? 0
    }
}

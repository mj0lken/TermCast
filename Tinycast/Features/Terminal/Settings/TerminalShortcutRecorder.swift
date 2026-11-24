import AppKit
import Carbon.HIToolbox
import SwiftUI

struct TerminalShortcutRecorder: View {
    let action: TerminalShortcutAction
    @Binding var recordingAction: TerminalShortcutAction?

    @Environment(AppSettings.self) private var settings
    @Environment(HotKeyManager.self) private var hotKeys
    @State private var hovered = false
    @State private var conflictTitle: String?
    @State private var hitHolder = RecorderViewHolder()
    @State private var eventMonitor: Any?

    private var isRecording: Bool { recordingAction == action }
    private var chord: TerminalKeyChord? { settings.terminalShortcuts.chord(for: action) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
        content
            .padding(.horizontal, Theme.Spacing.sm + 1)
            .frame(width: Theme.Size.shortcutRecorder, height: 24)
            .background(shape.fill(Theme.Colors.cardFill))
            .background {
                if isRecording { TerminalRecorderHitRegion(holder: hitHolder) }
            }
            .overlay(
                shape.strokeBorder(
                    isRecording ? Color.accentColor : Theme.Colors.cardStroke,
                    lineWidth: 1)
            )
            .clipShape(shape)
            .contentShape(shape)
            .onTapGesture {
                if isRecording {
                    stopRecording()
                } else {
                    hotKeys.recordingAction = nil
                    conflictTitle = nil
                    recordingAction = action
                }
            }
            .onHover { hovered = $0 }
            .onChange(of: isRecording) { _, active in
                if active {
                    startMonitor()
                } else {
                    removeMonitor()
                    conflictTitle = nil
                }
            }
            .onChange(of: hotKeys.recordingAction) { _, globalRecording in
                if globalRecording != nil, isRecording {
                    stopRecording()
                }
            }
            .onDisappear {
                removeMonitor()
                if isRecording { recordingAction = nil }
            }
            .animation(.easeOut(duration: 0.12), value: hovered)
    }

    @ViewBuilder
    private var content: some View {
        if isRecording {
            if let conflictTitle {
                Text(conflictTitle)
                    .font(Theme.Typography.keyCap)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Waiting for a shortcut…")
                    .font(Theme.Typography.keyCap)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if let chord {
            boundLabel(chord)
        } else {
            Text("Record Shortcut")
                .font(Theme.Typography.keyCap)
                .foregroundStyle(hovered ? Theme.Colors.textSecondary : Theme.Colors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func boundLabel(_ chord: TerminalKeyChord) -> some View {
        let caps = TerminalKeyEventBridge.keycaps(for: chord)
        return HStack(spacing: Theme.Spacing.xs) {
            ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in
                KeyCapChip.Label(text: cap, prefix: nil)
                    .font(Theme.Typography.keyCap)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Spacing.xs)
                    .frame(
                        minWidth: Theme.Size.recorderKeyCap,
                        minHeight: Theme.Size.recorderKeyCap)
                    .background(
                        RoundedRectangle(
                            cornerRadius: Theme.Radius.recorderKeyCap, style: .continuous
                        )
                        .fill(Color.primary.opacity(0.08))
                    )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caps.joined(separator: " "))
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) {
            Button {
                settings.terminalShortcuts = settings.terminalShortcuts.setting(nil, for: action)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .opacity(hovered ? 1 : 0)
            .allowsHitTesting(hovered)
        }
    }

    private func stopRecording() {
        removeMonitor()
        conflictTitle = nil
        if recordingAction == action {
            recordingAction = nil
        }
    }

    private func startMonitor() {
        removeMonitor()
        let holder = hitHolder
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown],
            handler: { @MainActor event in
                switch event.type {
                case .leftMouseDown, .rightMouseDown:
                    guard !holder.contains(event) else { return event }
                    stopRecording()
                    return event
                case .keyDown:
                    if Int(event.keyCode) == kVK_Escape,
                        event.modifierFlags.isDisjoint(
                            with: [.command, .option, .control, .shift])
                    {
                        stopRecording()
                        return nil
                    }
                    guard let captured = TerminalKeyEventBridge.chord(from: event),
                        captured.isValid
                    else {
                        return nil
                    }
                    if let owner = settings.terminalShortcuts.conflict(
                        for: captured, excluding: action)
                    {
                        conflictTitle = owner.localizedTitle
                        return nil
                    }
                    settings.terminalShortcuts = settings.terminalShortcuts.setting(
                        captured, for: action)
                    stopRecording()
                    return nil
                default:
                    return event
                }
            })
    }

    private func removeMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}

@MainActor
private final class RecorderViewHolder {
    weak var view: NSView?

    func contains(_ event: NSEvent) -> Bool {
        guard let view, view.window === event.window else { return false }
        let local = view.convert(event.locationInWindow, from: nil)
        return view.bounds.contains(local)
    }
}

private struct TerminalRecorderHitRegion: NSViewRepresentable {
    let holder: RecorderViewHolder

    func makeNSView(context: Context) -> PassiveView {
        let view = PassiveView()
        view.holder = holder
        holder.view = view
        return view
    }

    func updateNSView(_ view: PassiveView, context: Context) {
        view.holder = holder
        holder.view = view
    }

    static func dismantleNSView(_ view: PassiveView, coordinator: ()) {
        if let current = view.holder, current.view === view {
            current.view = nil
        }
    }

    final class PassiveView: NSView {
        weak var holder: RecorderViewHolder?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

extension TerminalShortcutAction {
    var localizedTitle: String {
        switch self {
        case .toggleTerminalMode: String(localized: "Toggle Hybrid Mode")
        case .switchToTerminal: String(localized: "Switch Hybrid / Terminal Mode")
        case .copyLastOutput: String(localized: "Copy Latest Output")
        case .openExternalTerminal: String(localized: "Continue in External Terminal")
        case .runInTerminal: String(localized: "Run in New Tab")
        case .cycleFolder: String(localized: "Cycle Recent Folder")
        case .newTab: String(localized: "New Tab")
        case .closeTab: String(localized: "Close Tab")
        case .stopCommand: String(localized: "Stop Command")
        case .clearOutput: String(localized: "Clear Output")
        }
    }

    var localizedSubtitle: String {
        switch self {
        case .toggleTerminalMode:
            String(localized: "Switch between Standard Mode and Hybrid Mode in the launcher.")
        case .switchToTerminal:
            String(localized: "Move between Hybrid Mode and interactive Terminal Mode, carrying typed input.")
        case .copyLastOutput:
            String(localized: "Copy the most recent command's output in Hybrid or Terminal Mode.")
        case .openExternalTerminal:
            String(localized: "Hand off the working folder and typed command to your external terminal app.")
        case .runInTerminal:
            String(localized: "Run the command in a new tab in Hybrid Mode, or open a new tab in Terminal Mode.")
        case .cycleFolder:
            String(localized: "Switch to the next recent working directory.")
        case .newTab:
            String(localized: "Open an empty terminal tab in the active directory.")
        case .closeTab:
            String(localized: "Close the selected terminal tab.")
        case .stopCommand:
            String(localized: "Terminate the command running in the selected tab.")
        case .clearOutput:
            String(localized: "Clear the scrollback log of the selected tab.")
        }
    }
}

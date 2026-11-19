import AppKit

/// The ⌘⇥ window switcher: opens on the tap's command, walks the board, switches on release.
@MainActor
final class WindowPickerCoordinator: HealthCheckable {
    private let settings: AppSettings
    private let session: WindowPickerSession
    private let tap = WindowPickerTap()
    private let controller = WindowPickerController()
    private var thumbnails: Task<Void, Never>?
    private var groupOpening: Task<Void, Never>?
    /// Bumped per show, so a preview captured for an earlier one is never applied.
    private var generation = 0

    weak var healthTicker: HealthTicker?

    init(settings: AppSettings, session: WindowPickerSession) {
        self.settings = settings
        self.session = session
        tap.onCommand = { [weak self] in self?.handle($0) }
    }

    func applyEnabled() {
        guard settings.windowPickerEnabled else {
            close()
            tap.tearDown()
            healthTicker?.unsubscribe(self)
            return
        }
        healthTicker?.subscribe(self)
        installTap()
    }

    /// Asked from the switch itself, never at launch: a prompt needs a gesture to explain it.
    func requestPermissions() {
        guard settings.windowPickerEnabled else { return }
        Permissions.ensureAccessibility()
        if settings.windowPickerShowsPreviews { Permissions.requestScreenRecording() }
    }

    func prepareForTermination() {
        close()
        tap.tearDown()
        healthTicker?.unsubscribe(self)
    }

    /// The tap cannot exist before the grant, and macOS disables it when the grant is revoked.
    func healthCheck() {
        guard settings.windowPickerEnabled else { return }
        if tap.isInstalled, !tap.isEnabled { tap.tearDown() }
        if !tap.isInstalled { installTap() }
        closeIfReleaseWasMissed()
    }

    /// Secure Input hides the release from the tap, which would leave the panel up for good.
    private func closeIfReleaseWasMissed() {
        guard session.isPresented else { return }
        let held = NSEvent.modifierFlags
        let chords = [settings.windowPickerChord, settings.windowPickerAppChord]
        let stillHeld = chords.contains { chord in
            switch chord {
            case .off: false
            case .command: held.contains(.command)
            case .option: held.contains(.option)
            case .control: held.contains(.control)
            }
        }
        if !stillHeld { close() }
    }

    private func installTap() {
        guard Permissions.isAccessibilityTrusted() else { return }
        tap.install(engine: engine())
    }

    private func engine() -> WindowPickerKeyEngine {
        WindowPickerKeyEngine(
            triggers: WindowPickerKeyEngine.triggers(
                allWindows: settings.windowPickerChord, frontApp: settings.windowPickerAppChord),
            actionKeys: Self.actionKeys())
    }

    private func limits() -> WindowPickerGeometry.Limits {
        WindowPickerGeometry.Limits(
            maxColumns: settings.windowPickerMaxColumns.rawValue,
            maxRows: settings.windowPickerMaxRows.rawValue,
            widthShare: settings.windowPickerMaxWidth.fraction,
            heightShare: settings.windowPickerMaxHeight.fraction,
            tileScale: settings.windowPickerTileSize.scale)
    }

    /// W, Q and H by what the keys type, so they hold on a layout that moves them.
    private static func actionKeys() -> [UInt16: WindowPickerKeyEngine.Action] {
        let letters: [String: WindowPickerKeyEngine.Action] = ["w": .close, "q": .quit, "h": .hide]
        let characters = ASCIIKeyboardLayout.baseCharacters(for: 0..<128)
        var keys: [UInt16: WindowPickerKeyEngine.Action] = [:]
        for (keyCode, character) in characters.sorted(by: { $0.key < $1.key }) {
            guard let action = letters[character.lowercased()], !keys.values.contains(action)
            else { continue }
            keys[UInt16(keyCode)] = action
        }
        return keys.count == letters.count ? keys : WindowPickerKeyEngine.KeyCode.defaultActions
    }

    // MARK: - Commands

    private func handle(_ command: WindowPickerKeyEngine.Command) {
        if case .open(let scope, let backwards) = command {
            return open(scope, backwards: backwards)
        }
        guard session.isPresented else { return }
        switch command {
        case .open: break
        case .step(let offset): change { $0.step(by: offset) }
        case .move(let direction):
            let columns = session.layout?.columns ?? 1
            change { $0.move(direction, columns: columns) }
        case .toggleGrouping: change { $0.toggleGrouping() }
        case .toggleGroup: change { $0.toggleGroup() }
        case .pick(let index): pick(number: index)
        case .perform(let action): perform(action)
        case .commit: commit()
        case .cancel: close()
        }
    }

    private func open(_ scope: WindowPickerKeyEngine.Scope, backwards: Bool) {
        guard settings.windowPickerEnabled, Permissions.isAccessibilityTrusted(),
            let screen = NSScreen.underCursor
        else { return close() }
        thumbnails?.cancel()
        groupOpening?.cancel()
        let ranks = WindowZOrder.ranks()
        let snapshot = WindowSwitchSweep.snapshot(ranks: ranks.apps)
        let windowIDs = snapshot.elements.compactMapValues { AXWindowAccess.windowID(of: $0.window) }
        var entries = snapshot.entries
        if scope == .frontApp {
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
            entries.removeAll { snapshot.elements[$0.handle]?.app.processIdentifier != front }
        }
        let ordered = WindowPickerOrder.sorted(
            entries, windowRanks: windowIDs.compactMapValues { ranks.windows[$0] })
        guard !ordered.isEmpty else { return close() }

        tap.install(engine: engine())
        generation &+= 1
        session.present(
            WindowPickerBoard(
                entries: ordered, isGrouped: settings.windowPickerGroupsByApp,
                allowsGrouping: scope == .allWindows, backwards: backwards),
            elements: snapshot.elements, screenSize: screen.visibleFrame.size, limits: limits())
        guard let layout = session.layout else { return close() }
        controller.show(
            WindowPickerView(session: session) { [weak self] in self?.pick($0) },
            size: layout.panel, on: screen)
        capturePreviews(of: ordered, windowIDs: windowIDs, scale: screen.backingScaleFactor)
        scheduleGroupOpening()
    }

    private func change(_ mutation: (inout WindowPickerBoard) -> Void) {
        session.update(mutation)
        guard let board = session.board, !board.tiles.isEmpty, let layout = session.layout
        else { return close() }
        controller.resize(to: layout.panel)
        scheduleGroupOpening()
    }

    private func pick(_ index: Int) {
        session.update { $0.select(index) }
        commit()
    }

    /// A number on a closed group opens it, so the same keys then reach the windows inside.
    private func pick(number index: Int) {
        guard let board = session.board, board.tiles.indices.contains(index) else { return }
        session.update { $0.select(index) }
        if session.board?.canExpandSelection == true {
            change { $0.expandSelection() }
        } else {
            commit()
        }
    }

    private func commit() {
        let entry = session.board?.target
        let element = entry.flatMap { session.element(for: $0.handle) }
        // Resolved before the close, which drops the element table.
        close()
        guard let entry, let element else { return }
        if entry.isMinimized { _ = AXWindowAccess.unminimize(element.window) }
        AXWindowAccess.focus(element.window, in: element.application, of: element.app)
    }

    private func perform(_ action: WindowPickerKeyEngine.Action) {
        guard let entry = session.board?.target, let element = session.element(for: entry.handle)
        else { return }
        switch action {
        case .close:
            guard AXWindowAccess.close(element.window) else { return }
            change { $0.remove(handles: [entry.handle]) }
        // Its tiles leave when the app exits, so a quit refused by a save sheet keeps them.
        case .quit: element.app.terminate()
        case .hide:
            if !element.app.hide() {
                AXWindowAccess.setHidden(true, application: element.application)
            }
            let hidden = session.handles(of: element.app.processIdentifier)
            change { $0.remove(handles: hidden) }
        }
    }

    private func close() {
        thumbnails?.cancel()
        thumbnails = nil
        groupOpening?.cancel()
        groupOpening = nil
        controller.hide()
        session.reset()
        tap.reset()
    }

    // MARK: - Groups and previews

    private func scheduleGroupOpening() {
        groupOpening?.cancel()
        groupOpening = nil
        guard let delay = settings.windowPickerGroupDelay.duration,
            session.board?.canExpandSelection == true
        else { return }
        groupOpening = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            groupOpening = nil
            change { $0.expandSelection() }
        }
    }

    private func capturePreviews(
        of entries: [WindowSwitchEntry], windowIDs: [Int: CGWindowID], scale: CGFloat
    ) {
        guard settings.windowPickerShowsPreviews, Permissions.hasScreenRecording() else { return }
        // A minimized window has no live surface; its tile keeps the app icon.
        let captured = entries.filter { !$0.isMinimized }.compactMap { entry in
            windowIDs[entry.handle].map { (id: $0, handle: entry.handle) }
        }
        let handles = Dictionary(
            captured.map { ($0.id, $0.handle) }, uniquingKeysWith: { first, _ in first })
        let size = WindowPickerGeometry.preview(tileScale: settings.windowPickerTileSize.scale)
        let pixels = CGSize(width: size.width * scale, height: size.height * scale)
        let generation = generation
        thumbnails = Task { [weak self] in
            await WindowThumbnailProvider.capture(
                windowIDs: captured.map(\.id), pixelSize: pixels
            ) { id, image in
                guard let self, self.generation == generation, let handle = handles[id]
                else { return }
                self.session.setThumbnail(image, for: handle)
            }
        }
    }
}

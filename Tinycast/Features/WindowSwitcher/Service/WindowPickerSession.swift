import AppKit

/// One showing of the picker: its board, its grid and the previews that have arrived so far.
@MainActor
@Observable
final class WindowPickerSession {
    private(set) var board: WindowPickerBoard?
    private(set) var layout: WindowPickerGeometry.Layout?
    /// Keyed by handle; the coordinator keeps the last capture per window between showings.
    private(set) var thumbnails: [Int: CGImage] = [:]

    @ObservationIgnored private var elements: [Int: WindowSwitchSweep.Element] = [:]
    @ObservationIgnored private var screenSize: CGSize = .zero
    @ObservationIgnored private var limits = WindowPickerGeometry.Limits()
    @ObservationIgnored private var terminationToken: NotificationCenter.ObservationToken?

    var isPresented: Bool { board != nil }

    func present(
        _ board: WindowPickerBoard, elements: [Int: WindowSwitchSweep.Element], screenSize: CGSize,
        limits: WindowPickerGeometry.Limits, thumbnails: [Int: CGImage] = [:]
    ) {
        self.limits = limits
        self.elements = elements
        self.screenSize = screenSize
        self.thumbnails = thumbnails
        self.board = board
        relayout()
        observeTerminations()
    }

    func reset() {
        if let terminationToken {
            NSWorkspace.shared.notificationCenter.removeObserver(terminationToken)
        }
        terminationToken = nil
        board = nil
        layout = nil
        thumbnails = [:]
        elements = [:]
    }

    func update(_ change: (inout WindowPickerBoard) -> Void) {
        guard var board else { return }
        change(&board)
        guard board != self.board else { return }
        self.board = board
        relayout()
    }

    func element(for handle: Int) -> WindowSwitchSweep.Element? {
        guard let element = elements[handle], !element.app.isTerminated else { return nil }
        return element
    }

    func handles(of pid: pid_t) -> Set<Int> {
        Set(elements.compactMap { $0.value.app.processIdentifier == pid ? $0.key : nil })
    }

    func setThumbnail(_ image: CGImage, for handle: Int) {
        guard board != nil else { return }
        thumbnails[handle] = image
    }

    private func relayout() {
        guard let board else { return }
        let next =
            board.sections.isEmpty
            ? WindowPickerGeometry.layout(
                tileCount: board.tiles.count, screen: screenSize,
                showsHeader: board.showsHeader, limits: limits)
            : WindowPickerGeometry.groupLayout(
                sectionSizes: board.sections.map(\.count), screen: screenSize, limits: limits)
        if next != layout { layout = next }
    }

    private func observeTerminations() {
        guard terminationToken == nil else { return }
        terminationToken = NSWorkspace.shared.notificationCenter.addObserver(
            of: NSWorkspace.shared, for: NSWorkspace.DidTerminateApplicationMessage.self
        ) { [weak self] message in
            guard let self else { return }
            let gone = handles(of: message.application.processIdentifier)
            update { $0.remove(handles: gone) }
        }
    }
}

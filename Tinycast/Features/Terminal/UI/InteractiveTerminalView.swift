import AppKit
import Carbon.HIToolbox
import SwiftUI

struct InteractiveTerminalView: NSViewRepresentable {
    let tab: TerminalTab
    let theme: TerminalColorTheme
    let isDark: Bool
    let interactiveFocusEnabled: Bool
    let shouldAutoFocus: Bool
    let fontSize: CGFloat
    let horizontalInset: CGFloat
    let bottomClearance: CGFloat
    let onCopyFeedback: () -> Void

    func makeNSView(context: Context) -> TerminalSurfaceNSView {
        let view = TerminalSurfaceNSView()
        view.configure(
            tab: tab,
            theme: theme,
            isDark: isDark,
            interactiveFocusEnabled: interactiveFocusEnabled,
            fontSize: fontSize,
            horizontalInset: horizontalInset,
            bottomClearance: bottomClearance,
            onCopyFeedback: onCopyFeedback)
        return view
    }

    func updateNSView(_ nsView: TerminalSurfaceNSView, context: Context) {
        _ = tab.revision
        let focusToken = tab.focusToken
        nsView.configure(
            tab: tab,
            theme: theme,
            isDark: isDark,
            interactiveFocusEnabled: interactiveFocusEnabled,
            fontSize: fontSize,
            horizontalInset: horizontalInset,
            bottomClearance: bottomClearance,
            onCopyFeedback: onCopyFeedback)
        if interactiveFocusEnabled && shouldAutoFocus {
            nsView.applyFocusIfNeeded(token: focusToken)
        }
    }
}

@MainActor
final class TerminalSurfaceNSView: NSView, @preconcurrency NSTextInputClient, TerminalKeyInputView {
    private weak var tab: TerminalTab?
    private var theme: TerminalColorTheme = .standard
    private var isDark = true
    private var interactiveFocusEnabled = true
    private var fontSize: CGFloat = 12.5
    private var horizontalInset: CGFloat = 24
    private var topInset: CGFloat = 8
    private var bottomClearance: CGFloat = 52
    private var onCopyFeedback: (() -> Void)?

    private var regularFont = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
    private var boldFont = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .semibold)
    private var italicFont = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
    private var boldItalicFont = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .semibold)
    private var cellWidth: CGFloat = 7.6
    private var cellHeight: CGFloat = 18.0
    private var baselineOffset: CGFloat = 13.0

    private var scrollOffset = 0
    private var wheelAccumulator: CGFloat = 0
    private var selectionAnchor: TerminalGridPoint?
    private var selectionEnd: TerminalGridPoint?
    private var markedTextStorage = ""
    private var markedSelectedRange = NSRange(location: 0, length: 0)

    private var lastAppliedFocusToken = -1
    private weak var lastFocusedTab: TerminalTab?
    private var cursorBlinkOn = true
    private var blinkTask: Task<Void, Never>?
    private var windowKeyTokens: [NotificationToken] = []

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { interactiveFocusEnabled }

    var hasActiveMarkedText: Bool { !markedTextStorage.isEmpty }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.drawsAsynchronously = false
        rebuildFonts()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        blinkTask?.cancel()
    }

    func configure(
        tab: TerminalTab,
        theme: TerminalColorTheme,
        isDark: Bool,
        interactiveFocusEnabled: Bool,
        fontSize: CGFloat,
        horizontalInset: CGFloat,
        bottomClearance: CGFloat,
        onCopyFeedback: @escaping () -> Void
    ) {
        let switchedTab = (self.tab !== tab)
        let fontChanged = abs(self.fontSize - fontSize) > 0.05
        let insetChanged =
            abs(self.horizontalInset - horizontalInset) > 0.5
            || abs(self.bottomClearance - bottomClearance) > 0.5

        self.tab = tab
        self.theme = theme
        self.isDark = theme.effectiveIsDark(systemIsDark: isDark)
        self.interactiveFocusEnabled = interactiveFocusEnabled
        self.fontSize = fontSize
        self.horizontalInset = horizontalInset
        self.bottomClearance = bottomClearance
        self.onCopyFeedback = onCopyFeedback

        if !interactiveFocusEnabled, let window, window.firstResponder === self {
            _ = window.makeFirstResponder(nil)
        }

        if fontChanged {
            rebuildFonts()
        }
        if switchedTab {
            scrollOffset = 0
            selectionAnchor = nil
            selectionEnd = nil
            markedTextStorage = ""
        }
        let maxScroll = tab.emulator.isAlternateScreen ? 0 : tab.emulator.scrollback.count
        if scrollOffset > maxScroll {
            scrollOffset = maxScroll
        }
        if switchedTab || fontChanged || insetChanged {
            syncTerminalGridSize()
        }
        needsDisplay = true
    }

    func applyFocusIfNeeded(token: Int) {
        guard let tab, let window else { return }
        let needsRefocus = (lastFocusedTab !== tab) || (token != lastAppliedFocusToken)
        guard needsRefocus else { return }
        lastFocusedTab = tab
        lastAppliedFocusToken = token
        if window.firstResponder !== self {
            _ = window.makeFirstResponder(self)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowKeyTokens.removeAll()
        guard let window else {
            stopBlinkTimer()
            return
        }
        let center = NotificationCenter.default
        windowKeyTokens = [
            NotificationToken(
                center.addObserver(
                    forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.updateBlinkState()
                        self?.needsDisplay = true
                    }
                },
                center: center),
            NotificationToken(
                center.addObserver(
                    forName: NSWindow.didResignKeyNotification, object: window, queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.updateBlinkState()
                        self?.needsDisplay = true
                    }
                },
                center: center)
        ]
        syncTerminalGridSize()
        if interactiveFocusEnabled,
            window.firstResponder == nil || window.firstResponder === window
        {
            _ = window.makeFirstResponder(self)
        }
        updateBlinkState()
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            resetBlinkToSolid()
            needsDisplay = true
        }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok {
            stopBlinkTimer()
            needsDisplay = true
        }
        return ok
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncTerminalGridSize()
    }

    private func rebuildFonts() {
        let base = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let bold = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)
        regularFont = base
        boldFont = bold
        italicFont = NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
        boldItalicFont = NSFontManager.shared.convert(bold, toHaveTrait: .italicFontMask)

        let sampleWidth = ("M" as NSString).size(withAttributes: [.font: base]).width
        cellWidth = max(6.0, sampleWidth)
        let rawLine = ceil(base.ascender - base.descender + max(0, base.leading))
        cellHeight = max(14.0, rawLine + 3.0)
        baselineOffset = ceil(base.ascender) + 1.0
    }

    private func syncTerminalGridSize() {
        guard let tab, bounds.width > 40, bounds.height > 40 else { return }
        let usableWidth = max(80, bounds.width - horizontalInset * 2)
        let usableHeight = max(36, bounds.height - topInset - bottomClearance)
        let cols = max(20, Int(floor(usableWidth / cellWidth)))
        let rows = max(4, Int(floor(usableHeight / cellHeight)))
        tab.resizeTerminal(cols: cols, rows: rows)
    }

    private var isTerminalFocused: Bool {
        guard let window else { return false }
        return window.isKeyWindow && window.firstResponder === self
    }

    private func updateBlinkState() {
        if isTerminalFocused {
            resetBlinkToSolid()
        } else {
            stopBlinkTimer()
        }
    }

    private func resetBlinkToSolid() {
        cursorBlinkOn = true
        blinkTask?.cancel()
        blinkTask = nil
        guard isTerminalFocused else { return }
        blinkTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(530))
                guard !Task.isCancelled, let self else { break }
                self.cursorBlinkOn.toggle()
                self.needsDisplay = true
            }
        }
    }

    private func stopBlinkTimer() {
        blinkTask?.cancel()
        blinkTask = nil
        cursorBlinkOn = true
    }

    // MARK: - TerminalKeyInputView

    func handleTerminalEscape() -> Bool {
        if selectionAnchor != nil || selectionEnd != nil {
            selectionAnchor = nil
            selectionEnd = nil
            needsDisplay = true
            return true
        }
        guard let tab else { return false }
        if tab.emulator.isAlternateScreen || tab.isRunningCommand {
            tab.sendBytesImmediately([0x1B])
            return true
        }
        return false
    }

    func copySelectionIfPresent() -> Bool {
        guard let tab,
            let a = selectionAnchor,
            let b = selectionEnd,
            a != b
        else { return false }
        let text = tab.emulator.text(from: a, to: b)
        guard !text.isEmpty else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        onCopyFeedback?()
        return true
    }

    func pasteFromClipboard() {
        guard let tab,
            let text = NSPasteboard.general.string(forType: .string),
            !text.isEmpty
        else { return }
        scrollOffset = 0
        selectionAnchor = nil
        selectionEnd = nil
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\r")
            .replacingOccurrences(of: "\n", with: "\r")
        if tab.emulator.bracketedPaste {
            tab.sendTextImmediately("\u{1B}[200~" + normalized + "\u{1B}[201~")
        } else {
            tab.sendTextImmediately(normalized)
        }
        resetBlinkToSolid()
        needsDisplay = true
    }

    func selectAllTerminalText() {
        guard let tab, tab.emulator.totalLines > 0 else { return }
        selectionAnchor = TerminalGridPoint(line: 0, col: 0)
        selectionEnd = TerminalGridPoint(
            line: tab.emulator.totalLines - 1,
            col: max(0, tab.emulator.cols - 1))
        needsDisplay = true
    }

    @objc func copy(_ sender: Any?) {
        _ = copySelectionIfPresent()
    }

    @objc func paste(_ sender: Any?) {
        pasteFromClipboard()
    }

    @objc override func selectAll(_ sender: Any?) {
        selectAllTerminalText()
    }

    override func keyDown(with event: NSEvent) {
        handleTerminalKeyDown(event)
    }

    func handleTerminalKeyDown(_ event: NSEvent) {
        guard let tab else { return }
        resetBlinkToSolid()

        if !hasActiveMarkedText {
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])

            if mods == [.shift], !tab.emulator.isAlternateScreen {
                if Int(event.keyCode) == kVK_PageUp {
                    scrollByLines(max(1, tab.emulator.rows - 2))
                    return
                }
                if Int(event.keyCode) == kVK_PageDown {
                    scrollByLines(-max(1, tab.emulator.rows - 2))
                    return
                }
            }

            if mods == [.command],
                ASCIIKeyboardLayout.character(for: event)?.lowercased() == "l"
            {
                scrollOffset = 0
                tab.clearOutput()
                needsDisplay = true
                return
            }

            if let encoded = encodeSpecialOrControlKey(event: event, emulator: tab.emulator) {
                scrollOffset = 0
                selectionAnchor = nil
                selectionEnd = nil
                tab.sendBytesImmediately(encoded)
                needsDisplay = true
                return
            }
        }

        interpretKeyEvents([event])
    }

    private func encodeSpecialOrControlKey(
        event: NSEvent, emulator: TerminalEmulator
    ) -> [UInt8]? {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let appCursor = emulator.applicationCursorKeys
        let altScreen = emulator.isAlternateScreen
        let keyCode = Int(event.keyCode)

        if mods.contains(.command) {
            if keyCode == kVK_LeftArrow {
                return altScreen ? Array("\u{1B}[H".utf8) : [0x01]
            }
            if keyCode == kVK_RightArrow {
                return altScreen ? Array("\u{1B}[F".utf8) : [0x05]
            }
            if keyCode == kVK_Delete {
                return [0x15]
            }
            return nil
        }

        switch keyCode {
        case kVK_Return, kVK_ANSI_KeypadEnter:
            return mods.contains(.option) ? [0x1B, 0x0D] : [0x0D]
        case kVK_Delete:
            if mods.contains(.option) { return [0x17] }
            return [0x7F]
        case kVK_ForwardDelete:
            if mods.contains(.option) { return Array("\u{1B}d".utf8) }
            return modifiedTildeSequence(code: 3, mods: mods)
        case kVK_Tab:
            if mods.contains(.shift) { return Array("\u{1B}[Z".utf8) }
            return [0x09]
        case kVK_Escape:
            return [0x1B]
        case kVK_UpArrow:
            return cursorKeySequence(letter: "A", mods: mods, appCursor: appCursor)
        case kVK_DownArrow:
            return cursorKeySequence(letter: "B", mods: mods, appCursor: appCursor)
        case kVK_RightArrow:
            if mods == [.option] && !altScreen { return Array("\u{1B}f".utf8) }
            return cursorKeySequence(letter: "C", mods: mods, appCursor: appCursor)
        case kVK_LeftArrow:
            if mods == [.option] && !altScreen { return Array("\u{1B}b".utf8) }
            return cursorKeySequence(letter: "D", mods: mods, appCursor: appCursor)
        case kVK_Home:
            return cursorKeySequence(letter: "H", mods: mods, appCursor: appCursor)
        case kVK_End:
            return cursorKeySequence(letter: "F", mods: mods, appCursor: appCursor)
        case kVK_PageUp:
            return modifiedTildeSequence(code: 5, mods: mods)
        case kVK_PageDown:
            return modifiedTildeSequence(code: 6, mods: mods)
        case kVK_F1: return functionKeySequence(index: 1, mods: mods)
        case kVK_F2: return functionKeySequence(index: 2, mods: mods)
        case kVK_F3: return functionKeySequence(index: 3, mods: mods)
        case kVK_F4: return functionKeySequence(index: 4, mods: mods)
        case kVK_F5: return modifiedTildeSequence(code: 15, mods: mods)
        case kVK_F6: return modifiedTildeSequence(code: 17, mods: mods)
        case kVK_F7: return modifiedTildeSequence(code: 18, mods: mods)
        case kVK_F8: return modifiedTildeSequence(code: 19, mods: mods)
        case kVK_F9: return modifiedTildeSequence(code: 20, mods: mods)
        case kVK_F10: return modifiedTildeSequence(code: 21, mods: mods)
        case kVK_F11: return modifiedTildeSequence(code: 23, mods: mods)
        case kVK_F12: return modifiedTildeSequence(code: 24, mods: mods)
        default:
            break
        }

        if mods.contains(.control) {
            if keyCode == kVK_Space {
                return [0x00]
            }
            if let ch = (ASCIIKeyboardLayout.character(for: event)
                ?? event.charactersIgnoringModifiers)?.lowercased().first,
                let ascii = ch.asciiValue
            {
                let byte: UInt8? =
                    switch ascii {
                    case 0x61...0x7A: ascii - 0x60
                    case 0x40, 0x20: 0x00
                    case 0x5B: 0x1B
                    case 0x5C: 0x1C
                    case 0x5D: 0x1D
                    case 0x5E: 0x1E
                    case 0x5F, 0x2F: 0x1F
                    case 0x3F: 0x7F
                    default: nil
                    }
                if let byte {
                    return mods.contains(.option) ? [0x1B, byte] : [byte]
                }
            }
        }

        return nil
    }

    private func xtermModifierParam(_ mods: NSEvent.ModifierFlags) -> Int {
        var code = 1
        if mods.contains(.shift) { code += 1 }
        if mods.contains(.option) { code += 2 }
        if mods.contains(.control) { code += 4 }
        return code
    }

    private func cursorKeySequence(
        letter: String, mods: NSEvent.ModifierFlags, appCursor: Bool
    ) -> [UInt8] {
        let param = xtermModifierParam(mods)
        if param > 1 {
            return Array("\u{1B}[1;\(param)\(letter)".utf8)
        }
        let prefix = appCursor ? "\u{1B}O" : "\u{1B}["
        return Array("\(prefix)\(letter)".utf8)
    }

    private func modifiedTildeSequence(code: Int, mods: NSEvent.ModifierFlags) -> [UInt8] {
        let param = xtermModifierParam(mods)
        if param > 1 {
            return Array("\u{1B}[\(code);\(param)~".utf8)
        }
        return Array("\u{1B}[\(code)~".utf8)
    }

    private func functionKeySequence(index: Int, mods: NSEvent.ModifierFlags) -> [UInt8] {
        let letters = ["P", "Q", "R", "S"]
        let letter = letters[max(0, min(3, index - 1))]
        let param = xtermModifierParam(mods)
        if param > 1 {
            return Array("\u{1B}[1;\(param)\(letter)".utf8)
        }
        return Array("\u{1B}O\(letter)".utf8)
    }

    // MARK: - NSTextInputClient

    func insertText(_ string: Any, replacementRange: NSRange) {
        let text: String
        if let str = string as? String {
            text = str
        } else if let attr = string as? NSAttributedString {
            text = attr.string
        } else {
            return
        }
        markedTextStorage = ""
        markedSelectedRange = NSRange(location: 0, length: 0)
        guard !text.isEmpty else {
            needsDisplay = true
            return
        }
        scrollOffset = 0
        selectionAnchor = nil
        selectionEnd = nil
        tab?.sendTextImmediately(text)
        needsDisplay = true
    }

    override func doCommand(by selector: Selector) {}

    func setMarkedText(
        _ string: Any, selectedRange: NSRange, replacementRange: NSRange
    ) {
        if let str = string as? String {
            markedTextStorage = str
        } else if let attr = string as? NSAttributedString {
            markedTextStorage = attr.string
        } else {
            markedTextStorage = ""
        }
        markedSelectedRange = selectedRange
        needsDisplay = true
    }

    func unmarkText() {
        markedTextStorage = ""
        markedSelectedRange = NSRange(location: 0, length: 0)
        needsDisplay = true
    }

    func selectedRange() -> NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    func markedRange() -> NSRange {
        guard !markedTextStorage.isEmpty else {
            return NSRange(location: NSNotFound, length: 0)
        }
        return NSRange(location: 0, length: (markedTextStorage as NSString).length)
    }

    func hasMarkedText() -> Bool {
        !markedTextStorage.isEmpty
    }

    func attributedSubstring(
        forProposedRange range: NSRange, actualRange: NSRangePointer?
    ) -> NSAttributedString? {
        nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func firstRect(
        forCharacterRange range: NSRange, actualRange: NSRangePointer?
    ) -> NSRect {
        guard let window, let tab else { return .zero }
        let x = horizontalInset + CGFloat(tab.emulator.cursorCol) * cellWidth
        let y = topInset + CGFloat(tab.emulator.cursorRow) * cellHeight
        let localRect = NSRect(x: x, y: y, width: cellWidth, height: cellHeight)
        let inWindow = convert(localRect, to: nil)
        return window.convertToScreen(inWindow)
    }

    func characterIndex(for point: NSPoint) -> Int {
        0
    }

    // MARK: - Mouse & Scrollback

    override func mouseDown(with event: NSEvent) {
        if interactiveFocusEnabled {
            _ = window?.makeFirstResponder(self)
        }
        guard let tab else { return }
        let pt = gridPoint(for: convert(event.locationInWindow, from: nil), in: tab.emulator)

        if event.clickCount >= 3 {
            let lineLen = max(0, tab.emulator.cols - 1)
            selectionAnchor = TerminalGridPoint(line: pt.line, col: 0)
            selectionEnd = TerminalGridPoint(line: pt.line, col: lineLen)
        } else if event.clickCount == 2 {
            let range = wordBounds(at: pt, in: tab.emulator)
            selectionAnchor = TerminalGridPoint(line: pt.line, col: range.lowerBound)
            selectionEnd = TerminalGridPoint(line: pt.line, col: range.upperBound)
        } else {
            selectionAnchor = pt
            selectionEnd = pt
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let tab else { return }
        let local = convert(event.locationInWindow, from: nil)
        if !tab.emulator.isAlternateScreen {
            if local.y < topInset {
                scrollByLines(1)
            } else if local.y > bounds.height - bottomClearance {
                scrollByLines(-1)
            }
        }
        selectionEnd = gridPoint(for: local, in: tab.emulator)
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        guard let tab else { return }
        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 14
        guard abs(dy) > 0.01 else { return }

        if tab.emulator.isAlternateScreen {
            wheelAccumulator += dy
            let step: CGFloat = 20
            while abs(wheelAccumulator) >= step {
                let up = wheelAccumulator > 0
                wheelAccumulator += up ? -step : step
                if tab.emulator.mouseTrackingMode > 0 && tab.emulator.sgrMouseMode {
                    let local = convert(event.locationInWindow, from: nil)
                    let col = min(
                        max(1, Int(floor((local.x - horizontalInset) / cellWidth)) + 1),
                        tab.emulator.cols)
                    let row = min(
                        max(1, Int(floor((local.y - topInset) / cellHeight)) + 1),
                        tab.emulator.rows)
                    let btn = up ? 64 : 65
                    tab.sendTextImmediately("\u{1B}[<\(btn);\(col);\(row)M")
                } else {
                    let seq =
                        up
                        ? (tab.emulator.applicationCursorKeys ? "\u{1B}OA" : "\u{1B}[A")
                        : (tab.emulator.applicationCursorKeys ? "\u{1B}OB" : "\u{1B}[B")
                    tab.sendTextImmediately(seq)
                }
            }
            return
        }

        wheelAccumulator += dy
        let linePixels = max(12.0, cellHeight * 0.85)
        let deltaLines = Int(wheelAccumulator / linePixels)
        if deltaLines != 0 {
            wheelAccumulator -= CGFloat(deltaLines) * linePixels
            scrollByLines(deltaLines)
        }
    }

    private func scrollByLines(_ delta: Int) {
        guard let tab else { return }
        let maxOffset = tab.emulator.isAlternateScreen ? 0 : tab.emulator.scrollback.count
        let next = min(max(0, scrollOffset + delta), maxOffset)
        guard next != scrollOffset else { return }
        scrollOffset = next
        needsDisplay = true
    }

    private func gridPoint(for local: NSPoint, in emulator: TerminalEmulator) -> TerminalGridPoint {
        let firstVisibleLine = max(0, emulator.scrollback.count - scrollOffset)
        let rowOffset = min(
            max(0, Int(floor((local.y - topInset) / cellHeight))),
            emulator.rows - 1)
        let col = min(
            max(0, Int(floor((local.x - horizontalInset) / cellWidth))),
            emulator.cols - 1)
        return TerminalGridPoint(line: firstVisibleLine + rowOffset, col: col)
    }

    private func wordBounds(
        at point: TerminalGridPoint, in emulator: TerminalEmulator
    ) -> ClosedRange<Int> {
        emulator.withLine(at: point.line) { cells, graphemes, _ in
            let cols = cells.count
            let idx = min(max(0, point.col), max(0, cols - 1))
            let base = cells.startIndex
            func charAt(_ col: Int) -> Character {
                let cell = cells[base + col]
                if cell.hasGraphemeCluster, let cluster = graphemes?[col] {
                    return cluster
                }
                return cell.character
            }
            func isWordChar(_ ch: Character) -> Bool {
                ch.isLetter || ch.isNumber || "_-./~:@+".contains(ch)
            }
            guard cols > 0, isWordChar(charAt(idx)) else { return idx...idx }
            var start = idx
            while start > 0 && isWordChar(charAt(start - 1)) { start -= 1 }
            var end = idx
            while end + 1 < cols && isWordChar(charAt(end + 1)) { end += 1 }
            return start...end
        } ?? (point.col...point.col)
    }

    // MARK: - CoreGraphics Grid Rendering

    override func draw(_ dirtyRect: NSRect) {
        guard let tab, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let emulator = tab.emulator
        let palette = theme.palette(isDark: isDark)

        if let surfaceRGB = theme.surfaceBackground {
            ctx.setFillColor(nsColor(from: surfaceRGB).cgColor)
            ctx.fill(bounds)
        }

        let defaultFg = nsColor(from: palette.foreground)
        let defaultBg =
            theme.surfaceBackground.map(nsColor(from:))
            ?? (isDark ? NSColor(srgbRed: 0.08, green: 0.09, blue: 0.11, alpha: 1) : .white)
        let selectionFill = NSColor.selectedContentBackgroundColor.withAlphaComponent(
            isDark ? 0.36 : 0.24)

        let firstVisibleLine =
            emulator.isAlternateScreen ? 0 : max(0, emulator.scrollback.count - scrollOffset)
        let hasSelection = selectionAnchor != nil && selectionEnd != nil && selectionAnchor != selectionEnd
        let selLow = hasSelection ? min(selectionAnchor!, selectionEnd!) : nil
        let selHigh = hasSelection ? max(selectionAnchor!, selectionEnd!) : nil
        var asciiBuffer: [UInt8] = []

        for visualRow in 0..<emulator.rows {
            let lineIndex = firstVisibleLine + visualRow
            let y = topInset + CGFloat(visualRow) * cellHeight
            if y + cellHeight < dirtyRect.minY || y > dirtyRect.maxY { continue }
            emulator.withLine(at: lineIndex) { cells, graphemes, _ in
                let base = cells.startIndex
                let colCount = min(cells.count, emulator.cols)

                var col = 0
                while col < colCount {
                    let cell = cells[base + col]
                    let bg = resolvedBackground(for: cell, palette: palette, defaultFg: defaultFg)
                    if let bg {
                        var endCol = col + 1
                        while endCol < colCount,
                            resolvedBackground(
                                for: cells[base + endCol], palette: palette, defaultFg: defaultFg
                            ) == bg
                        {
                            endCol += 1
                        }
                        let rect = NSRect(
                            x: horizontalInset + CGFloat(col) * cellWidth,
                            y: y,
                            width: CGFloat(endCol - col) * cellWidth,
                            height: cellHeight)
                        ctx.setFillColor(bg.cgColor)
                        ctx.fill(rect)
                        col = endCol
                    } else {
                        col += 1
                    }
                }

                if let low = selLow, let high = selHigh,
                    lineIndex >= low.line && lineIndex <= high.line
                {
                    let startC = lineIndex == low.line ? max(0, low.col) : 0
                    let endC = lineIndex == high.line ? min(colCount - 1, high.col) : colCount - 1
                    if startC <= endC {
                        let selRect = NSRect(
                            x: horizontalInset + CGFloat(startC) * cellWidth,
                            y: y,
                            width: CGFloat(endC - startC + 1) * cellWidth,
                            height: cellHeight)
                        ctx.setFillColor(selectionFill.cgColor)
                        ctx.fill(selRect)
                    }
                }

                var textCol = 0
                while textCol < colCount {
                    let cell = cells[base + textCol]
                    if cell.width == 0
                        || cell.isSpace
                        || cell.style.contains(.invisible)
                    {
                        if cell.style.contains(.underline) || cell.style.contains(.strikethrough) {
                            let fg = resolvedForeground(
                                for: cell, palette: palette, defaultFg: defaultFg,
                                defaultBg: defaultBg)
                            drawDecorations(
                                style: cell.style, color: fg, col: textCol, span: 1, y: y, in: ctx)
                        }
                        textCol += 1
                        continue
                    }

                    let fg = resolvedForeground(
                        for: cell, palette: palette, defaultFg: defaultFg, defaultBg: defaultBg)
                    let font = font(for: cell.style)

                    if cell.width == 1, !cell.hasGraphemeCluster, let ascii = cell.asciiByte {
                        asciiBuffer.removeAll(keepingCapacity: true)
                        asciiBuffer.append(ascii)
                        var span = 1
                        while textCol + span < colCount {
                            let next = cells[base + textCol + span]
                            guard next.width == 1,
                                !next.hasGraphemeCluster,
                                let nextASCII = next.asciiByte,
                                nextASCII != 0x20,
                                !next.style.contains(.invisible),
                                next.style == cell.style,
                                next.foreground == cell.foreground,
                                next.background == cell.background
                            else { break }
                            asciiBuffer.append(nextASCII)
                            span += 1
                        }
                        let run = String(bytes: asciiBuffer, encoding: .utf8) ?? ""
                        let pt = NSPoint(
                            x: horizontalInset + CGFloat(textCol) * cellWidth,
                            y: y)
                        (run as NSString).draw(
                            at: pt,
                            withAttributes: [.font: font, .foregroundColor: fg, .kern: 0])
                        if cell.style.contains(.underline) || cell.style.contains(.strikethrough) {
                            drawDecorations(
                                style: cell.style, color: fg, col: textCol, span: span, y: y,
                                in: ctx)
                        }
                        textCol += span
                    } else {
                        let rendered: Character =
                            cell.hasGraphemeCluster
                            ? (graphemes?[textCol] ?? cell.character)
                            : cell.character
                        let pt = NSPoint(
                            x: horizontalInset + CGFloat(textCol) * cellWidth,
                            y: y)
                        (String(rendered) as NSString).draw(
                            at: pt,
                            withAttributes: [.font: font, .foregroundColor: fg])
                        let span = max(1, Int(cell.width))
                        if cell.style.contains(.underline) || cell.style.contains(.strikethrough) {
                            drawDecorations(
                                style: cell.style, color: fg, col: textCol, span: span, y: y,
                                in: ctx)
                        }
                        textCol += span
                    }
                }
            }
        }

        if scrollOffset == 0 && emulator.cursorVisible {
            drawCursor(
                emulator: emulator,
                palette: palette,
                defaultFg: defaultFg,
                defaultBg: defaultBg,
                in: ctx)
        }

        if scrollOffset > 0 && emulator.scrollback.count > 0 && !emulator.isAlternateScreen {
            drawScrollbackThumb(emulator: emulator, color: defaultFg, in: ctx)
        }
    }

    private func drawDecorations(
        style: TerminalCellStyle,
        color: NSColor,
        col: Int,
        span: Int,
        y: CGFloat,
        in ctx: CGContext
    ) {
        let x = horizontalInset + CGFloat(col) * cellWidth
        let width = CGFloat(span) * cellWidth
        ctx.setFillColor(color.cgColor)
        if style.contains(.underline) {
            ctx.fill(NSRect(x: x, y: y + baselineOffset + 2, width: width, height: 1))
        }
        if style.contains(.strikethrough) {
            ctx.fill(NSRect(x: x, y: y + floor(cellHeight * 0.52), width: width, height: 1))
        }
    }

    private func drawCursor(
        emulator: TerminalEmulator,
        palette: TerminalPalette16,
        defaultFg: NSColor,
        defaultBg: NSColor,
        in ctx: CGContext
    ) {
        let cRow = min(max(0, emulator.cursorRow), emulator.rows - 1)
        let cCol = min(max(0, emulator.cursorCol), emulator.cols - 1)
        let x = horizontalInset + CGFloat(cCol) * cellWidth
        let y = topInset + CGFloat(cRow) * cellHeight

        if !markedTextStorage.isEmpty {
            let width = max(cellWidth, CGFloat(markedTextStorage.count) * cellWidth)
            let rect = NSRect(x: x, y: y, width: width, height: cellHeight)
            ctx.setFillColor(defaultBg.withAlphaComponent(0.92).cgColor)
            ctx.fill(rect)
            (markedTextStorage as NSString).draw(
                at: NSPoint(x: x, y: y),
                withAttributes: [
                    .font: regularFont,
                    .foregroundColor: defaultFg,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ])
            return
        }

        let row = emulator.grid[cRow]
        let cell = row.cells[cCol]
        let span: CGFloat = cell.width == 2 ? 2.0 : 1.0
        let cursorRect = NSRect(x: x, y: y + 1, width: cellWidth * span, height: cellHeight - 2)

        if isTerminalFocused {
            guard cursorBlinkOn else { return }
            ctx.setFillColor(defaultFg.withAlphaComponent(0.84).cgColor)
            let path = CGPath(roundedRect: cursorRect, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
            ctx.addPath(path)
            ctx.fillPath()

            if !cell.isSpace && cell.width != 0 && !cell.style.contains(.invisible) {
                (String(row.character(at: cCol)) as NSString).draw(
                    at: NSPoint(x: x, y: y),
                    withAttributes: [
                        .font: font(for: cell.style),
                        .foregroundColor: defaultBg
                    ])
            }
        } else {
            let strokeRect = cursorRect.insetBy(dx: 0.5, dy: 0.5)
            ctx.setStrokeColor(defaultFg.withAlphaComponent(0.55).cgColor)
            ctx.setLineWidth(1.0)
            ctx.stroke(strokeRect)
        }
    }

    private func drawScrollbackThumb(
        emulator: TerminalEmulator, color: NSColor, in ctx: CGContext
    ) {
        let trackTop = topInset + 4
        let trackHeight = max(24, bounds.height - topInset - bottomClearance - 8)
        let total = CGFloat(max(1, emulator.totalLines))
        let visibleRatio = min(1.0, CGFloat(emulator.rows) / total)
        let thumbHeight = max(20, trackHeight * visibleRatio)
        let maxScroll = CGFloat(max(1, emulator.scrollback.count))
        let progressFromTop = 1.0 - (CGFloat(scrollOffset) / maxScroll)
        let thumbY = trackTop + (trackHeight - thumbHeight) * progressFromTop
        let thumbRect = NSRect(x: bounds.width - 7, y: thumbY, width: 3.5, height: thumbHeight)
        let path = CGPath(roundedRect: thumbRect, cornerWidth: 1.75, cornerHeight: 1.75, transform: nil)
        ctx.setFillColor(color.withAlphaComponent(0.28).cgColor)
        ctx.addPath(path)
        ctx.fillPath()
    }

    private func font(for style: TerminalCellStyle) -> NSFont {
        let isBold = style.contains(.bold)
        let isItalic = style.contains(.italic)
        if isBold && isItalic { return boldItalicFont }
        if isBold { return boldFont }
        if isItalic { return italicFont }
        return regularFont
    }

    private func resolvedForeground(
        for cell: TerminalCell,
        palette: TerminalPalette16,
        defaultFg: NSColor,
        defaultBg: NSColor
    ) -> NSColor {
        let inverse = cell.style.contains(.inverse)
        var color: NSColor
        if inverse {
            switch cell.background {
            case .defaultBackground:
                color = defaultBg
            default:
                color = resolveColor(cell.background, palette: palette, fallback: defaultBg)
            }
        } else {
            var fgSpec = cell.foreground
            if cell.style.contains(.bold), case .ansi(let idx) = fgSpec, idx < 8 {
                fgSpec = .ansi(idx + 8)
            }
            color = resolveColor(fgSpec, palette: palette, fallback: defaultFg)
        }
        if cell.style.contains(.dim) {
            color = color.withAlphaComponent(0.62)
        }
        return color
    }

    private func resolvedBackground(
        for cell: TerminalCell,
        palette: TerminalPalette16,
        defaultFg: NSColor
    ) -> NSColor? {
        if cell.style.contains(.inverse) {
            return resolveColor(cell.foreground, palette: palette, fallback: defaultFg)
        }
        if cell.background == .defaultBackground {
            return nil
        }
        return resolveColor(cell.background, palette: palette, fallback: defaultFg)
    }

    private func resolveColor(
        _ spec: TerminalColorSpec,
        palette: TerminalPalette16,
        fallback: NSColor
    ) -> NSColor {
        switch spec {
        case .defaultForeground, .defaultBackground:
            return fallback
        case .ansi(let index):
            return nsColor(from: theme.color256(Int(index), isDark: isDark))
        case .rgb(let r, let g, let b):
            return NSColor(
                srgbRed: CGFloat(r) / 255.0,
                green: CGFloat(g) / 255.0,
                blue: CGFloat(b) / 255.0,
                alpha: 1.0)
        }
    }

    private func nsColor(from rgb: TerminalRGB) -> NSColor {
        NSColor(
            srgbRed: CGFloat(rgb.r) / 255.0,
            green: CGFloat(rgb.g) / 255.0,
            blue: CGFloat(rgb.b) / 255.0,
            alpha: 1.0)
    }
}

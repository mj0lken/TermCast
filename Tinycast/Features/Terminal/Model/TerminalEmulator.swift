import Darwin
import Foundation

enum TerminalColorSpec: Equatable, Hashable, Sendable {
    case defaultForeground
    case defaultBackground
    case ansi(UInt8)
    case rgb(UInt8, UInt8, UInt8)

    fileprivate var packed: UInt32 {
        switch self {
        case .defaultForeground:
            return 0
        case .defaultBackground:
            return 1 << 24
        case .ansi(let index):
            return (2 << 24) | UInt32(index)
        case .rgb(let r, let g, let b):
            return (3 << 24) | (UInt32(r) << 16) | (UInt32(g) << 8) | UInt32(b)
        }
    }

    fileprivate init(packed: UInt32) {
        switch packed >> 24 {
        case 0:
            self = .defaultForeground
        case 1:
            self = .defaultBackground
        case 2:
            self = .ansi(UInt8(truncatingIfNeeded: packed))
        default:
            self = .rgb(
                UInt8(truncatingIfNeeded: packed >> 16),
                UInt8(truncatingIfNeeded: packed >> 8),
                UInt8(truncatingIfNeeded: packed))
        }
    }
}

struct TerminalCellStyle: OptionSet, Hashable, Sendable {
    let rawValue: UInt8

    static let bold = TerminalCellStyle(rawValue: 1 << 0)
    static let dim = TerminalCellStyle(rawValue: 1 << 1)
    static let italic = TerminalCellStyle(rawValue: 1 << 2)
    static let underline = TerminalCellStyle(rawValue: 1 << 3)
    static let inverse = TerminalCellStyle(rawValue: 1 << 4)
    static let strikethrough = TerminalCellStyle(rawValue: 1 << 5)
    static let invisible = TerminalCellStyle(rawValue: 1 << 6)
}

/// 16-byte value cell; multi-scalar grapheme clusters resolve via an overflow flag.
struct TerminalCell: Equatable, Hashable, Sendable {
    fileprivate static let graphemeTag: UInt32 = 0x8000_0000

    fileprivate var rawScalar: UInt32
    fileprivate var rawForeground: UInt32
    fileprivate var rawBackground: UInt32
    var style: TerminalCellStyle
    var width: UInt8
    private var reserved: UInt16 = 0

    init(
        scalar: UnicodeScalar,
        foreground: TerminalColorSpec,
        background: TerminalColorSpec,
        style: TerminalCellStyle,
        width: UInt8
    ) {
        self.rawScalar = scalar.value
        self.rawForeground = foreground.packed
        self.rawBackground = background.packed
        self.style = style
        self.width = width
    }

    fileprivate init(
        graphemeClusterWithForeground foreground: TerminalColorSpec,
        background: TerminalColorSpec,
        style: TerminalCellStyle,
        width: UInt8
    ) {
        self.rawScalar = Self.graphemeTag
        self.rawForeground = foreground.packed
        self.rawBackground = background.packed
        self.style = style
        self.width = width
    }

    var foreground: TerminalColorSpec {
        get { TerminalColorSpec(packed: rawForeground) }
        set { rawForeground = newValue.packed }
    }

    var background: TerminalColorSpec {
        get { TerminalColorSpec(packed: rawBackground) }
        set { rawBackground = newValue.packed }
    }

    var hasGraphemeCluster: Bool {
        (rawScalar & Self.graphemeTag) != 0
    }

    var isSpace: Bool {
        rawScalar == 0x20
    }

    var asciiByte: UInt8? {
        rawScalar < 0x80 ? UInt8(truncatingIfNeeded: rawScalar) : nil
    }

    var scalar: UnicodeScalar {
        guard !hasGraphemeCluster, let decoded = UnicodeScalar(rawScalar) else {
            return "\u{FFFD}"
        }
        return decoded
    }

    var character: Character {
        Character(scalar)
    }

    static let blank = TerminalCell(
        scalar: " ",
        foreground: .defaultForeground,
        background: .defaultBackground,
        style: [],
        width: 1)

    static func blank(background: TerminalColorSpec) -> TerminalCell {
        TerminalCell(
            scalar: " ",
            foreground: .defaultForeground,
            background: background,
            style: [],
            width: 1)
    }
}

struct TerminalGridLine: Equatable, Sendable {
    var cells: [TerminalCell]
    var graphemes: [Int: Character]?
    var isWrapped: Bool

    init(
        cols: Int,
        background: TerminalColorSpec = .defaultBackground,
        isWrapped: Bool = false
    ) {
        self.cells = Array(repeating: .blank(background: background), count: max(cols, 1))
        self.graphemes = nil
        self.isWrapped = isWrapped
    }

    init(
        cells: [TerminalCell],
        graphemes: [Int: Character]? = nil,
        isWrapped: Bool = false
    ) {
        self.cells = cells
        self.graphemes = graphemes
        self.isWrapped = isWrapped
    }

    func character(at col: Int) -> Character {
        let cell = cells[col]
        if cell.hasGraphemeCluster, let cluster = graphemes?[col] {
            return cluster
        }
        return cell.character
    }

    mutating func setScalar(
        _ scalar: UnicodeScalar,
        at col: Int,
        foreground: TerminalColorSpec,
        background: TerminalColorSpec,
        style: TerminalCellStyle,
        width: UInt8
    ) {
        if cells[col].hasGraphemeCluster {
            graphemes?.removeValue(forKey: col)
            if graphemes?.isEmpty == true { graphemes = nil }
        }
        cells[col] = TerminalCell(
            scalar: scalar,
            foreground: foreground,
            background: background,
            style: style,
            width: width)
    }

    mutating func setCharacter(_ character: Character, at col: Int) {
        let existing = cells[col]
        var scalars = character.unicodeScalars.makeIterator()
        if let first = scalars.next(), scalars.next() == nil {
            if existing.hasGraphemeCluster {
                graphemes?.removeValue(forKey: col)
                if graphemes?.isEmpty == true { graphemes = nil }
            }
            cells[col] = TerminalCell(
                scalar: first,
                foreground: existing.foreground,
                background: existing.background,
                style: existing.style,
                width: existing.width)
            return
        }
        if graphemes == nil { graphemes = [:] }
        graphemes?[col] = character
        cells[col] = TerminalCell(
            graphemeClusterWithForeground: existing.foreground,
            background: existing.background,
            style: existing.style,
            width: existing.width)
    }

    mutating func clearCell(at col: Int, background: TerminalColorSpec = .defaultBackground) {
        if cells[col].hasGraphemeCluster {
            graphemes?.removeValue(forKey: col)
            if graphemes?.isEmpty == true { graphemes = nil }
        }
        cells[col] = .blank(background: background)
    }
}

/// Stores scrollback in 128 KB+ VM slabs so macOS unmaps freed physical pages on close.
struct TerminalScrollbackBuffer: Sendable {
    static let targetChunkBytes = 131_072
    static let minimumLinesPerChunk = 64

    private final class CellSlab: @unchecked Sendable {
        let capacityCells: Int
        let byteSize: Int
        let pointer: UnsafeMutablePointer<TerminalCell>
        private(set) var count = 0

        init(capacityCells: Int) {
            let safeCapacity = max(capacityCells, 1)
            let rawBytes = safeCapacity * MemoryLayout<TerminalCell>.stride
            let pageSize = max(Int(getpagesize()), 16_384)
            let alignedBytes = ((rawBytes + pageSize - 1) / pageSize) * pageSize
            var address: vm_address_t = 0
            let kr = vm_allocate(mach_task_self_, &address, vm_size_t(alignedBytes), VM_FLAGS_ANYWHERE)
            precondition(kr == KERN_SUCCESS, "vm_allocate failed for scrollback slab")
            self.capacityCells = alignedBytes / MemoryLayout<TerminalCell>.stride
            self.byteSize = alignedBytes
            self.pointer = UnsafeMutablePointer<TerminalCell>(bitPattern: UInt(address))!
        }

        private init(copying other: CellSlab) {
            var address: vm_address_t = 0
            let kr = vm_allocate(
                mach_task_self_, &address, vm_size_t(other.byteSize), VM_FLAGS_ANYWHERE)
            precondition(kr == KERN_SUCCESS, "vm_allocate failed for scrollback slab clone")
            self.capacityCells = other.capacityCells
            self.byteSize = other.byteSize
            self.pointer = UnsafeMutablePointer<TerminalCell>(bitPattern: UInt(address))!
            if other.count > 0 {
                self.pointer.initialize(from: other.pointer, count: other.count)
                self.count = other.count
            }
        }

        deinit {
            if count > 0 {
                pointer.deinitialize(count: count)
            }
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: pointer)),
                vm_size_t(byteSize))
        }

        func clone() -> CellSlab {
            CellSlab(copying: self)
        }

        func appendSlice(_ cells: [TerminalCell], cols: Int) {
            let copyCount = min(cells.count, cols)
            if copyCount > 0 {
                cells.withUnsafeBufferPointer { src in
                    if let base = src.baseAddress {
                        (pointer + count).initialize(from: base, count: copyCount)
                    }
                }
            }
            if copyCount < cols {
                (pointer + count + copyCount).initialize(
                    repeating: .blank, count: cols - copyCount)
            }
            count += cols
        }

        func removeLast(_ n: Int) {
            let clamped = min(max(0, n), count)
            guard clamped > 0 else { return }
            count -= clamped
            (pointer + count).deinitialize(count: clamped)
        }

        func buffer(start: Int, count sliceCount: Int) -> UnsafeBufferPointer<TerminalCell> {
            UnsafeBufferPointer(start: pointer + start, count: sliceCount)
        }
    }

    private struct Chunk: Sendable {
        let cols: Int
        let capacityLines: Int
        private var slab: CellSlab
        var wrappedFlags: [Bool]
        var graphemes: [Int: [Int: Character]] = [:]
        var headLine = 0
        var lineCount = 0

        init(cols: Int) {
            let safeCols = max(cols, 1)
            let targetCells = max(
                Self.minimumCells(forCols: safeCols),
                TerminalScrollbackBuffer.targetChunkBytes / MemoryLayout<TerminalCell>.stride)
            let requestedLines = max(
                TerminalScrollbackBuffer.minimumLinesPerChunk, targetCells / safeCols)
            let allocatedSlab = CellSlab(capacityCells: requestedLines * safeCols)
            self.cols = safeCols
            self.capacityLines = allocatedSlab.capacityCells / safeCols
            self.slab = allocatedSlab
            self.wrappedFlags = []
            self.wrappedFlags.reserveCapacity(self.capacityLines)
        }

        private static func minimumCells(forCols cols: Int) -> Int {
            TerminalScrollbackBuffer.minimumLinesPerChunk * cols
        }

        var canAppend: Bool {
            headLine + lineCount < capacityLines
        }

        private mutating func ensureUniqueSlab() {
            if !isKnownUniquelyReferenced(&slab) {
                slab = slab.clone()
            }
        }

        mutating func append(_ line: TerminalGridLine) {
            ensureUniqueSlab()
            let physicalRow = headLine + lineCount
            slab.appendSlice(line.cells, cols: cols)
            wrappedFlags.append(line.isWrapped)
            if let clusters = line.graphemes, !clusters.isEmpty {
                let filtered = clusters.filter { $0.key < cols }
                if !filtered.isEmpty {
                    graphemes[physicalRow] = filtered
                }
            }
            lineCount += 1
        }

        func line(at offset: Int) -> TerminalGridLine {
            let physicalRow = headLine + offset
            let start = physicalRow * cols
            let slice = Array(slab.buffer(start: start, count: cols))
            return TerminalGridLine(
                cells: slice,
                graphemes: graphemes[physicalRow],
                isWrapped: wrappedFlags[physicalRow])
        }

        func withLine<R>(
            at offset: Int,
            _ body: (UnsafeBufferPointer<TerminalCell>, [Int: Character]?, Bool) -> R
        ) -> R {
            let physicalRow = headLine + offset
            let start = physicalRow * cols
            return body(
                slab.buffer(start: start, count: cols),
                graphemes[physicalRow],
                wrappedFlags[physicalRow])
        }

        mutating func dropFirst(_ n: Int) {
            for row in headLine..<(headLine + n) {
                graphemes.removeValue(forKey: row)
            }
            headLine += n
            lineCount -= n
        }

        mutating func popLast() -> TerminalGridLine? {
            guard lineCount > 0 else { return nil }
            ensureUniqueSlab()
            let result = line(at: lineCount - 1)
            let physicalRow = headLine + lineCount - 1
            slab.removeLast(cols)
            wrappedFlags.removeLast()
            graphemes.removeValue(forKey: physicalRow)
            lineCount -= 1
            return result
        }
    }

    private var chunks: [Chunk] = []
    private(set) var count = 0

    var isEmpty: Bool { count == 0 }

    mutating func append(_ line: TerminalGridLine) {
        let lineCols = max(line.cells.count, 1)
        if let lastIdx = chunks.indices.last,
            chunks[lastIdx].cols == lineCols,
            chunks[lastIdx].canAppend
        {
            chunks[lastIdx].append(line)
        } else {
            var chunk = Chunk(cols: lineCols)
            chunk.append(line)
            chunks.append(chunk)
        }
        count += 1
    }

    mutating func append<S: Sequence>(contentsOf lines: S) where S.Element == TerminalGridLine {
        for line in lines {
            append(line)
        }
    }

    subscript(index: Int) -> TerminalGridLine {
        var remaining = index
        for chunk in chunks {
            if remaining < chunk.lineCount {
                return chunk.line(at: remaining)
            }
            remaining -= chunk.lineCount
        }
        preconditionFailure("Scrollback index out of bounds")
    }

    func withLine<R>(
        at index: Int,
        _ body: (UnsafeBufferPointer<TerminalCell>, [Int: Character]?, Bool) -> R
    ) -> R? {
        guard index >= 0, index < count else { return nil }
        var remaining = index
        for chunk in chunks {
            if remaining < chunk.lineCount {
                return chunk.withLine(at: remaining, body)
            }
            remaining -= chunk.lineCount
        }
        return nil
    }

    mutating func removeFirst(_ k: Int) {
        var toDrop = min(max(0, k), count)
        guard toDrop > 0 else { return }
        count -= toDrop
        while toDrop > 0, !chunks.isEmpty {
            if toDrop >= chunks[0].lineCount {
                toDrop -= chunks[0].lineCount
                chunks.removeFirst()
            } else {
                chunks[0].dropFirst(toDrop)
                toDrop = 0
            }
        }
    }

    mutating func popLast(_ k: Int) -> [TerminalGridLine] {
        let toPop = min(max(0, k), count)
        guard toPop > 0 else { return [] }
        var popped: [TerminalGridLine] = []
        popped.reserveCapacity(toPop)
        for _ in 0..<toPop {
            while let lastIdx = chunks.indices.last {
                if let line = chunks[lastIdx].popLast() {
                    popped.append(line)
                    count -= 1
                    if chunks[lastIdx].lineCount == 0 {
                        chunks.removeLast()
                    }
                    break
                } else {
                    chunks.removeLast()
                }
            }
        }
        popped.reverse()
        return popped
    }

    mutating func removeAll() {
        chunks.removeAll(keepingCapacity: false)
        count = 0
    }
}

struct TerminalGridPoint: Equatable, Comparable, Sendable {
    var line: Int
    var col: Int

    static func < (lhs: TerminalGridPoint, rhs: TerminalGridPoint) -> Bool {
        if lhs.line != rhs.line { return lhs.line < rhs.line }
        return lhs.col < rhs.col
    }
}

enum TerminalShellEvent: Equatable, Sendable {
    case commandStarted(String)
    case commandFinished(Int32)
    case backgroundJobCountChanged(Int)
    case directoryChanged(String)
    case titleChanged(String)
    case promptInputCaptured(String)
}

final class TerminalEmulator {
    static let defaultCols = 80
    static let defaultRows = 24
    static let maxScrollbackLines = 4_000

    private enum ParseState: Equatable {
        case ground
        case escape
        case escapeIntermediate(UInt8)
        case csi
        case osc
        case stringIgnore
        case stringIgnoreEsc
        case oscEsc
    }

    private struct CursorSnapshot {
        var row: Int = 0
        var col: Int = 0
        var pendingWrap: Bool = false
        var foreground: TerminalColorSpec = .defaultForeground
        var background: TerminalColorSpec = .defaultBackground
        var style: TerminalCellStyle = []
        var g0LineDrawing: Bool = false
        var g1LineDrawing: Bool = false
        var useG1: Bool = false
    }

    private(set) var cols: Int
    private(set) var rows: Int
    private(set) var scrollback = TerminalScrollbackBuffer()
    private(set) var grid: [TerminalGridLine]

    private(set) var cursorRow: Int = 0
    private(set) var cursorCol: Int = 0
    private(set) var pendingWrap = false

    private(set) var cursorVisible = true
    private(set) var applicationCursorKeys = false
    private(set) var autoWrap = true
    private(set) var bracketedPaste = false
    private(set) var isAlternateScreen = false
    private(set) var mouseTrackingMode = 0
    private(set) var sgrMouseMode = false

    private(set) var windowTitle: String?
    private(set) var reportedDirectory: String?

    private var foreground: TerminalColorSpec = .defaultForeground
    private var background: TerminalColorSpec = .defaultBackground
    private var style: TerminalCellStyle = []
    private var scrollTop: Int = 0
    private var scrollBottom: Int
    private var g0LineDrawing = false
    private var g1LineDrawing = false
    private var useG1 = false
    private var lastGraphicScalar: UnicodeScalar?
    private var awaitingZWJContinuation = false

    private var savedPrimaryCursor = CursorSnapshot()
    private var savedAltCursor = CursorSnapshot()
    private var savedPrimaryGrid: [TerminalGridLine]?
    private var savedPrimaryState = CursorSnapshot()

    private var parseState: ParseState = .ground
    private var csiPrefix: UInt8 = 0
    private var csiIntermediate: UInt8 = 0
    private var csiBuffer: [UInt8] = []
    private var oscBuffer: [UInt8] = []
    private var utf8Pending: [UInt8] = []
    private var utf8ExpectedCount = 0

    private var pendingResponses: [[UInt8]] = []
    private var pendingShellEvents: [TerminalShellEvent] = []
    private var promptInputStart: TerminalGridPoint?
    private var activeOutputStartLine: Int?
    private(set) var lastCompletedOutput: String?

    init(cols: Int = TerminalEmulator.defaultCols, rows: Int = TerminalEmulator.defaultRows) {
        let clampedCols = min(max(cols, 10), 400)
        let clampedRows = min(max(rows, 2), 200)
        self.cols = clampedCols
        self.rows = clampedRows
        self.scrollBottom = clampedRows - 1
        self.grid = (0..<clampedRows).map { _ in TerminalGridLine(cols: clampedCols) }
    }

    var totalLines: Int { scrollback.count + rows }

    func line(at globalIndex: Int) -> TerminalGridLine? {
        guard globalIndex >= 0, globalIndex < totalLines else { return nil }
        if globalIndex < scrollback.count {
            return scrollback[globalIndex]
        }
        return grid[globalIndex - scrollback.count]
    }

    func withLine<R>(
        at globalIndex: Int,
        _ body: (UnsafeBufferPointer<TerminalCell>, [Int: Character]?, Bool) -> R
    ) -> R? {
        guard globalIndex >= 0, globalIndex < totalLines else { return nil }
        if globalIndex < scrollback.count {
            return scrollback.withLine(at: globalIndex, body)
        }
        let row = grid[globalIndex - scrollback.count]
        return row.cells.withUnsafeBufferPointer { buf in
            body(buf, row.graphemes, row.isWrapped)
        }
    }

    func takePendingResponses() -> [[UInt8]] {
        guard !pendingResponses.isEmpty else { return [] }
        let items = pendingResponses
        pendingResponses.removeAll(keepingCapacity: true)
        return items
    }

    func takeShellEvents() -> [TerminalShellEvent] {
        guard !pendingShellEvents.isEmpty else { return [] }
        let items = pendingShellEvents
        pendingShellEvents.removeAll(keepingCapacity: true)
        return items
    }

    func clearScrollback() {
        let dropped = scrollback.count
        scrollback.removeAll()
        adjustTrackedPositions(droppedScrollbackLines: dropped)
        activeOutputStartLine = nil
        lastCompletedOutput = nil
    }

    func resize(cols newCols: Int, rows newRows: Int) {
        let targetCols = min(max(newCols, 10), 400)
        let targetRows = min(max(newRows, 2), 200)
        guard targetCols != cols || targetRows != rows else { return }

        if isAlternateScreen {
            if var saved = savedPrimaryGrid {
                saved = Self.resizedGrid(
                    saved, oldRows: rows, newCols: targetCols, newRows: targetRows,
                    cursorRow: &savedPrimaryState.row, intoScrollback: &scrollback)
                savedPrimaryGrid = saved
                savedPrimaryState.col = min(savedPrimaryState.col, targetCols - 1)
                savedPrimaryState.pendingWrap = false
            }
            var altScrollback = TerminalScrollbackBuffer()
            grid = Self.resizedGrid(
                grid, oldRows: rows, newCols: targetCols, newRows: targetRows,
                cursorRow: &cursorRow, intoScrollback: &altScrollback)
        } else {
            grid = Self.resizedGrid(
                grid, oldRows: rows, newCols: targetCols, newRows: targetRows,
                cursorRow: &cursorRow, intoScrollback: &scrollback)
            trimScrollbackIfNeeded()
        }

        cols = targetCols
        rows = targetRows
        scrollTop = 0
        scrollBottom = targetRows - 1
        cursorRow = min(max(cursorRow, 0), targetRows - 1)
        cursorCol = min(max(cursorCol, 0), targetCols - 1)
        pendingWrap = false
    }

    private static func resizedGrid(
        _ current: [TerminalGridLine],
        oldRows: Int,
        newCols: Int,
        newRows: Int,
        cursorRow: inout Int,
        intoScrollback scrollback: inout TerminalScrollbackBuffer
    ) -> [TerminalGridLine] {
        var adjusted: [TerminalGridLine] = current.map { line in
            Self.resizedLine(line, newCols: newCols)
        }

        if newRows < oldRows {
            let excess = oldRows - newRows
            var trimBottom = 0
            while trimBottom < excess,
                let last = adjusted.last,
                Self.isBlankLine(last),
                adjusted.count - 1 > cursorRow
            {
                adjusted.removeLast()
                trimBottom += 1
            }
            let pushTop = excess - trimBottom
            if pushTop > 0 {
                scrollback.append(contentsOf: adjusted.prefix(pushTop))
                adjusted.removeFirst(pushTop)
                cursorRow = max(0, cursorRow - pushTop)
            }
        } else if newRows > oldRows {
            let needed = newRows - oldRows
            let pulled = scrollback.popLast(needed).map { line in
                Self.resizedLine(line, newCols: newCols)
            }
            if !pulled.isEmpty {
                adjusted.insert(contentsOf: pulled, at: 0)
                cursorRow += pulled.count
            }
            while adjusted.count < newRows {
                adjusted.append(TerminalGridLine(cols: newCols))
            }
        }
        return adjusted
    }

    private static func resizedLine(_ line: TerminalGridLine, newCols: Int) -> TerminalGridLine {
        var copy = line
        if copy.cells.count < newCols {
            copy.cells.append(
                contentsOf: Array(repeating: .blank, count: newCols - copy.cells.count))
        } else if copy.cells.count > newCols {
            copy.cells.removeLast(copy.cells.count - newCols)
            if var clusters = copy.graphemes {
                clusters = clusters.filter { $0.key < newCols }
                copy.graphemes = clusters.isEmpty ? nil : clusters
            }
        }
        return copy
    }

    private static func isBlankLine(_ line: TerminalGridLine) -> Bool {
        !line.isWrapped
            && line.graphemes == nil
            && line.cells.allSatisfy {
                $0.isSpace && $0.background == .defaultBackground && $0.style.isEmpty
            }
    }

    func feed(_ text: String) {
        feed(Array(text.utf8))
    }

    func feed(_ bytes: [UInt8]) {
        bytes.withUnsafeBufferPointer { feed($0) }
    }

    func feed(_ bytes: UnsafeBufferPointer<UInt8>) {
        for byte in bytes {
            if utf8ExpectedCount > 0 {
                if (byte & 0b1100_0000) == 0b1000_0000 {
                    utf8Pending.append(byte)
                    if utf8Pending.count == utf8ExpectedCount {
                        let decoded = String(bytes: utf8Pending, encoding: .utf8) ?? "\u{FFFD}"
                        utf8Pending.removeAll(keepingCapacity: true)
                        utf8ExpectedCount = 0
                        for scalar in decoded.unicodeScalars {
                            processScalar(scalar)
                        }
                    }
                    continue
                } else {
                    utf8Pending.removeAll(keepingCapacity: true)
                    utf8ExpectedCount = 0
                }
            }

            switch parseState {
            case .osc:
                handleOSCByte(byte)
                continue
            case .oscEsc:
                if byte == 0x5C {
                    finishOSC()
                } else {
                    parseState = .ground
                    processGroundOrEscapeByte(byte, startedWithEscape: true)
                }
                continue
            case .stringIgnore:
                if byte == 0x07 {
                    parseState = .ground
                } else if byte == 0x1B {
                    parseState = .stringIgnoreEsc
                }
                continue
            case .stringIgnoreEsc:
                parseState = (byte == 0x5C) ? .ground : .stringIgnore
                continue
            default:
                break
            }

            if byte >= 0x80, parseState == .ground {
                if (byte & 0b1110_0000) == 0b1100_0000 {
                    utf8Pending = [byte]
                    utf8ExpectedCount = 2
                    continue
                } else if (byte & 0b1111_0000) == 0b1110_0000 {
                    utf8Pending = [byte]
                    utf8ExpectedCount = 3
                    continue
                } else if (byte & 0b1111_1000) == 0b1111_0000 {
                    utf8Pending = [byte]
                    utf8ExpectedCount = 4
                    continue
                }
            }

            processGroundOrEscapeByte(byte, startedWithEscape: false)
        }
    }

    private func processGroundOrEscapeByte(_ byte: UInt8, startedWithEscape: Bool) {
        if startedWithEscape {
            parseState = .escape
        }

        if byte == 0x1B {
            awaitingZWJContinuation = false
            parseState = .escape
            csiPrefix = 0
            csiIntermediate = 0
            csiBuffer.removeAll(keepingCapacity: true)
            return
        }

        if byte < 0x20 || byte == 0x7F {
            awaitingZWJContinuation = false
            handleControlByte(byte)
            return
        }

        switch parseState {
        case .ground:
            processScalar(UnicodeScalar(byte))
        case .escape:
            handleEscapeByte(byte)
        case .escapeIntermediate(let intermediate):
            handleEscapeIntermediate(intermediate: intermediate, finalByte: byte)
        case .csi:
            handleCSIByte(byte)
        case .osc, .oscEsc, .stringIgnore, .stringIgnoreEsc:
            break
        }
    }

    private func handleControlByte(_ byte: UInt8) {
        switch byte {
        case 0x07:
            break
        case 0x08:
            pendingWrap = false
            if cursorCol > 0 { cursorCol -= 1 }
        case 0x09:
            pendingWrap = false
            let nextStop = ((cursorCol / 8) + 1) * 8
            cursorCol = min(nextStop, cols - 1)
        case 0x0A, 0x0B, 0x0C:
            pendingWrap = false
            lineFeed()
        case 0x0D:
            pendingWrap = false
            cursorCol = 0
        case 0x0E:
            useG1 = true
        case 0x0F:
            useG1 = false
        default:
            break
        }
    }

    private func handleEscapeByte(_ byte: UInt8) {
        switch byte {
        case 0x5B:
            parseState = .csi
            csiPrefix = 0
            csiIntermediate = 0
            csiBuffer.removeAll(keepingCapacity: true)
        case 0x5D:
            parseState = .osc
            oscBuffer.removeAll(keepingCapacity: true)
        case 0x50, 0x58, 0x5E, 0x5F:
            parseState = .stringIgnore
        case 0x28, 0x29, 0x2A, 0x2B, 0x23:
            parseState = .escapeIntermediate(byte)
        case 0x37:
            saveCursor()
            parseState = .ground
        case 0x38:
            restoreCursor()
            parseState = .ground
        case 0x44:
            pendingWrap = false
            lineFeed()
            parseState = .ground
        case 0x45:
            pendingWrap = false
            cursorCol = 0
            lineFeed()
            parseState = .ground
        case 0x4D:
            pendingWrap = false
            reverseIndex()
            parseState = .ground
        case 0x63:
            fullReset()
            parseState = .ground
        default:
            parseState = .ground
        }
    }

    private func handleEscapeIntermediate(intermediate: UInt8, finalByte: UInt8) {
        if intermediate == 0x28 {
            g0LineDrawing = (finalByte == 0x30)
        } else if intermediate == 0x29 {
            g1LineDrawing = (finalByte == 0x30)
        }
        parseState = .ground
    }

    private func handleOSCByte(_ byte: UInt8) {
        if byte == 0x07 {
            finishOSC()
            return
        }
        if byte == 0x1B {
            parseState = .oscEsc
            return
        }
        if oscBuffer.count < 8_192 {
            oscBuffer.append(byte)
        }
    }

    private func finishOSC() {
        parseState = .ground
        guard !oscBuffer.isEmpty else { return }
        let text = String(bytes: oscBuffer, encoding: .utf8) ?? ""
        oscBuffer.removeAll(keepingCapacity: true)

        guard let semi = text.firstIndex(of: ";") else { return }
        let code = text[..<semi]
        let payload = String(text[text.index(after: semi)...])

        switch code {
        case "0", "2":
            windowTitle = payload
            pendingShellEvents.append(.titleChanged(payload))
        case "7":
            if let path = Self.parseOSC7Directory(payload) {
                reportedDirectory = path
                pendingShellEvents.append(.directoryChanged(path))
            }
        case "133":
            handleOSC133(payload)
        default:
            break
        }
    }

    private func handleOSC133(_ payload: String) {
        if payload == "B" {
            if !isAlternateScreen {
                promptInputStart = TerminalGridPoint(line: scrollback.count + cursorRow, col: cursorCol)
            }
        } else if payload == "C" {
            promptInputStart = nil
            if !isAlternateScreen {
                activeOutputStartLine = scrollback.count + cursorRow
            }
            pendingShellEvents.append(.commandStarted(""))
        } else if payload.hasPrefix("C;") {
            promptInputStart = nil
            if !isAlternateScreen {
                activeOutputStartLine = scrollback.count + cursorRow
            }
            let cmd = String(payload.dropFirst(2))
            pendingShellEvents.append(.commandStarted(cmd))
        } else if payload == "D" {
            captureCompletedOutputIfNeeded()
            pendingShellEvents.append(.commandFinished(0))
        } else if payload.hasPrefix("D;") {
            captureCompletedOutputIfNeeded()
            let rest = payload.dropFirst(2)
            let parts = rest.split(separator: ";", maxSplits: 2, omittingEmptySubsequences: false)
            let exitStatus = Int32(parts.first ?? "0") ?? 0
            pendingShellEvents.append(.commandFinished(exitStatus))
            if parts.count >= 2, let bgJobs = Int(parts[1]) {
                pendingShellEvents.append(.backgroundJobCountChanged(max(0, bgJobs)))
            }
        } else if payload == "I" {
            pendingShellEvents.append(.promptInputCaptured(""))
        } else if payload.hasPrefix("I;") {
            pendingShellEvents.append(.promptInputCaptured(String(payload.dropFirst(2))))
        }
    }

    private func captureCompletedOutputIfNeeded() {
        guard let startLine = activeOutputStartLine else { return }
        activeOutputStartLine = nil
        guard !isAlternateScreen else { return }
        let cursorGlobalLine = scrollback.count + cursorRow
        let cursorOnFreshBlankLine =
            cursorCol == 0 && !pendingWrap && Self.isBlankLine(grid[cursorRow])
        let endLine = cursorOnFreshBlankLine ? cursorGlobalLine - 1 : cursorGlobalLine
        guard endLine >= startLine else { return }
        let extracted = extractOutputLines(
            from: startLine, through: endLine, trimPromptEolMark: true)
        if !extracted.isEmpty {
            lastCompletedOutput = extracted
        }
    }

    static func parseOSC7Directory(_ payload: String) -> String? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("file://") {
            let withoutScheme = trimmed.dropFirst("file://".count)
            guard let slash = withoutScheme.firstIndex(of: "/") else { return nil }
            let rawPath = String(withoutScheme[slash...])
            return rawPath.removingPercentEncoding ?? rawPath
        }
        if trimmed.hasPrefix("/") {
            return trimmed
        }
        return nil
    }

    private func handleCSIByte(_ byte: UInt8) {
        if csiBuffer.isEmpty && csiPrefix == 0 && (byte >= 0x3C && byte <= 0x3F) {
            csiPrefix = byte
            return
        }
        if (byte >= 0x30 && byte <= 0x39) || byte == 0x3B || byte == 0x3A {
            if csiBuffer.count < 256 {
                csiBuffer.append(byte)
            }
            return
        }
        if byte >= 0x20 && byte <= 0x2F {
            csiIntermediate = byte
            return
        }
        if byte >= 0x40 && byte <= 0x7E {
            dispatchCSI(finalByte: byte)
            parseState = .ground
            return
        }
        parseState = .ground
    }

    private func parseCSIParams() -> [Int] {
        guard !csiBuffer.isEmpty else { return [] }
        var params: [Int] = []
        var current = 0
        var hasDigit = false
        var inColonSubparam = false
        for byte in csiBuffer {
            if byte == 0x3B {
                params.append(hasDigit ? current : 0)
                current = 0
                hasDigit = false
                inColonSubparam = false
            } else if byte == 0x3A {
                inColonSubparam = true
            } else if !inColonSubparam, byte >= 0x30, byte <= 0x39 {
                current = min(current * 10 + Int(byte - 0x30), 65_535)
                hasDigit = true
            }
        }
        params.append(hasDigit ? current : 0)
        return params
    }

    private func dispatchCSI(finalByte: UInt8) {
        if csiPrefix == 0x3F {
            let params = parseCSIParams()
            if finalByte == 0x68 {
                setDECPrivateModes(params, enabled: true)
            } else if finalByte == 0x6C {
                setDECPrivateModes(params, enabled: false)
            }
            return
        }

        if csiPrefix == 0x3E {
            if finalByte == 0x63 {
                pendingResponses.append(Array("\u{1B}[>0;10;1c".utf8))
            }
            return
        }

        guard csiPrefix == 0, csiIntermediate == 0 else { return }
        let params = parseCSIParams()
        let p0 = params.first ?? 0

        switch finalByte {
        case 0x41:
            pendingWrap = false
            let delta = max(p0, 1)
            let floor = cursorRow >= scrollTop ? scrollTop : 0
            cursorRow = max(floor, cursorRow - delta)
        case 0x42:
            pendingWrap = false
            let delta = max(p0, 1)
            let ceiling = cursorRow <= scrollBottom ? scrollBottom : rows - 1
            cursorRow = min(ceiling, cursorRow + delta)
        case 0x43:
            pendingWrap = false
            cursorCol = min(cols - 1, cursorCol + max(p0, 1))
        case 0x44:
            pendingWrap = false
            cursorCol = max(0, cursorCol - max(p0, 1))
        case 0x45:
            pendingWrap = false
            cursorCol = 0
            cursorRow = min(rows - 1, cursorRow + max(p0, 1))
        case 0x46:
            pendingWrap = false
            cursorCol = 0
            cursorRow = max(0, cursorRow - max(p0, 1))
        case 0x47, 0x60:
            pendingWrap = false
            cursorCol = min(max(max(p0, 1) - 1, 0), cols - 1)
        case 0x48, 0x66:
            pendingWrap = false
            let r = params.count >= 1 ? max(params[0], 1) - 1 : 0
            let c = params.count >= 2 ? max(params[1], 1) - 1 : 0
            cursorRow = min(max(r, 0), rows - 1)
            cursorCol = min(max(c, 0), cols - 1)
        case 0x64:
            pendingWrap = false
            cursorRow = min(max(max(p0, 1) - 1, 0), rows - 1)
        case 0x4A:
            eraseInDisplay(mode: p0)
        case 0x4B:
            eraseInLine(mode: p0)
        case 0x4C:
            insertLines(count: max(p0, 1))
        case 0x4D:
            deleteLines(count: max(p0, 1))
        case 0x50:
            deleteCharacters(count: max(p0, 1))
        case 0x40:
            insertBlankCharacters(count: max(p0, 1))
        case 0x58:
            eraseCharacters(count: max(p0, 1))
        case 0x53:
            scrollRegionUp(lines: max(p0, 1), intoScrollback: false)
        case 0x54:
            scrollRegionDown(lines: max(p0, 1))
        case 0x62:
            if let scalar = lastGraphicScalar {
                let count = min(max(p0, 1), cols * rows)
                let width = Self.displayWidth(of: scalar)
                for _ in 0..<count {
                    putScalar(scalar, width: width)
                }
            }
        case 0x63:
            pendingResponses.append(Array("\u{1B}[?62;22c".utf8))
        case 0x6D:
            applySGR()
        case 0x6E:
            if p0 == 5 {
                pendingResponses.append(Array("\u{1B}[0n".utf8))
            } else if p0 == 6 {
                pendingResponses.append(Array("\u{1B}[\(cursorRow + 1);\(cursorCol + 1)R".utf8))
            }
        case 0x72:
            let top = params.count >= 1 && params[0] > 0 ? params[0] - 1 : 0
            let bottom = params.count >= 2 && params[1] > 0 ? params[1] - 1 : rows - 1
            if top < bottom, bottom < rows {
                scrollTop = top
                scrollBottom = bottom
            } else {
                scrollTop = 0
                scrollBottom = rows - 1
            }
            pendingWrap = false
            cursorRow = 0
            cursorCol = 0
        case 0x73:
            saveCursor()
        case 0x75:
            restoreCursor()
        default:
            break
        }
    }

    private func setDECPrivateModes(_ modes: [Int], enabled: Bool) {
        for mode in modes {
            switch mode {
            case 1:
                applicationCursorKeys = enabled
            case 7:
                autoWrap = enabled
            case 25:
                cursorVisible = enabled
            case 1000, 1002, 1003:
                mouseTrackingMode = enabled ? mode : 0
            case 1006:
                sgrMouseMode = enabled
            case 2004:
                if enabled, !bracketedPaste, !isAlternateScreen {
                    promptInputStart = TerminalGridPoint(
                        line: scrollback.count + cursorRow, col: cursorCol)
                } else if !enabled {
                    promptInputStart = nil
                }
                bracketedPaste = enabled
            case 47, 1047:
                if enabled {
                    enterAlternateScreen(saveCursorFirst: false)
                } else {
                    leaveAlternateScreen(restoreCursorAfter: false)
                }
            case 1048:
                if enabled { saveCursor() } else { restoreCursor() }
            case 1049:
                if enabled {
                    enterAlternateScreen(saveCursorFirst: true)
                } else {
                    leaveAlternateScreen(restoreCursorAfter: true)
                }
            default:
                break
            }
        }
    }

    private func enterAlternateScreen(saveCursorFirst: Bool) {
        guard !isAlternateScreen else { return }
        if saveCursorFirst {
            savedPrimaryState = currentCursorSnapshot()
        }
        savedPrimaryGrid = grid
        promptInputStart = nil
        isAlternateScreen = true
        grid = (0..<rows).map { _ in TerminalGridLine(cols: cols) }
        scrollTop = 0
        scrollBottom = rows - 1
        cursorRow = 0
        cursorCol = 0
        pendingWrap = false
    }

    private func leaveAlternateScreen(restoreCursorAfter: Bool) {
        guard isAlternateScreen else { return }
        isAlternateScreen = false
        if let saved = savedPrimaryGrid {
            grid = saved
            savedPrimaryGrid = nil
        } else {
            grid = (0..<rows).map { _ in TerminalGridLine(cols: cols) }
        }
        scrollTop = 0
        scrollBottom = rows - 1
        if restoreCursorAfter {
            applyCursorSnapshot(savedPrimaryState)
        } else {
            cursorRow = min(cursorRow, rows - 1)
            cursorCol = min(cursorCol, cols - 1)
            pendingWrap = false
        }
    }

    private func saveCursor() {
        let snap = currentCursorSnapshot()
        if isAlternateScreen { savedAltCursor = snap } else { savedPrimaryCursor = snap }
    }

    private func restoreCursor() {
        let snap = isAlternateScreen ? savedAltCursor : savedPrimaryCursor
        applyCursorSnapshot(snap)
    }

    private func currentCursorSnapshot() -> CursorSnapshot {
        CursorSnapshot(
            row: cursorRow,
            col: cursorCol,
            pendingWrap: pendingWrap,
            foreground: foreground,
            background: background,
            style: style,
            g0LineDrawing: g0LineDrawing,
            g1LineDrawing: g1LineDrawing,
            useG1: useG1)
    }

    private func applyCursorSnapshot(_ snap: CursorSnapshot) {
        cursorRow = min(max(snap.row, 0), rows - 1)
        cursorCol = min(max(snap.col, 0), cols - 1)
        pendingWrap = snap.pendingWrap
        foreground = snap.foreground
        background = snap.background
        style = snap.style
        g0LineDrawing = snap.g0LineDrawing
        g1LineDrawing = snap.g1LineDrawing
        useG1 = snap.useG1
    }

    private func fullReset() {
        isAlternateScreen = false
        savedPrimaryGrid = nil
        promptInputStart = nil
        activeOutputStartLine = nil
        lastCompletedOutput = nil
        grid = (0..<rows).map { _ in TerminalGridLine(cols: cols) }
        cursorRow = 0
        cursorCol = 0
        pendingWrap = false
        foreground = .defaultForeground
        background = .defaultBackground
        style = []
        scrollTop = 0
        scrollBottom = rows - 1
        cursorVisible = true
        applicationCursorKeys = false
        autoWrap = true
        bracketedPaste = false
        mouseTrackingMode = 0
        sgrMouseMode = false
        g0LineDrawing = false
        g1LineDrawing = false
        useG1 = false
    }

    private func eraseInDisplay(mode: Int) {
        pendingWrap = false
        switch mode {
        case 0:
            eraseInLine(mode: 0)
            if cursorRow + 1 < rows {
                for r in (cursorRow + 1)..<rows {
                    grid[r] = TerminalGridLine(cols: cols, background: background)
                }
            }
        case 1:
            if cursorRow > 0 {
                for r in 0..<cursorRow {
                    grid[r] = TerminalGridLine(cols: cols, background: background)
                }
            }
            for c in 0...min(cursorCol, cols - 1) {
                grid[cursorRow].clearCell(at: c, background: background)
            }
        case 2:
            if !isAlternateScreen {
                var lastNonBlank = -1
                for r in 0..<rows where !Self.isBlankLine(grid[r]) {
                    lastNonBlank = r
                }
                if lastNonBlank >= 0 {
                    scrollback.append(contentsOf: grid[0...lastNonBlank])
                    trimScrollbackIfNeeded()
                }
            }
            for r in 0..<rows {
                grid[r] = TerminalGridLine(cols: cols, background: background)
            }
        case 3:
            let dropped = scrollback.count
            scrollback.removeAll()
            adjustTrackedPositions(droppedScrollbackLines: dropped)
            activeOutputStartLine = nil
            lastCompletedOutput = nil
        default:
            break
        }
    }

    private func eraseInLine(mode: Int) {
        pendingWrap = false
        switch mode {
        case 0:
            clearWideCellOverlap(row: cursorRow, col: cursorCol)
            for c in cursorCol..<cols {
                grid[cursorRow].clearCell(at: c, background: background)
            }
            grid[cursorRow].isWrapped = false
        case 1:
            let end = min(cursorCol, cols - 1)
            clearWideCellOverlap(row: cursorRow, col: end)
            for c in 0...end {
                grid[cursorRow].clearCell(at: c, background: background)
            }
        case 2:
            grid[cursorRow] = TerminalGridLine(cols: cols, background: background)
        default:
            break
        }
    }

    private func insertLines(count: Int) {
        guard cursorRow >= scrollTop, cursorRow <= scrollBottom else { return }
        pendingWrap = false
        let n = min(count, scrollBottom - cursorRow + 1)
        for _ in 0..<n {
            grid.remove(at: scrollBottom)
            grid.insert(TerminalGridLine(cols: cols, background: background), at: cursorRow)
        }
    }

    private func deleteLines(count: Int) {
        guard cursorRow >= scrollTop, cursorRow <= scrollBottom else { return }
        pendingWrap = false
        let n = min(count, scrollBottom - cursorRow + 1)
        for _ in 0..<n {
            grid.remove(at: cursorRow)
            grid.insert(TerminalGridLine(cols: cols, background: background), at: scrollBottom)
        }
    }

    private func deleteCharacters(count: Int) {
        pendingWrap = false
        let n = min(count, cols - cursorCol)
        guard n > 0 else { return }
        clearWideCellOverlap(row: cursorRow, col: cursorCol)
        grid[cursorRow].cells.removeSubrange(cursorCol..<(cursorCol + n))
        grid[cursorRow].cells.append(
            contentsOf: Array(repeating: .blank(background: background), count: n))
        if let clusters = grid[cursorRow].graphemes {
            var shifted: [Int: Character] = [:]
            for (col, ch) in clusters {
                if col < cursorCol {
                    shifted[col] = ch
                } else if col >= cursorCol + n {
                    shifted[col - n] = ch
                }
            }
            grid[cursorRow].graphemes = shifted.isEmpty ? nil : shifted
        }
    }

    private func insertBlankCharacters(count: Int) {
        pendingWrap = false
        let n = min(count, cols - cursorCol)
        guard n > 0 else { return }
        clearWideCellOverlap(row: cursorRow, col: cursorCol)
        let blanks = Array(repeating: TerminalCell.blank(background: background), count: n)
        grid[cursorRow].cells.insert(contentsOf: blanks, at: cursorCol)
        grid[cursorRow].cells.removeLast(n)
        if let clusters = grid[cursorRow].graphemes {
            var shifted: [Int: Character] = [:]
            for (col, ch) in clusters {
                if col < cursorCol {
                    shifted[col] = ch
                } else if col + n < cols {
                    shifted[col + n] = ch
                }
            }
            grid[cursorRow].graphemes = shifted.isEmpty ? nil : shifted
        }
    }

    private func eraseCharacters(count: Int) {
        pendingWrap = false
        let end = min(cols, cursorCol + count)
        guard cursorCol < end else { return }
        clearWideCellOverlap(row: cursorRow, col: cursorCol)
        clearWideCellOverlap(row: cursorRow, col: end - 1)
        for c in cursorCol..<end {
            grid[cursorRow].clearCell(at: c, background: background)
        }
    }

    private func lineFeed() {
        if cursorRow == scrollBottom {
            let saveToScrollback = !isAlternateScreen && scrollTop == 0
            scrollRegionUp(lines: 1, intoScrollback: saveToScrollback)
        } else if cursorRow < rows - 1 {
            cursorRow += 1
        }
    }

    private func reverseIndex() {
        if cursorRow == scrollTop {
            scrollRegionDown(lines: 1)
        } else if cursorRow > 0 {
            cursorRow -= 1
        }
    }

    private func scrollRegionUp(lines: Int, intoScrollback: Bool) {
        let count = min(lines, scrollBottom - scrollTop + 1)
        guard count > 0 else { return }
        for _ in 0..<count {
            let removed = grid.remove(at: scrollTop)
            if intoScrollback {
                scrollback.append(removed)
            }
            grid.insert(TerminalGridLine(cols: cols, background: background), at: scrollBottom)
        }
        if intoScrollback {
            trimScrollbackIfNeeded()
        }
    }

    private func scrollRegionDown(lines: Int) {
        let count = min(lines, scrollBottom - scrollTop + 1)
        guard count > 0 else { return }
        for _ in 0..<count {
            grid.remove(at: scrollBottom)
            grid.insert(TerminalGridLine(cols: cols, background: background), at: scrollTop)
        }
    }

    private func trimScrollbackIfNeeded() {
        if scrollback.count > Self.maxScrollbackLines {
            let dropped = scrollback.count - Self.maxScrollbackLines
            scrollback.removeFirst(dropped)
            adjustTrackedPositions(droppedScrollbackLines: dropped)
        }
    }

    private func adjustTrackedPositions(droppedScrollbackLines dropped: Int) {
        guard dropped > 0 else { return }
        if var start = promptInputStart {
            start.line -= dropped
            promptInputStart = start.line >= 0 ? start : nil
        }
        if let outputStart = activeOutputStartLine {
            activeOutputStartLine = max(0, outputStart - dropped)
        }
    }

    private func processScalar(_ scalar: UnicodeScalar) {
        if Self.isCombiningMark(scalar) {
            appendCombiningScalar(scalar)
            return
        }
        if awaitingZWJContinuation {
            awaitingZWJContinuation = false
            appendCombiningScalar(scalar)
            return
        }
        let mapped: UnicodeScalar
        let lineDrawingActive = useG1 ? g1LineDrawing : g0LineDrawing
        if lineDrawingActive,
            scalar.value >= 0x60, scalar.value <= 0x7E,
            let box = Self.decLineDrawingMap[UInt8(scalar.value)]
        {
            mapped = box
        } else {
            mapped = scalar
        }
        let width = Self.displayWidth(of: mapped)
        guard width > 0 else { return }
        lastGraphicScalar = mapped
        putScalar(mapped, width: width)
    }

    private func appendCombiningScalar(_ scalar: UnicodeScalar) {
        var targetRow = cursorRow
        var targetCol = pendingWrap ? cursorCol : cursorCol - 1
        if targetCol < 0 {
            guard targetRow > 0, grid[targetRow - 1].isWrapped else { return }
            targetRow -= 1
            targetCol = cols - 1
        }
        if grid[targetRow].cells[targetCol].width == 0, targetCol > 0 {
            targetCol -= 1
        }
        var existing = String(grid[targetRow].character(at: targetCol))
        existing.unicodeScalars.append(scalar)
        if let combined = existing.first {
            grid[targetRow].setCharacter(combined, at: targetCol)
            awaitingZWJContinuation = (scalar.value == 0x200D)
        }
    }

    private func putScalar(_ scalar: UnicodeScalar, width: UInt8) {
        let cellWidth = width == 2 && cols >= 2 ? UInt8(2) : UInt8(1)
        if pendingWrap {
            if autoWrap {
                grid[cursorRow].isWrapped = true
                cursorCol = 0
                lineFeed()
            }
            pendingWrap = false
        }

        if cellWidth == 2, cursorCol == cols - 1 {
            grid[cursorRow].clearCell(at: cursorCol, background: background)
            if autoWrap {
                grid[cursorRow].isWrapped = true
                cursorCol = 0
                lineFeed()
            } else {
                cursorCol = cols - 2
            }
        }

        clearWideCellOverlap(row: cursorRow, col: cursorCol)
        if cellWidth == 2, cursorCol + 1 < cols {
            clearWideCellOverlap(row: cursorRow, col: cursorCol + 1)
        }

        grid[cursorRow].setScalar(
            scalar,
            at: cursorCol,
            foreground: foreground,
            background: background,
            style: style,
            width: cellWidth)

        if cellWidth == 2, cursorCol + 1 < cols {
            grid[cursorRow].setScalar(
                "\0",
                at: cursorCol + 1,
                foreground: foreground,
                background: background,
                style: style,
                width: 0)
            if cursorCol + 1 >= cols - 1 {
                cursorCol = cols - 1
                pendingWrap = autoWrap
            } else {
                cursorCol += 2
            }
        } else {
            if cursorCol >= cols - 1 {
                cursorCol = cols - 1
                pendingWrap = autoWrap
            } else {
                cursorCol += 1
            }
        }
    }

    private func clearWideCellOverlap(row: Int, col: Int) {
        guard row >= 0, row < rows, col >= 0, col < cols else { return }
        let cell = grid[row].cells[col]
        if cell.width == 2, col + 1 < cols {
            grid[row].clearCell(at: col + 1, background: background)
        } else if cell.width == 0, col > 0 {
            grid[row].clearCell(at: col - 1, background: background)
        }
    }

    private func applySGR() {
        if csiBuffer.isEmpty {
            resetAttributes()
            return
        }
        let raw = String(bytes: csiBuffer, encoding: .utf8) ?? ""
        let groups = raw.split(separator: ";", omittingEmptySubsequences: false)
        var idx = 0
        while idx < groups.count {
            let group = groups[idx]
            let subparts = group.split(separator: ":", omittingEmptySubsequences: false)
            let code = Int(subparts.first ?? "") ?? 0

            switch code {
            case 0:
                resetAttributes()
            case 1:
                style.insert(.bold)
                style.remove(.dim)
            case 2:
                style.insert(.dim)
                style.remove(.bold)
            case 3:
                style.insert(.italic)
            case 4:
                if subparts.count >= 2, (Int(subparts[1]) ?? 1) == 0 {
                    style.remove(.underline)
                } else {
                    style.insert(.underline)
                }
            case 7:
                style.insert(.inverse)
            case 8:
                style.insert(.invisible)
            case 9:
                style.insert(.strikethrough)
            case 21, 22:
                style.remove([.bold, .dim])
            case 23:
                style.remove(.italic)
            case 24:
                style.remove(.underline)
            case 27:
                style.remove(.inverse)
            case 28:
                style.remove(.invisible)
            case 29:
                style.remove(.strikethrough)
            case 30...37:
                foreground = .ansi(UInt8(code - 30))
            case 39:
                foreground = .defaultForeground
            case 40...47:
                background = .ansi(UInt8(code - 40))
            case 49:
                background = .defaultBackground
            case 90...97:
                foreground = .ansi(UInt8(code - 90 + 8))
            case 100...107:
                background = .ansi(UInt8(code - 100 + 8))
            case 38, 48:
                let isFg = (code == 38)
                if subparts.count >= 3 {
                    let mode = Int(subparts[1]) ?? 0
                    if mode == 5 {
                        let idx256 = UInt8(clamping: Int(subparts[2]) ?? 0)
                        if isFg { foreground = .ansi(idx256) } else { background = .ansi(idx256) }
                    } else if mode == 2 {
                        let offset = subparts.count >= 6 ? 3 : 2
                        if subparts.count >= offset + 3 {
                            let r = UInt8(clamping: Int(subparts[offset]) ?? 0)
                            let g = UInt8(clamping: Int(subparts[offset + 1]) ?? 0)
                            let b = UInt8(clamping: Int(subparts[offset + 2]) ?? 0)
                            if isFg {
                                foreground = .rgb(r, g, b)
                            } else {
                                background = .rgb(r, g, b)
                            }
                        }
                    }
                } else if idx + 1 < groups.count {
                    let mode = Int(groups[idx + 1]) ?? 0
                    if mode == 5, idx + 2 < groups.count {
                        let idx256 = UInt8(clamping: Int(groups[idx + 2]) ?? 0)
                        if isFg { foreground = .ansi(idx256) } else { background = .ansi(idx256) }
                        idx += 2
                    } else if mode == 2, idx + 4 < groups.count {
                        let r = UInt8(clamping: Int(groups[idx + 2]) ?? 0)
                        let g = UInt8(clamping: Int(groups[idx + 3]) ?? 0)
                        let b = UInt8(clamping: Int(groups[idx + 4]) ?? 0)
                        if isFg { foreground = .rgb(r, g, b) } else { background = .rgb(r, g, b) }
                        idx += 4
                    }
                }
            default:
                break
            }
            idx += 1
        }
    }

    private func resetAttributes() {
        foreground = .defaultForeground
        background = .defaultBackground
        style = []
    }

    func currentPromptInput() -> String {
        guard !isAlternateScreen, let start = promptInputStart, start.line < totalLines else {
            return ""
        }
        let cursorGlobalLine = scrollback.count + cursorRow
        var endLine = max(start.line, cursorGlobalLine)
        while endLine + 1 < totalLines,
            withLine(at: endLine, { _, _, isWrapped in isWrapped }) == true
        {
            endLine += 1
        }
        guard
            let (cellCount, lastNonSpaceCol) = withLine(
                at: endLine,
                { cells, _, _ -> (Int, Int) in
                    let base = cells.startIndex
                    var last = -1
                    for col in stride(from: cells.count - 1, through: 0, by: -1) {
                        let cell = cells[base + col]
                        if cell.width != 0 && !cell.isSpace {
                            last = col
                            break
                        }
                    }
                    return (cells.count, last)
                }),
            cellCount > 0
        else {
            return ""
        }
        let cursorEndCol = endLine == cursorGlobalLine ? cursorCol - 1 : -1
        let endCol = max(lastNonSpaceCol, cursorEndCol)
        if endLine == start.line && endCol < start.col {
            return ""
        }
        if endCol < 0 && endLine == start.line {
            return ""
        }
        let clampedEndCol = min(max(endCol, 0), cellCount - 1)
        let raw = text(
            from: start,
            to: TerminalGridPoint(line: endLine, col: clampedEndCol))
        return raw.split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    func latestCommandOutput() -> String {
        if let startLine = activeOutputStartLine, !isAlternateScreen {
            let liveEnd = scrollback.count + cursorRow
            if liveEnd >= startLine {
                let live = extractOutputLines(
                    from: startLine, through: liveEnd, trimPromptEolMark: false)
                if !live.isEmpty {
                    return live
                }
            }
        }
        if let lastCompletedOutput, !lastCompletedOutput.isEmpty {
            return lastCompletedOutput
        }
        return plainText(includeScrollback: true)
    }

    private func extractOutputLines(
        from startLine: Int, through endLine: Int, trimPromptEolMark: Bool
    ) -> String {
        let start = max(0, startLine)
        let end = min(totalLines - 1, endLine)
        guard start <= end else { return "" }
        var lines: [String] = []
        var current = ""
        for idx in start...end {
            if idx == end {
                guard var row = line(at: idx) else { continue }
                row.isWrapped = false
                if trimPromptEolMark {
                    Self.stripTrailingPromptEolMark(&row)
                }
                current.append(Self.trimmedLineString(row))
                lines.append(current)
                current = ""
            } else {
                guard
                    let (text, isWrapped) = withLine(
                        at: idx,
                        { cells, graphemes, isWrapped in
                            (
                                Self.trimmedSliceString(
                                    cells: cells, graphemes: graphemes, isWrapped: isWrapped),
                                isWrapped
                            )
                        })
                else {
                    continue
                }
                current.append(text)
                if !isWrapped {
                    lines.append(current)
                    current = ""
                }
            }
        }
        if !current.isEmpty {
            lines.append(current)
        }
        while lines.last?.isEmpty == true {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    private static func stripTrailingPromptEolMark(_ row: inout TerminalGridLine) {
        for col in stride(from: row.cells.count - 1, through: 0, by: -1) {
            let cell = row.cells[col]
            if cell.width == 0 || cell.isSpace { continue }
            if !cell.hasGraphemeCluster, cell.asciiByte == 0x25, cell.style.contains(.inverse) {
                row.clearCell(at: col)
            }
            return
        }
    }

    /// `!plainText().isEmpty` without building up to 4,000 lines of text to find out.
    var hasText: Bool {
        (0..<totalLines).reversed().contains { index in
            withLine(at: index) { cells, _, isWrapped in
                cells.contains { $0.width != 0 && (isWrapped || !$0.isSpace) }
            } ?? false
        }
    }

    func plainText(includeScrollback: Bool = true) -> String {
        let start = includeScrollback ? 0 : scrollback.count
        guard start < totalLines else { return "" }
        var lines: [String] = []
        var current = ""
        for idx in start..<totalLines {
            guard
                let (text, isWrapped) = withLine(
                    at: idx,
                    { cells, graphemes, isWrapped in
                        (
                            Self.trimmedSliceString(
                                cells: cells, graphemes: graphemes, isWrapped: isWrapped),
                            isWrapped
                        )
                    })
            else {
                continue
            }
            current.append(text)
            if !isWrapped {
                lines.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            lines.append(current)
        }
        while lines.last?.isEmpty == true {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    func text(from a: TerminalGridPoint, to b: TerminalGridPoint) -> String {
        let low = min(a, b)
        let high = max(a, b)
        guard low.line < totalLines else { return "" }
        let startLine = max(0, low.line)
        let endLine = min(totalLines - 1, high.line)
        guard startLine <= endLine else { return "" }

        var output = ""
        for lineIdx in startLine...endLine {
            guard
                let (slice, isWrapped) = withLine(
                    at: lineIdx,
                    { cells, graphemes, isWrapped -> (String, Bool) in
                        let count = cells.count
                        guard count > 0 else { return ("", isWrapped) }
                        let base = cells.startIndex
                        let cStart = lineIdx == startLine ? max(0, low.col) : 0
                        let cEnd = lineIdx == endLine ? min(count - 1, high.col) : count - 1
                        guard cStart <= cEnd else { return ("", isWrapped) }
                        var chunk = ""
                        for c in cStart...cEnd {
                            let cell = cells[base + c]
                            if cell.width == 0 { continue }
                            if cell.hasGraphemeCluster, let cluster = graphemes?[c] {
                                chunk.append(cluster)
                            } else {
                                chunk.append(cell.character)
                            }
                        }
                        if lineIdx < endLine && !isWrapped {
                            chunk = chunk.replacingOccurrences(
                                of: "\\s+$", with: "", options: .regularExpression)
                        }
                        return (chunk, isWrapped)
                    })
            else {
                continue
            }
            output.append(slice)
            if lineIdx < endLine && !isWrapped {
                output.append("\n")
            }
        }
        return output
    }

    private static func trimmedLineString(_ row: TerminalGridLine) -> String {
        row.cells.withUnsafeBufferPointer { buf in
            trimmedSliceString(cells: buf, graphemes: row.graphemes, isWrapped: row.isWrapped)
        }
    }

    private static func trimmedSliceString(
        cells: UnsafeBufferPointer<TerminalCell>,
        graphemes: [Int: Character]?,
        isWrapped: Bool
    ) -> String {
        var endCol = cells.count - 1
        if !isWrapped {
            while endCol >= 0 {
                let cell = cells[endCol]
                if cell.width == 0 || cell.isSpace {
                    endCol -= 1
                } else {
                    break
                }
            }
        }
        guard endCol >= 0 else { return "" }
        var result = ""
        result.reserveCapacity(endCol + 1)
        for col in 0...endCol {
            let cell = cells[col]
            if cell.width == 0 { continue }
            if cell.hasGraphemeCluster, let cluster = graphemes?[col] {
                result.append(cluster)
            } else {
                result.unicodeScalars.append(cell.scalar)
            }
        }
        return result
    }

    private static func isCombiningMark(_ scalar: UnicodeScalar) -> Bool {
        let v = scalar.value
        return (0x0300...0x036F).contains(v)
            || (0x1AB0...0x1AFF).contains(v)
            || (0x1DC0...0x1DFF).contains(v)
            || (0x20D0...0x20FF).contains(v)
            || (0xFE00...0xFE0F).contains(v)
            || (0xFE20...0xFE2F).contains(v)
            || (0x1F3FB...0x1F3FF).contains(v)
            || v == 0x200D
    }

    private static func displayWidth(of scalar: UnicodeScalar) -> UInt8 {
        let v = scalar.value
        if v < 0x20 || (0x7F...0x9F).contains(v) { return 0 }
        if isCombiningMark(scalar) { return 0 }
        if (0x1100...0x115F).contains(v)
            || (0x2329...0x232A).contains(v)
            || (0x2E80...0x303E).contains(v)
            || (0x3040...0xA4CF).contains(v)
            || (0xAC00...0xD7A3).contains(v)
            || (0xF900...0xFAFF).contains(v)
            || (0xFE10...0xFE19).contains(v)
            || (0xFE30...0xFE6F).contains(v)
            || (0xFF00...0xFF60).contains(v)
            || (0xFFE0...0xFFE6).contains(v)
            || (0x1F300...0x1FAFF).contains(v)
            || (0x20000...0x3FFFD).contains(v)
        {
            return 2
        }
        return 1
    }

    private static let decLineDrawingMap: [UInt8: UnicodeScalar] = [
        0x60: "◆", 0x61: "▒", 0x66: "°", 0x67: "±", 0x6A: "┘", 0x6B: "┐",
        0x6C: "┌", 0x6D: "└", 0x6E: "┼", 0x6F: "⎺", 0x70: "⎻", 0x71: "─",
        0x72: "⎼", 0x73: "⎽", 0x74: "├", 0x75: "┤", 0x76: "┴", 0x77: "┬",
        0x78: "│", 0x79: "≤", 0x7A: "≥", 0x7B: "π", 0x7C: "≠", 0x7D: "£",
        0x7E: "·"
    ]
}

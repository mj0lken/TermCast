import Foundation

enum DisplayDDC {
    struct Identity: Equatable, Sendable {
        var vendorID: UInt32
        var modelID: UInt32
        var serialNumber: UInt32
    }

    struct Target: Equatable, Sendable {
        var identity: Identity
        var allowsSingleExternalFallback: Bool
    }

    private static let edidHeader: [UInt8] = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]
    private static let hostChecksumSeed: UInt8 = 0x6E ^ 0x51
    private static let vcpLuminance: UInt8 = 0x10

    static func parseEDID(_ data: Data) -> Identity? {
        guard data.count >= 16, data.prefix(8).elementsEqual(edidHeader) else { return nil }
        let vendorID = (UInt32(data[8]) << 8) | UInt32(data[9])
        let modelID = UInt32(data[10]) | (UInt32(data[11]) << 8)
        let serialNumber =
            UInt32(data[12])
            | (UInt32(data[13]) << 8)
            | (UInt32(data[14]) << 16)
            | (UInt32(data[15]) << 24)
        return Identity(vendorID: vendorID, modelID: modelID, serialNumber: serialNumber)
    }

    static func matchIndex(for target: Target, in candidates: [Identity?]) -> Int? {
        if target.identity.serialNumber != 0,
            let exact = candidates.firstIndex(where: { $0 == target.identity })
        {
            return exact
        }
        // Many monitors zero the numeric EDID serial and store an ASCII descriptor instead.
        if let vendorModel = candidates.firstIndex(where: { candidate in
            guard let candidate else { return false }
            let serialCompatible = target.identity.serialNumber == 0 || candidate.serialNumber == 0
            return candidate.vendorID == target.identity.vendorID
                && candidate.modelID == target.identity.modelID
                && serialCompatible
        }) {
            return vendorModel
        }
        if target.allowsSingleExternalFallback, candidates.count == 1 {
            return 0
        }
        return nil
    }

    static func makeBrightnessWritePacket(level: Double) -> [UInt8] {
        let clamped = min(max(level, 0), 1)
        let percent = UInt8((clamped * 100).rounded())
        var packet: [UInt8] = [0x84, 0x03, vcpLuminance, 0x00, percent, 0x00]
        packet[5] = packet.dropLast().reduce(hostChecksumSeed, ^)
        return packet
    }

    static func makeBrightnessReadRequest() -> [UInt8] {
        var packet: [UInt8] = [0x82, 0x01, vcpLuminance, 0x00]
        packet[3] = packet.dropLast().reduce(hostChecksumSeed, ^)
        return packet
    }

    static func parseBrightnessReply(_ bytes: [UInt8]) -> Double? {
        for offset in [2, 1, 0] where offset + 7 < bytes.count {
            guard bytes[offset] == 0x02,
                bytes[offset + 1] == 0x00,
                bytes[offset + 2] == vcpLuminance
            else { continue }
            let maximum = (UInt16(bytes[offset + 4]) << 8) | UInt16(bytes[offset + 5])
            let current = (UInt16(bytes[offset + 6]) << 8) | UInt16(bytes[offset + 7])
            guard maximum > 0 else { return nil }
            return min(max(Double(current) / Double(maximum), 0), 1)
        }
        return nil
    }
}

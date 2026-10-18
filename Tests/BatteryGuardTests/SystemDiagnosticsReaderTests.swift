import Testing
@testable import BatteryGuard

struct SystemDiagnosticsReaderTests {
    @Test func modelIdentifierTrimsNullTermination() {
        let bytes: [CChar] = Array("MacBookPro18,3".utf8).map { CChar(bitPattern: $0) } + [0, 0, 0]
        #expect(SystemDiagnosticsReader.modelIdentifier(from: bytes) == "MacBookPro18,3")
    }

    @Test func modelIdentifierStopsAtFirstNullByte() {
        var bytes: [CChar] = Array("Mac14,2".utf8).map { CChar(bitPattern: $0) }
        bytes += [0]
        bytes += Array("Rest".utf8).map { CChar(bitPattern: $0) }
        #expect(SystemDiagnosticsReader.modelIdentifier(from: bytes) == "Mac14,2")
    }

    @Test func modelIdentifierHandlesFullBufferWithoutTerminator() {
        let bytes: [CChar] = Array("MacBookPro18,3".utf8).map { CChar(bitPattern: $0) }
        #expect(SystemDiagnosticsReader.modelIdentifier(from: bytes) == "MacBookPro18,3")
    }

    @Test func modelIdentifierReturnsEmptyStringForEmptyBuffer() {
        #expect(SystemDiagnosticsReader.modelIdentifier(from: []) == "")
        #expect(SystemDiagnosticsReader.modelIdentifier(from: [0, 0]) == "")
    }
}

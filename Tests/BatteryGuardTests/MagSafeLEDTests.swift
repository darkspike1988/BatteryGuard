import Testing
@testable import batteryguardd

struct MagSafeLEDTests {
    @Test func autoTrustsTheWriteResultBecauseFirmwareReportsItsOwnColor() {
        var reads = 0
        #expect(SMCClient.confirmMagSafeLED(.auto, written: true, wait: {}, read: { reads += 1; return 3 }))
        #expect(reads == 0)
        #expect(!SMCClient.confirmMagSafeLED(.auto, written: false, wait: {}, read: { 0 }))
    }

    @Test func colorsWaitForTheDelayedReadback() {
        var values: [UInt8] = [3, 3, 4] // gemessen: zuerst alter Wert, dann neuer
        var waits = 0
        #expect(SMCClient.confirmMagSafeLED(.orange, written: true, wait: { waits += 1 }, read: { values.removeFirst() }))
        #expect(waits == 2)
    }

    @Test func colorsFailAfterBoundedAttempts() {
        var reads = 0
        #expect(!SMCClient.confirmMagSafeLED(.off, written: true, attempts: 4, wait: {}, read: { reads += 1; return 3 }))
        #expect(reads == 4)
        #expect(!SMCClient.confirmMagSafeLED(.green, written: false, wait: {}, read: { 3 }))
    }
}

import Foundation
import Testing
@testable import BatteryGuard

struct PowerDetailsReaderTests {
    @Test func adapterDetailsAreConvertedToUnits() {
        let properties: [String: Any] = [
            "ExternalConnected": true,
            "AdapterDetails": [
                "Name": "67W USB-C Power Adapter", "Manufacturer": "Apple Inc.", "Watts": 65,
                "AdapterVoltage": 20000, "Current": 3260, "SerialString": "C0TEST", "FwVersion": "01050036",
                "IsWireless": false,
            ] as [String: Any],
        ]
        let info = PowerDetailsReader.parseAdapter(properties: properties)
        #expect(info?.name == "67W USB-C Power Adapter")
        #expect(info?.ratedWatts == 65)
        #expect(info?.voltage == 20)
        #expect(info?.current == 3.26)
        #expect(info?.serialNumber == "C0TEST")
        #expect(info?.isWireless == false)
    }

    @Test func missingOrImplausibleAdapterValuesStayUnknown() {
        #expect(PowerDetailsReader.parseAdapter(properties: ["ExternalConnected": false, "AdapterDetails": ["Watts": 65]]) == nil)
        #expect(PowerDetailsReader.parseAdapter(properties: ["ExternalConnected": true]) == nil)
        #expect(PowerDetailsReader.parseAdapter(properties: ["ExternalConnected": true, "AdapterDetails": ["Watts": 0, "Name": " "]]) == nil)
        let info = PowerDetailsReader.parseAdapter(properties: ["ExternalConnected": true,
            "AdapterDetails": ["Watts": true, "AdapterVoltage": 999_999, "Name": "USB-C"] as [String: Any]])
        #expect(info == BGAdapterInfo(name: "USB-C"))
    }

    @Test func energyConsumersComeFromTheLastSample() {
        let output = """
        Processes: 600 total
        PID    POWER COMMAND
        1      0.0   launchd
        99     99.0  firstSampleOnly

        Processes: 600 total
        PID    POWER COMMAND
        457    14.2  WindowServer
        31309  61.8  spotlightknowled
        40580  10.6  top
        791    0.0   Terminal
        12     5.5   Google Chrome He
        """
        let consumers = PowerDetailsReader.parseEnergyConsumers(output, limit: 2)
        #expect(consumers.map(\.name) == ["spotlightknowled", "WindowServer"])
        #expect(consumers.first?.pid == 31309)
        #expect(PowerDetailsReader.parseEnergyConsumers(output).map(\.name).last == "Google Chrome He")
        #expect(PowerDetailsReader.parseEnergyConsumers("garbage").isEmpty)
    }
}

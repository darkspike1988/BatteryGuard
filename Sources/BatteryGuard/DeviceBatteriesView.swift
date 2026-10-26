import SwiftUI

/// Akkustände verbundener Geräte; Abfrage nur, solange die Diagnoseseite sichtbar ist.
struct DeviceBatteriesView: View {
    @State private var devices: [BGDeviceBattery] = []
    @State private var loaded = false

    var body: some View {
        BGPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text("Geräteakkus").font(.headline)
                if devices.isEmpty {
                    Text(loaded ? "Kein verbundenes Gerät meldet einen Akkustand." : "Messung läuft …").foregroundStyle(.secondary)
                }
                ForEach(devices) { device in
                    LabeledContent(device.name, value: device.levels.sorted { $0.key < $1.key }
                        .map { $0.key.isEmpty ? "\($0.value) %" : "\(L($0.key)) \($0.value) %" }.joined(separator: " · "))
                }
                Text("Werte meldet macOS für verbundene Apple- und Standard-Bluetooth-Geräte. Manche Hersteller (z. B. Logitech) melden den Akkustand nur in eigener Software.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .task {
            guard !DesignPreview.isRendering else { return }
            while !Task.isCancelled {
                devices = await Task.detached(priority: .utility) { DeviceBatteryReader.read() }.value
                loaded = true
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }
}

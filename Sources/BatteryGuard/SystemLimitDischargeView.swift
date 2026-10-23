import SwiftUI
import BatteryGuardShared

/// Einmal entladen im macOS-Limit-Modus: Die Firmware entlädt am Netzteil bis zur gewählten Stufe.
struct SystemLimitDischargeView: View {
    let steps: [Int]
    let percent: Int
    let perform: (BGChargingActionRequest) -> Void
    @State private var target = 80

    private var targets: [Int] { steps.filter { $0 < 100 && $0 < percent } }

    var body: some View {
        if targets.isEmpty {
            Text("Einmal entladen ist möglich, sobald der Akku über einer macOS-Stufe unter 100 % liegt.")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            Picker("Entladen auf", selection: $target) {
                ForEach(targets, id: \.self) { Text(L("%lld %%", $0)).tag($0) }
            }
            .onAppear { if !targets.contains(target) { target = targets.first ?? 80 } }
            Button("Einmal entladen · experimentell") {
                perform(.init(action: .dischargeTo, minutes: 480, targetPercent: target))
            }
            Text("Setzt das macOS-Limit vorübergehend auf die Stufe; die Firmware entlädt dann am Netzteil. Danach gilt wieder dein Profil. Hardware-Abnahme steht aus.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

import SwiftUI
import BatteryGuardShared

struct SpecialChargeActionsView: View {
    @Bindable var configStore: ConfigStore
    @Bindable var statusStore: StatusStore
    @State private var duration = 480
    @State private var error: String?
    private var canTopUp: Bool {
        statusStore.supportsChargingPlans && statusStore.status.hasBatteryPercent && statusStore.status.hasExternalPower && statusStore.status.smcKeysDetected.contains(where: {
            $0 == "CHTE" || $0 == "CH0B"
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let plan = configStore.config.specialChargePlan {
                Text(title(plan.kind)).font(.headline)
                Text("Ziel: \(plan.targetPercent) % · spätestens bis \(plan.expiresAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Sonderaktion beenden") { perform(.init(action: .cancelSpecial)) }
            } else {
                Picker("Maximale Dauer", selection: $duration) {
                    Text("2 Stunden").tag(120)
                    Text("8 Stunden").tag(480)
                    Text("24 Stunden").tag(1440)
                }
                Button("Top Up bis Abstecken") { perform(.init(action: .topUp, minutes: duration)) }
                    .disabled(!canTopUp)
                Text("Lädt bis 100 % und hält den Ladestand bis zum Abstecken oder Ablauf. Danach gilt wieder dein Basisprofil. Hitzeschutz bleibt aktiv.")
                    .font(.caption).foregroundStyle(.secondary)
                if !canTopUp {
                    Text("Top Up benötigt einen aktuellen Dienst und eine separate Ladesperre. Auf diesem Mac ist diese Fähigkeit momentan nicht bestätigt.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Einmalentladung und „Laden hier halten“ sind vorbereitet, bleiben aber bis zur physischen Hardware-Abnahme gesperrt.")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }
    }
    private func perform(_ request: BGChargingActionRequest) {
        do { _ = try configStore.performAPIAction(request); error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func title(_ kind: BGSpecialPlanKind) -> String {
        switch kind {
        case .topUp: "Top Up bis Abstecken"
        case .discharge: "Einmalentladung"
        case .hold: "Ladestand halten"
        }
    }
}

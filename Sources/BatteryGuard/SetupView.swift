import SwiftUI
import AppKit
import BatteryGuardShared

@MainActor
struct SetupView: View {
    @State private var services = ServiceManager()
    let close: () -> Void
    private var needsCopy: Bool {
        (try? Bundle.main.bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "battery.75percent")
                .font(.system(size: 52, weight: .regular)).foregroundStyle(.secondary)
            Text("Willkommen bei B-Guard").font(.title2.weight(.semibold))
            Text(needsCopy
                 ? "Ziehe B-Guard zuerst in den Programme-Ordner. Öffne die App anschließend von dort."
                 : "Ein letzter Schritt: Der Hintergrunddienst liest die Akkuwerte und führt deine Ladeprofile aus. macOS fragt dafür einmal nach deinem Administratorpasswort.")
                .foregroundStyle(.secondary)
            if let message = services.message {
                Text(message).foregroundStyle(services.isError ? Color.orange : Color.secondary)
                    .textSelection(.enabled)
            }
            HStack {
                Button(services.message != nil && !services.isError ? "Fertig" : "Später", action: close)
                    .disabled(services.isBusy)
                Spacer()
                if !needsCopy && (services.message == nil || services.isError) {
                    Button(services.isBusy ? "Wird eingerichtet …" : "B-Guard einrichten") {
                        services.install()
                    }
                    .buttonStyle(.borderedProminent).disabled(services.isBusy)
                }
            }
        }
        .padding(32).frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .interactiveDismissDisabled(services.isBusy)
    }
}

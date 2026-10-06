import SwiftUI
import AppKit
import UniformTypeIdentifiers
import BatteryGuardShared

/// Native SwiftUI view for managing, applying, editing, importing, and exporting custom charging profiles.
struct SavedProfilesView: View {
    @Bindable var configStore: ConfigStore
    @State private var store: SavedProfileStore

    // MARK: - Sheet & Alert State (Using Bool to avoid identifier conformance assumptions)
    @State private var showSaveCurrentSheet: Bool = false
    @State private var showAddSheet: Bool = false
    @State private var showEditSheet: Bool = false
    @State private var showImportPreviewSheet: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @State private var showAlert: Bool = false

    // MARK: - Action & Error State
    @State private var alertTitle: String = "Hinweis"
    @State private var alertMessage: String = ""

    // Save Current Limits state
    @State private var saveCurrentName: String = ""
    @State private var saveCurrentError: String? = nil

    // Add / Edit state
    @State private var editTargetID: UUID? = nil
    @State private var editName: String = ""
    @State private var editLowerLimit: Int = 40
    @State private var editUpperLimit: Int = 80
    @State private var editHeatProtection: Int = 0
    @State private var editActiveDischarge: Bool = false
    @State private var editErrorMessage: String? = nil

    // Delete state
    @State private var deleteTargetID: UUID? = nil
    @State private var deleteTargetName: String = ""

    // Import Preview state
    @State private var didLoad = false
    @State private var importError: String?
    @State private var pendingDischargeProfile: BGSavedProfile?
    @State private var confirmDischarge = false
    @State private var pendingImportCollection: BGSavedProfileCollection? = nil

    init(configStore: ConfigStore, store: SavedProfileStore? = nil) {
        self.configStore = configStore
        self._store = State(initialValue: store ?? SavedProfileStore(loadImmediately: false))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            VStack(alignment: .leading, spacing: 10) {
                BGSectionHeading(
                    title: "Gespeicherte Profile",
                    subtitle: "Eigene Lade- und Entladeprofile verwalten und anwenden"
                )
                HStack(spacing: 8) {
                    Button {
                        importProfilesFromDisk()
                    } label: {
                        Label("Importieren…", systemImage: "square.and.arrow.down")
                    }
                    .help("Profile aus einer JSON-Datei importieren")

                    Button {
                        exportProfilesToDisk()
                    } label: {
                        Label("Exportieren…", systemImage: "square.and.arrow.up")
                    }
                    .disabled(store.profiles.isEmpty || store.loadErrorMessage != nil)
                    .help("Alle Profile in eine JSON-Datei sichern")

                    Button {
                        openSaveCurrentSheet()
                    } label: {
                        Label("Aktuelle Limits sichern", systemImage: "plus.circle")
                    }
                    .disabled(store.isCorrupt || store.loadErrorMessage != nil)
                    .help("Die aktuell eingestellten Limits als Profil speichern")
                }
                Button {
                    do { try store.load() }
                    catch {
                        alertTitle = "Profile konnten nicht geladen werden"
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                } label: {
                    Label("Profile neu laden", systemImage: "arrow.clockwise")
                }
                .help("Aktuelle Änderungen anderer Fenster oder Programme übernehmen")
            }

            // Corruption Warning Banner
            if store.loadErrorMessage != nil {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.isCorrupt ? "Profildatei beschädigt" : "Profildatei nicht lesbar")
                            .font(.headline)
                        Text(store.loadErrorMessage ?? "Unbekannter Lesefehler beim Laden der Profile.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Die Originaldatei auf der Festplatte bleibt unberührt und wird nicht überschrieben. Bei beschädigten Daten können Sie eine gültige Sicherung über 'Importieren…' einspielen. Bei Lesefehlern zuerst den Dateizugriff wiederherstellen; übergroße Dateien zuerst manuell sichern und verschieben.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.orange.opacity(0.3)))
            }

            // Profile List or Empty State
            if store.profiles.isEmpty {
                BGPanel {
                    VStack(spacing: 12) {
                        Image(systemName: "slider.horizontal.2.square")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(.secondary)
                        Text(store.isCorrupt ? "Keine Profile verfügbar" : "Keine gespeicherten Profile")
                            .font(.headline)
                        Text(store.isCorrupt
                             ? "Importieren Sie eine gültige Sicherung, um Profile wiederherzustellen."
                             : "Erstelle ein neues Profil oder speichere die aktuell konfigurierten Ladelimits.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        if !store.isCorrupt {
                            HStack(spacing: 12) {
                                Button("Aktuelle Limits sichern") {
                                    openSaveCurrentSheet()
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Neues Profil anlegen") {
                                    openAddSheet()
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(store.profiles) { profile in
                        profileRow(profile)
                    }
                }
            }
        }
        .padding(20)
        .task { if !didLoad && !DesignPreview.isRendering { didLoad = true; _ = try? store.load() } }
        .confirmationDialog("Aktives Entladen einschalten?", isPresented: $confirmDischarge, titleVisibility: .visible) {
            Button("Profil mit aktivem Entladen anwenden") {
                if let profile = pendingDischargeProfile { applyProfile(profile, confirmed: true) }
                pendingDischargeProfile = nil
            }
            Button("Abbrechen", role: .cancel) { pendingDischargeProfile = nil }
        } message: { Text("Dieses Profil kann das Netzteil softwareseitig trennen und den Akku entladen. Monitor- und Deckelschutz bleiben aktiv.") }
        // Sheets driven by Bool state
        .sheet(isPresented: $showSaveCurrentSheet) {
            saveCurrentSheetContent
        }
        .sheet(isPresented: $showAddSheet) {
            profileEditSheetContent(isNew: true)
        }
        .sheet(isPresented: $showEditSheet) {
            profileEditSheetContent(isNew: false)
        }
        .sheet(isPresented: $showImportPreviewSheet) {
            importPreviewSheetContent
        }
        .confirmationDialog(
            "Profil wirklich löschen?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Löschen", role: .destructive) {
                if let id = deleteTargetID {
                    do {
                        try store.delete(id: id)
                    } catch {
                        alertTitle = "Fehler beim Löschen"
                        alertMessage = error.localizedDescription
                        showAlert = true
                    }
                }
                deleteTargetID = nil
            }
            Button("Abbrechen", role: .cancel) {
                deleteTargetID = nil
            }
        } message: {
            Text("Möchtest du das Profil '\(deleteTargetName)' unwiderruflich löschen?")
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Profile Row View

    @ViewBuilder
    private func profileRow(_ profile: BGSavedProfile) -> some View {
        let isCurrent = profile.matches(configStore.config)

        BGPanel {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(profile.name)
                            .font(.headline)

                        if isCurrent {
                            Text("Aktiv")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        }

                        if profile.activeDischargeAboveUpper {
                            Label("Aktives Entladen", systemImage: "arrow.down.forward.and.arrow.up.backward")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                    }

                    HStack(spacing: 16) {
                        Label("\(profile.lowerLimit) % – \(profile.upperLimit) %", systemImage: "bolt.badge.clock")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if profile.heatProtectionCelsius > 0 {
                            Label("Hitzeschutz: \(profile.heatProtectionCelsius) °C", systemImage: "thermometer.medium")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Label("Hitzeschutz: Aus", systemImage: "thermometer.snowflake")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    Button("Anwenden") {
                        applyProfile(profile)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCurrent || configStore.config.mode == .native || configStore.config.mode == .direct)

                    Menu {
                        Button {
                            openEditSheet(for: profile)
                        } label: {
                            Label("Bearbeiten…", systemImage: "pencil")
                        }

                        Divider()

                        Button(role: .destructive) {
                            deleteTargetID = profile.id
                            deleteTargetName = profile.name
                            showDeleteConfirmation = true
                        } label: {
                            Label("Löschen…", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 28)
                }
            }
        }
    }

    // MARK: - Actions

    private func applyProfile(_ profile: BGSavedProfile, confirmed: Bool = false) {
        if profile.activeDischargeAboveUpper && !confirmed { pendingDischargeProfile = profile; confirmDischarge = true; return }
        do {
            _ = try configStore.performAPIAction(.init(action: .savedProfile, savedProfile: profile))
        } catch {
            alertTitle = "Fehler beim Anwenden"
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    private func openSaveCurrentSheet() {
        saveCurrentName = "Profil vom \(Date().formatted(date: .numeric, time: .shortened))"
        saveCurrentError = nil
        showSaveCurrentSheet = true
    }

    private func openAddSheet() {
        editTargetID = UUID()
        editName = ""
        editLowerLimit = 40
        editUpperLimit = 80
        editHeatProtection = 0
        editActiveDischarge = false
        editErrorMessage = nil
        showAddSheet = true
    }

    private func openEditSheet(for profile: BGSavedProfile) {
        editTargetID = profile.id
        editName = profile.name
        editLowerLimit = profile.lowerLimit
        editUpperLimit = profile.upperLimit
        editHeatProtection = profile.heatProtectionCelsius
        editActiveDischarge = profile.activeDischargeAboveUpper
        editErrorMessage = nil
        showEditSheet = true
    }

    private func importProfilesFromDisk() {
        let panel = NSOpenPanel()
        panel.title = "Profile importieren"
        panel.prompt = "Importieren"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try SavedProfileStore.readBoundedData(from: url)
            let collection = try BGSavedProfileCollection.importData(data)
            self.pendingImportCollection = collection
            self.showImportPreviewSheet = true
        } catch {
            alertTitle = "Import fehlgeschlagen"
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    private func exportProfilesToDisk() {
        guard !store.profiles.isEmpty else {
            alertTitle = "Export nicht möglich"
            alertMessage = "Es sind keine Profile zum Exportieren vorhanden."
            showAlert = true
            return
        }

        let panel = NSSavePanel()
        panel.title = "Profile exportieren"
        panel.prompt = "Exportieren"
        panel.nameFieldStringValue = "BatteryGuard-Profile.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try store.exportData()
            try data.write(to: url, options: .atomic)
        } catch {
            alertTitle = "Export fehlgeschlagen"
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    // MARK: - Save Current Limits Sheet Content

    private var saveCurrentSheetContent: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Profilname", text: $saveCurrentName)
                        .textFieldStyle(.roundedBorder)

                    if let saveCurrentError {
                        Text(saveCurrentError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Neuer Name")
                }

                Section {
                    LabeledContent("Starten bei (Unteres Limit)", value: "\(configStore.config.lowerLimit) %")
                    LabeledContent("Stoppen bei (Oberes Limit)", value: "\(configStore.config.upperLimit) %")
                    LabeledContent("Hitzeschutz", value: configStore.config.heatProtectionCelsius == 0
                                   ? "Deaktiviert"
                                   : "\(configStore.config.heatProtectionCelsius) °C")
                    LabeledContent("Aktives Entladen", value: configStore.config.activeDischargeAboveUpper ? "Aktiviert" : "Deaktiviert")
                } header: {
                    Text("Zu speichernde Grenzwerte")
                } footer: {
                    Text("Diese Einstellungen werden direkt aus deiner aktuellen Konfiguration übernommen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Aktuelle Limits als Profil sichern")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        showSaveCurrentSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        do {
                            _ = try store.saveCurrentLimits(name: saveCurrentName, config: configStore.config)
                            showSaveCurrentSheet = false
                        } catch {
                            saveCurrentError = error.localizedDescription
                        }
                    }
                    .disabled(saveCurrentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .frame(minWidth: 420, minHeight: 320)
        }
    }

    // MARK: - Add / Edit Sheet Content

    private func profileEditSheetContent(isNew: Bool) -> some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Profilname", text: $editName)
                        .textFieldStyle(.roundedBorder)

                    if let editErrorMessage {
                        Text(editErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Bezeichnung")
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Unteres Ladelimit (Laden starten)")
                            Spacer()
                            Text("\(editLowerLimit) %").bold().monospacedDigit()
                        }
                        Slider(value: Binding(
                            get: { Double(editLowerLimit) },
                            set: { editLowerLimit = Int($0) }
                        ), in: 5...95, step: 1)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Oberes Ladelimit (Laden stoppen)")
                            Spacer()
                            Text("\(editUpperLimit) %").bold().monospacedDigit()
                        }
                        Slider(value: Binding(
                            get: { Double(editUpperLimit) },
                            set: { editUpperLimit = Int($0) }
                        ), in: 20...100, step: 1)
                    }
                } header: {
                    Text("Ladebegrenzungen")
                } footer: {
                    Text("Das obere Limit muss größer sein als das untere Limit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Picker("Hitzeschutz", selection: $editHeatProtection) {
                        Text("Deaktiviert").tag(0)
                        ForEach(30...50, id: \.self) { temp in
                            Text("\(temp) °C").tag(temp)
                        }
                    }

                    Toggle("Aktives Entladen über oberem Limit", isOn: $editActiveDischarge)

                    if editActiveDischarge {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                            Text("Warnung: Der Akku wird aktiv am Netzteil entladen, sobald die Ladung über dem oberen Limit liegt. Dies erhöht die Zyklenbelastung.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Zusatzoptionen")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? "Neues Profil erstellen" : "Profil bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        if isNew { showAddSheet = false } else { showEditSheet = false }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        saveProfileEdit(isNew: isNew)
                    }
                    .disabled(editName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .frame(minWidth: 460, minHeight: 460)
        }
    }

    private func saveProfileEdit(isNew: Bool) {
        do {
            let profileID = isNew ? UUID() : (editTargetID ?? UUID())
            let profile = try BGSavedProfile(
                id: profileID,
                name: editName,
                lowerLimit: editLowerLimit,
                upperLimit: editUpperLimit,
                heatProtectionCelsius: editHeatProtection,
                activeDischargeAboveUpper: editActiveDischarge
            )

            if isNew {
                try store.add(profile)
                showAddSheet = false
            } else {
                try store.update(profile)
                showEditSheet = false
            }
        } catch {
            editErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Import Preview Sheet Content

    private var importPreviewSheetContent: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if let importError { Text(importError).foregroundStyle(.orange) }
                if let collection = pendingImportCollection {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Vorschau der zu importierenden Profile (\(collection.profiles.count)):")
                            .font(.headline)

                        let hasActiveDischarge = collection.profiles.contains { $0.activeDischargeAboveUpper }
                        if hasActiveDischarge {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Warnung: Aktives Entladen vorhanden")
                                        .font(.subheadline.weight(.semibold))
                                    Text("Ein oder mehrere Profile aktivieren das aktive Entladen über dem oberen Ladelimit. Der Akku wird hierbei am Netzteil entladen.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    List(collection.profiles) { profile in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(profile.name)
                                    .font(.headline)
                                Spacer()
                                Text("\(profile.lowerLimit) % → \(profile.upperLimit) %")
                                    .font(.subheadline.weight(.medium))
                            }
                            HStack(spacing: 12) {
                                Text(profile.heatProtectionCelsius > 0
                                     ? "Hitzeschutz: \(profile.heatProtectionCelsius) °C"
                                     : "Hitzeschutz: Aus")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                if profile.activeDischargeAboveUpper {
                                    Text("⚠️ Aktives Entladen aktiv")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.bordered(alternatesRowBackgrounds: true))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hinweis zum Import:")
                            .font(.caption.weight(.semibold))
                        Text(store.isCorrupt ? "Die beschädigte Profildatei wird gesichert und durch den Import ersetzt." : "Der Import ersetzt alle bestehenden Profile (\(store.profiles.count)). Die vorherige Datei wird gesichert.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(20)
            .navigationTitle("Profile importieren")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        pendingImportCollection = nil
                        showImportPreviewSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bestehende Profile ersetzen", role: .destructive) {
                        guard let collection = pendingImportCollection else { return }
                        do {
                            try store.replaceCollection(collection)
                            pendingImportCollection = nil
                            showImportPreviewSheet = false
                        } catch {
                            importError = error.localizedDescription
                        }
                    }
                }
            }
            .frame(minWidth: 480, minHeight: 420)
        }
    }
}

import SwiftUI
import BatteryGuardShared

struct ScheduledTasksView: View {
    @Bindable var configStore: ConfigStore
    @State private var editing = false
    @State private var editID: UUID?
    @State private var name = "Neuer Zeitplan"
    @State private var start = Date().addingTimeInterval(3600)
    @State private var recurrence: ScheduledRule.Recurrence = .daily
    @State private var kind: BGScheduledAction.Kind = .profile
    @State private var profileKey = BGProfile.everyday.rawValue
    @State private var profileSnapshot: BGSavedProfile?
    @State private var profileStore = SavedProfileStore(loadImmediately: false)
    @State private var loadedProfiles = false
    @State private var zone = TimeZone.current.identifier
    @State private var catchUp = false
    @State private var enabled = true
    @State private var minutes = 480
    @State private var target = 50
    @State private var error: String?
        var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Zeitpläne laufen im Hintergrunddienst, auch bei geschlossener App. Manuelle Aktionen haben Vorrang; eine manuelle Profilwahl übersteuert Zeitpläne für zwei Stunden.")
                .font(.caption).foregroundStyle(.secondary)
            if let until = configStore.config.manualOverrideUntil, until > Date() {
                Text("Manuelle Übersteuerung bis \(until.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(configStore.config.scheduledTasks) { task in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Toggle(task.schedule.name, isOn: Binding(get: { task.enabled }, set: { value in
                            var edited = task; edited.enabled = value
                            perform(.init(action: .upsertSchedule, scheduledTask: edited))
                        }))
                        Button("Bearbeiten") { open(task) }
                        Button("Löschen", role: .destructive) { perform(.init(action: .deleteSchedule, scheduleID: task.id)) }
                    }
                    Text("\(recurrenceTitle(task.schedule.recurrence)) · \(task.schedule.timeZoneIdentifier)")
                        .font(.caption).foregroundStyle(.secondary)
                    if let next = task.schedule.nextOccurrence(after: Date()), task.enabled {
                        Text("Nächster Termin: \(next.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                    }
                    if let last = task.state.lastExecutionDate {
                        Text("Zuletzt \(last.formatted(date: .abbreviated, time: .shortened)): \(resultTitle(task.state.lastResult))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 5)
            }
            Button("Zeitplan hinzufügen") { open(nil) }
                .disabled(configStore.config.scheduledTasks.count >= 50)
            if let error { Text(error).foregroundStyle(.orange).font(.caption) }
            if !configStore.config.scheduleHistory.isEmpty {
                DisclosureGroup("Letzte Aufgaben") {
                    ForEach(Array(configStore.config.scheduleHistory.suffix(10).reversed().enumerated()), id: \.offset) { _, run in
                        Text("\(run.executedAt.formatted(date: .abbreviated, time: .shortened)): \(resultTitle(run.resultString))")
                            .font(.caption)
                    }
                }
            }
        }
        .task { if !loadedProfiles && !DesignPreview.isRendering { loadedProfiles = true; _ = try? profileStore.load() } }
        .sheet(isPresented: $editing) { editor }
    }
    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(editID == nil ? "Zeitplan hinzufügen" : "Zeitplan bearbeiten").font(.title2)
            Form {
                TextField("Name", text: $name)
                Toggle("Aktiv", isOn: $enabled)
                DatePicker("Erster Termin", selection: $start)
                    .environment(\.timeZone, TimeZone(identifier: zone) ?? .current)
                TextField("Zeitzone", text: $zone)
                Picker("Wiederholung", selection: $recurrence) {
                    ForEach(ScheduledRule.Recurrence.allCases, id: \.self) { value in Text(recurrenceTitle(value)).tag(value) }
                }
                Picker("Aktion", selection: $kind) {
                    Text("Profil anwenden").tag(BGScheduledAction.Kind.profile)
                    Text("Top Up bis Abstecken").tag(BGScheduledAction.Kind.topUp)
                    Text("Ladestand halten · Hardware-Abnahme offen").tag(BGScheduledAction.Kind.hold)
                    Text("Einmal entladen · Hardware-Abnahme offen").tag(BGScheduledAction.Kind.discharge)
                }
                if kind == .profile {
                    Picker("Profil", selection: $profileKey) {
                        ForEach(BGProfile.allCases) { value in Text(value.title).tag(value.rawValue) }
                        ForEach(profileStore.profiles) { value in Text(value.name).tag(value.id.uuidString) }
                        if let profileSnapshot { Text("Gespeicherter Stand: " + profileSnapshot.name).tag("snapshot") }
                    }
                    if selectedProfileHasDischarge { Text("Dieses Profil schaltet aktives Entladen ein; das Netzteil kann softwareseitig getrennt werden.").font(.caption).foregroundStyle(.orange) }
                    Text("Die Profilparameter werden als eigener Stand im Zeitplan gespeichert.").font(.caption)
                } else {
                    Stepper("Maximale Dauer: \(minutes) Minuten", value: $minutes, in: 1...1440, step: 30)
                    if kind == .discharge { Stepper("Ziel: \(target) %", value: $target, in: 10...95) }
                    Text("Die Aktion wird nur bei bestätigter Fähigkeit ausgeführt. Halten und Einmalentladung bleiben bis zur Hardware-Abnahme gesperrt.").font(.caption)
                }
                Toggle("Verpassten Termin bis zu 6 Stunden nachholen", isOn: $catchUp)
                Text("Es wird höchstens der neueste Termin nachgeholt. Der 31. eines Monats und der 29. Februar werden in Monaten bzw. Jahren ohne diesen Tag übersprungen.").font(.caption)
            }
            if let error { Text(error).foregroundStyle(.orange).font(.caption) }
            HStack {
                Button("Abbrechen") { editing = false }
                Spacer()
                Button("Speichern") { save() }.buttonStyle(.borderedProminent)
            }
        }.padding(20).frame(width: 520)
    }
    private func open(_ task: BGScheduledTask?) {
        editID = task?.id; name = task?.schedule.name ?? "Neuer Zeitplan"
        start = task?.schedule.startsAt ?? Date().addingTimeInterval(3600)
        recurrence = task?.schedule.recurrence ?? .daily
        zone = task?.schedule.timeZoneIdentifier ?? TimeZone.current.identifier
        kind = task?.action.kind ?? .profile; enabled = task?.enabled ?? true
        catchUp = task?.catchUp ?? false; minutes = task?.action.minutes ?? 480
        target = task?.action.targetPercent ?? 50
        profileSnapshot = task?.action.profile
        profileKey = task?.action.profile == nil ? BGProfile.everyday.rawValue : "snapshot"
        _ = try? profileStore.load()
        error = nil; editing = true
    }
    private var selectedProfileHasDischarge: Bool {
        if profileKey == "snapshot" { return profileSnapshot?.activeDischargeAboveUpper == true }
        return profileStore.profiles.first { $0.id.uuidString == profileKey }?.activeDischargeAboveUpper == true
    }
    private func save() {
        do {
            let schedule = try ScheduledRule(id: editID ?? UUID(), name: name, timeZoneIdentifier: zone,
                startsAt: start, recurrence: recurrence)
            let existing = configStore.config.scheduledTasks.first { $0.id == editID }
            let saved: BGSavedProfile?
            if kind == .profile {
                if let builtin = BGProfile(rawValue: profileKey) {
                    saved = try BGSavedProfile(name: builtin.title, lowerLimit: builtin.lower, upperLimit: builtin.upper)
                } else if profileKey == "snapshot", let profileSnapshot { saved = profileSnapshot }
                else if let selected = profileStore.profiles.first(where: { $0.id.uuidString == profileKey }) { saved = selected }
                else { throw BGChargingActionError.invalidRequest("Das gewählte Profil ist nicht mehr vorhanden.") }
            } else { saved = nil }
            let action = BGScheduledAction(kind: kind, profile: saved,
                minutes: kind == .profile ? nil : minutes, targetPercent: kind == .discharge ? target : nil)
            let task = BGScheduledTask(schedule: schedule, enabled: enabled, catchUp: catchUp,
                action: action, state: existing?.state ?? .init())
            _ = try configStore.performAPIAction(.init(action: .upsertSchedule, scheduledTask: task))
            editing = false; error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func perform(_ request: BGChargingActionRequest) {
        do { _ = try configStore.performAPIAction(request); error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func recurrenceTitle(_ value: ScheduledRule.Recurrence) -> String {
        switch value {
        case .once: "Einmalig"
        case .daily: "Täglich"
        case .weekdays: "Montag bis Freitag"
        case .weekly: "Wöchentlich"
        case .biweekly: "Alle zwei Wochen"
        case .monthly: "Monatlich"
        case .yearly: "Jährlich"
        }
    }
    private func resultTitle(_ value: String?) -> String {
        switch value {
        case "stored: requested action": "Auftrag gespeichert"
        case "skipped: manual override": "Durch manuelle Aktion übersprungen"
        case "skipped: missed occurrence": "Verpassten Termin übersprungen"
        case "skipped: newer task selected": "Neueren Zeitplan bevorzugt"
        case "skipped: clock correction": "Nach Uhrzeitkorrektur übersprungen"
        case "failed: action unavailable or invalid": "Aktion nicht verfügbar oder ungültig"
        default: "Noch keine Ausführung"
        }
    }
}

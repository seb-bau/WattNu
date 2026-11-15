import SwiftUI

struct TimeSectionView: View {
    @EnvironmentObject private var session: SessionStore

    let commission: Commission

    @State private var entries: [TimeEntry] = []
    @State private var hoursText = ""
    @State private var workHoursText = ""
    @State private var waitingHoursText = ""
    @State private var materialHoursText = ""
    @State private var travelHoursText = ""
    @State private var documentationHoursText = ""
    @State private var extraHoursText = ""
    @State private var note = ""
    @State private var serviceDate = Date()
    @State private var editingEntry: TimeEntry?
    @State private var entryToDelete: TimeEntry?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var commissionTasks: [TimeTask] = []
    @State private var isLoadingTasks = true
    @FocusState private var focusedField: InputField?

    private enum InputField: Hashable {
        case totalHours
        case workHours
        case waitingHours
        case materialHours
        case travelHours
        case documentationHours
        case extraHours
        case note
    }

    private var selectedTask: TimeTask? {
        if let editingEntry {
            return editingEntry.taskTemplate
        }

        guard commissionTasks.count == 1 else {
            return nil
        }

        return commissionTasks.first
    }

    private var formTitle: String {
        editingEntry == nil ? "Zeit erfassen" : "Zeit bearbeiten"
    }

    private var saveButtonTitle: String {
        editingEntry == nil ? "Zeit speichern" : "Änderung speichern"
    }

    private var componentTexts: [String] {
        guard session.timeComponentsEnabled else {
            return []
        }

        return [
            workHoursText,
            waitingHoursText,
            materialHoursText,
            travelHoursText,
            documentationHoursText,
            extraHoursText
        ]
    }

    private var hasComponentInput: Bool {
        componentTexts.contains { value in
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var isSaveDisabled: Bool {
        if isLoading || commission.canEditValue == false {
            return true
        }

        if selectedTask == nil {
            return true
        }

        let hasTotalInput = !hoursText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return !hasTotalInput && !hasComponentInput
    }

    var body: some View {
        List {
            Section(formTitle) {
                if commission.canEditValue == false {
                    Text("Zeiten sind für Kollegenaufträge nur lesend verfügbar.")
                        .foregroundStyle(.secondary)
                }
                
                DatePicker(
                    "Leistungsdatum",
                    selection: $serviceDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .disabled(
                    isLoading || commission.canEditValue == false
                )

                if let selectedTask {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedTask.title)
                            .font(.headline)

                        Text(selectedTask.code)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if session.showServiceTargetTimes,
                           let suggestedMinutes = selectedTask.suggestedMinutes,
                           suggestedMinutes > 0 {
                            Text("SOLL-Zeit: \(WorkTimeText.duration(suggestedMinutes))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } else if isLoadingTasks {
                    ProgressView("Leistungsposition wird geladen …")
                } else {
                    Text("Diesem Auftrag ist keine eindeutige Leistungsposition zugeordnet.")
                        .foregroundStyle(.secondary)
                }

                TextField("Gesamtzeit in Stunden", text: $hoursText)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .totalHours)
                    .disabled(isLoading || commission.canEditValue == false)

                if session.timeComponentsEnabled {
                    DisclosureGroup("Zeitbausteine") {
                        hourField("Arbeitszeit vor Ort", text: $workHoursText, field: .workHours)
                        hourField("Wartezeit", text: $waitingHoursText, field: .waitingHours)
                        hourField("Materialbeschaffung", text: $materialHoursText, field: .materialHours)
                        hourField("Fahrt / Wegezeit", text: $travelHoursText, field: .travelHours)
                        hourField("Dokumentation / Rücksprache", text: $documentationHoursText, field: .documentationHours)
                        hourField("Zusatzarbeit", text: $extraHoursText, field: .extraHours)
                    }
                }

                if !session.timeComponentsEnabled,
                   let editingEntry,
                   hasComponents(editingEntry) {
                    Text("Eine Änderung der Gesamtzeit ersetzt die bisherige Aufteilung.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                TextField("Notiz / Erläuterung", text: $note, axis: .vertical)
                    .focused($focusedField, equals: .note)
                    .disabled(isLoading || commission.canEditValue == false)

                Button {
                    focusedField = nil
                    Task {
                        await saveTimeEntry()
                    }
                } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Label(saveButtonTitle, systemImage: "clock.badge.checkmark")
                    }
                }
                .disabled(isSaveDisabled)

                if editingEntry != nil {
                    Button("Bearbeitung abbrechen") {
                        clearTimeInput()
                    }
                    .disabled(isLoading)
                }
            }

            Section("Erfasste Zeiten") {
                if entries.isEmpty {
                    Text("Noch keine Zeiten erfasst.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        timeEntryRow(entry)
                    }
                }
            }
        }
        .refreshForCommissionChanges { await loadEntries(refresh: false) }
        .task {
            await session.loadMobileConfig()
        }
        .refreshWhileActive(id: commission.id, periodicAction: { await loadEntries() }) {
            await loadData()
        }
        .refreshable {
            await session.loadMobileConfig()
            await loadData()
        }
        .onChange(of: session.timeComponentsEnabled) { _, enabled in
            if !enabled {
                useTotalTimeInput()
            }
        }
        .confirmationDialog("Zeiterfassung löschen?", isPresented: Binding(
            get: { entryToDelete != nil },
            set: { newValue in
                if !newValue {
                    entryToDelete = nil
                }
            }
        ), titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                if let entryToDelete {
                    Task {
                        await deleteTimeEntry(entryToDelete)
                    }
                }
            }

            Button("Abbrechen", role: .cancel) {
                entryToDelete = nil
            }
        } message: {
            Text("Diese Zeitposition wird endgültig gelöscht.")
        }
        .alert("Fehler", isPresented: Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
                    errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func timeEntryRow(_ entry: TimeEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.taskTemplate?.title ?? "Zeitbuchung")
                    .font(.headline)

                Spacer()

                Text(WorkTimeText.duration(entry.minutes))
                    .font(.subheadline.bold())
            }

            Text(
                "Leistung: \(Formatters.dateText(entry.serviceDate))"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(entry.user.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)

            if hasComponents(entry) {
                Text(componentSummary(for: entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let note = entry.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
            }

            if canEdit(entry) {
                HStack {
                    Button("Bearbeiten") {
                        beginEditing(entry)
                    }

                    Button("Löschen", role: .destructive) {
                        entryToDelete = entry
                    }
                }
                .font(.caption)
                .buttonStyle(.borderless)
                .disabled(isLoading)
            }
        }
        .padding(.vertical, 4)
    }

    private func hourField(
        _ title: String,
        text: Binding<String>,
        field: InputField
    ) -> some View {
        TextField("\(title) (Std.)", text: text)
            .keyboardType(.decimalPad)
            .focused($focusedField, equals: field)
            .disabled(isLoading || commission.canEditValue == false)
    }
    
    private func loadData() async {
        isLoadingTasks = true

        defer {
            isLoadingTasks = false
        }

        do {
            async let loadedEntries =
                session.apiClient.fetchTimeEntries(
                    commissionId: commission.id,
                    refresh: true
                )
            async let loadedTasks =
                session.apiClient.fetchTimeTasks()

            let result = try await (
                loadedEntries,
                loadedTasks
            )

            entries = result.0
            commissionTasks = (
                commission.matchingTimeTasks(
                    in: result.1
                )
            )
        } catch {
            if error.isRequestCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    private func loadEntries(refresh: Bool = true) async {
        do {
            entries = try await session.apiClient.fetchTimeEntries(commissionId: commission.id, refresh: refresh)
        } catch {
            if error.isRequestCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    private func beginEditing(_ entry: TimeEntry) {
        focusedField = nil
        editingEntry = entry
        serviceDate = (
            Formatters.dateFromApiDate(
                entry.serviceDate
            )
            ?? Date()
        )

        if session.timeComponentsEnabled && hasComponents(entry) {
            hoursText = ""
            workHoursText = hoursText(for: entry.workMinutes)
            waitingHoursText = hoursText(for: entry.waitingMinutes)
            materialHoursText = hoursText(for: entry.materialMinutes)
            travelHoursText = hoursText(for: entry.travelMinutes)
            documentationHoursText = hoursText(for: entry.documentationMinutes)
            extraHoursText = hoursText(for: entry.extraMinutes)
        } else {
            hoursText = WorkTimeText.hoursInput(entry.minutes)
            workHoursText = ""
            waitingHoursText = ""
            materialHoursText = ""
            travelHoursText = ""
            documentationHoursText = ""
            extraHoursText = ""
        }

        note = entry.note ?? ""
    }

    private func saveTimeEntry() async {
        guard let selectedTask else {
            errorMessage = "Diesem Auftrag ist keine eindeutige Leistungsposition zugeordnet."
            return
        }

        let values = parsedTimeInput()
        if values.hasInvalidComponent {
            errorMessage = "Bitte gültige Stunden in den Zeitbausteinen eingeben."
            return
        }

        if values.hasComponentInput && values.componentSum <= 0 {
            errorMessage = "Bitte mindestens einen Zeitbaustein ausfüllen."
            return
        }

        if !values.hasComponentInput && (values.totalMinutes ?? 0) <= 0 {
            errorMessage = session.timeComponentsEnabled
                ? "Bitte eine Gesamtzeit oder Zeitbausteine eingeben."
                : "Bitte eine gültige Gesamtzeit eingeben."
            return
        }

        isLoading = true

        defer {
            isLoading = false
        }

        do {
            if let editingEntry {
                _ = try await session.apiClient.updateTimeEntry(
                    commissionId: commission.id,
                    entryId: editingEntry.id,
                    taskTemplateId: selectedTask.id,
                    serviceDate: Formatters.apiDateText(
                        serviceDate
                    ),
                    minutes: values.hasComponentInput ? nil : values.totalMinutes,
                    workMinutes: values.hasComponentInput ? values.workMinutes : nil,
                    waitingMinutes: values.hasComponentInput ? values.waitingMinutes : nil,
                    materialMinutes: values.hasComponentInput ? values.materialMinutes : nil,
                    travelMinutes: values.hasComponentInput ? values.travelMinutes : nil,
                    documentationMinutes: values.hasComponentInput ? values.documentationMinutes : nil,
                    extraMinutes: values.hasComponentInput ? values.extraMinutes : nil,
                    deviationReason: editingEntry.deviationReason,
                    note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
                )
            } else {
                _ = try await session.apiClient.addTimeEntry(
                    commissionId: commission.id,
                    taskTemplateId: selectedTask.id,
                    serviceDate: Formatters.apiDateText(
                        serviceDate
                    ),
                    minutes: values.hasComponentInput ? nil : values.totalMinutes,
                    workMinutes: values.hasComponentInput ? values.workMinutes : nil,
                    waitingMinutes: values.hasComponentInput ? values.waitingMinutes : nil,
                    materialMinutes: values.hasComponentInput ? values.materialMinutes : nil,
                    travelMinutes: values.hasComponentInput ? values.travelMinutes : nil,
                    documentationMinutes: values.hasComponentInput ? values.documentationMinutes : nil,
                    extraMinutes: values.hasComponentInput ? values.extraMinutes : nil,
                    deviationReason: nil,
                    note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
                )
            }

            clearTimeInput()
            await loadEntries()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteTimeEntry(_ entry: TimeEntry) async {
        isLoading = true

        defer {
            isLoading = false
        }

        do {
            try await session.apiClient.deleteTimeEntry(commissionId: commission.id, entryId: entry.id)

            if editingEntry?.id == entry.id {
                clearTimeInput()
            }

            entryToDelete = nil
            await loadEntries()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func parsedTimeInput() -> ParsedTimeInput {
        let workMinutes = minutesFromHours(workHoursText) ?? 0
        let waitingMinutes = minutesFromHours(waitingHoursText) ?? 0
        let materialMinutes = minutesFromHours(materialHoursText) ?? 0
        let travelMinutes = minutesFromHours(travelHoursText) ?? 0
        let documentationMinutes = minutesFromHours(documentationHoursText) ?? 0
        let extraMinutes = minutesFromHours(extraHoursText) ?? 0
        var hasInvalidComponent = componentTexts.contains { value in
            minutesFromHours(value) == nil
                && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        var componentSum = 0

        for value in [
            workMinutes,
            waitingMinutes,
            materialMinutes,
            travelMinutes,
            documentationMinutes,
            extraMinutes
        ] {
            let result = componentSum.addingReportingOverflow(value)
            hasInvalidComponent = hasInvalidComponent || result.overflow
            componentSum = result.partialValue
        }

        return ParsedTimeInput(
            totalMinutes: minutesFromHours(hoursText),
            hasComponentInput: hasComponentInput,
            hasInvalidComponent: hasInvalidComponent,
            componentSum: componentSum,
            workMinutes: workMinutes,
            waitingMinutes: waitingMinutes,
            materialMinutes: materialMinutes,
            travelMinutes: travelMinutes,
            documentationMinutes: documentationMinutes,
            extraMinutes: extraMinutes
        )
    }
    
    private func useTotalTimeInput() {
        let componentSum = parsedTimeInput().componentSum
        if componentSum > 0 {
            hoursText = WorkTimeText.hoursInput(componentSum)
        }

        workHoursText = ""
        waitingHoursText = ""
        materialHoursText = ""
        travelHoursText = ""
        documentationHoursText = ""
        extraHoursText = ""
    }

    private func minutesFromHours(_ value: String) -> Int? {
        WorkTimeText.minutes(fromHours: value)
    }

    private func hoursText(for value: Int?) -> String {
        guard let value, value > 0 else {
            return ""
        }

        return WorkTimeText.hoursInput(value)
    }

    private func hasComponents(_ entry: TimeEntry) -> Bool {
        let componentValues: [Int?] = [
            entry.workMinutes,
            entry.waitingMinutes,
            entry.materialMinutes,
            entry.travelMinutes,
            entry.documentationMinutes,
            entry.extraMinutes
        ]

        return componentValues.contains { value in
            (value ?? 0) > 0
        }
    }

    private func componentSummary(for entry: TimeEntry) -> String {
        [
            "Arbeit \(WorkTimeText.duration(entry.workMinutes ?? 0))",
            "Warten \(WorkTimeText.duration(entry.waitingMinutes ?? 0))",
            "Material \(WorkTimeText.duration(entry.materialMinutes ?? 0))",
            "Fahrt \(WorkTimeText.duration(entry.travelMinutes ?? 0))",
            "Doku \(WorkTimeText.duration(entry.documentationMinutes ?? 0))",
            "Zusatz \(WorkTimeText.duration(entry.extraMinutes ?? 0))"
        ].joined(separator: " · ")
    }

    private func canEdit(_ entry: TimeEntry) -> Bool {
        commission.canEditValue && entry.canEditValue
    }

    private func clearTimeInput() {
        focusedField = nil
        hoursText = ""
        workHoursText = ""
        waitingHoursText = ""
        materialHoursText = ""
        travelHoursText = ""
        documentationHoursText = ""
        extraHoursText = ""
        note = ""
        editingEntry = nil
        serviceDate = Date()
    }
}

private struct ParsedTimeInput {
    let totalMinutes: Int?
    let hasComponentInput: Bool
    let hasInvalidComponent: Bool
    let componentSum: Int
    let workMinutes: Int
    let waitingMinutes: Int
    let materialMinutes: Int
    let travelMinutes: Int
    let documentationMinutes: Int
    let extraMinutes: Int
}

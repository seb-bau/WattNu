import SwiftUI

struct TimeSectionView: View {
    @EnvironmentObject private var session: SessionStore

    let commission: Commission

    @State private var entries: [TimeEntry] = []
    @State private var taskSearchText = ""
    @State private var selectedTask: TimeTask?
    @State private var taskSuggestions: [TimeTask] = []
    @State private var minutesText = ""
    @State private var workMinutesText = ""
    @State private var waitingMinutesText = ""
    @State private var materialMinutesText = ""
    @State private var travelMinutesText = ""
    @State private var documentationMinutesText = ""
    @State private var extraMinutesText = ""
    @State private var deviationReason = ""
    @State private var note = ""
    @State private var serviceDate = Date()
    @State private var editingEntry: TimeEntry?
    @State private var entryToDelete: TimeEntry?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var suggestionTask: Task<Void, Never>?
    @State private var commissionTasks: [TimeTask] = []

    private let deviationReasons = [
        ("", "Keine Besonderheit"),
        ("waiting", "Wartezeit"),
        ("extra_damage", "Zusätzlicher Schaden"),
        ("difficult_access", "Erschwerte Bedingungen"),
        ("material", "Materialbeschaffung"),
        ("consultation", "Rücksprache"),
        ("other", "Sonstiges")
    ]

    private var formTitle: String {
        editingEntry == nil ? "Zeit erfassen" : "Zeit bearbeiten"
    }

    private var saveButtonTitle: String {
        editingEntry == nil ? "Zeit speichern" : "Änderung speichern"
    }

    private var componentTexts: [String] {
        [
            workMinutesText,
            waitingMinutesText,
            materialMinutesText,
            travelMinutesText,
            documentationMinutesText,
            extraMinutesText
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

        if editingEntry == nil && selectedTask == nil {
            return true
        }

        let hasTotalInput = !minutesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                .disabled(
                    commission.canEditValue == false
                )

                TextField("Position eintippen", text: $taskSearchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(commission.canEditValue == false)

                if let selectedTask {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedTask.title)
                                .font(.headline)

                            Text(selectedTask.code)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let suggestedMinutes = selectedTask.suggestedMinutes, suggestedMinutes > 0 {
                                Text("SOLL-Zeit: \(suggestedMinutes) Min.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Button {
                            clearSelectedTask()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .disabled(commission.canEditValue == false)
                    }
                    .padding(.vertical, 4)
                }

                if !taskSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Vorschläge")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(taskSuggestions) { task in
                            Button {
                                selectTask(task)
                            } label: {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(task.title)
                                            .foregroundStyle(.primary)

                                        Text(task.code)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: "checkmark.circle")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(commission.canEditValue == false)

                            if task.id != taskSuggestions.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                TextField("Gesamtzeit in Minuten", text: $minutesText)
                    .keyboardType(.numberPad)
                    .disabled(commission.canEditValue == false)

                DisclosureGroup("Zeitbausteine") {
                    minuteField("Arbeitszeit vor Ort", text: $workMinutesText)
                    minuteField("Wartezeit", text: $waitingMinutesText)
                    minuteField("Materialbeschaffung", text: $materialMinutesText)
                    minuteField("Fahrt / Wegezeit", text: $travelMinutesText)
                    minuteField("Dokumentation / Rücksprache", text: $documentationMinutesText)
                    minuteField("Zusatzarbeit", text: $extraMinutesText)
                }

                Picker("Grund bei Abweichung", selection: $deviationReason) {
                    ForEach(deviationReasons, id: \.0) { reason in
                        Text(reason.1).tag(reason.0)
                    }
                }
                .disabled(commission.canEditValue == false)

                TextField("Notiz / Erläuterung", text: $note, axis: .vertical)
                    .disabled(commission.canEditValue == false)

                Button {
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
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
        .onChange(of: taskSearchText) { _, newValue in
            handleTaskSearchTextChange(newValue)
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

                Text("\(entry.minutes) Min.")
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

            if let deviationReason = entry.deviationReason, !deviationReason.isEmpty {
                Text(deviationReason)
                    .font(.caption)
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
            }
        }
        .padding(.vertical, 4)
    }

    private func minuteField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .keyboardType(.numberPad)
            .disabled(commission.canEditValue == false)
    }
    
    private func loadData() async {
        do {
            async let loadedEntries =
                session.apiClient.fetchTimeEntries(
                    commissionId: commission.id
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
            restoreTaskSelection()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restoreTaskSelection() {
        guard editingEntry == nil else {
            return
        }

        if commissionTasks.count == 1,
           let task = commissionTasks.first {
            selectTask(task)
        } else if (
            selectedTask == nil
            && taskSearchText.isEmpty
        ) {
            taskSuggestions = commissionTasks
        }
    }

    private func loadEntries() async {
        do {
            entries = try await session.apiClient.fetchTimeEntries(commissionId: commission.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleTaskSearchTextChange(_ value: String) {
        if selectedTask?.title == value || selectedTask?.code == value {
            return
        }

        selectedTask = nil
        scheduleTaskSearch(for: value)
    }

    private func scheduleTaskSearch(for value: String) {
        suggestionTask?.cancel()

        let searchText = value.trimmingCharacters(in: .whitespacesAndNewlines)

        guard searchText.count >= 2 else {
            taskSuggestions = []
            return
        }

        suggestionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)

            if Task.isCancelled {
                return
            }

            do {
                let items = try await session.apiClient.searchTimeTasks(query: searchText)

                if Task.isCancelled {
                    return
                }

                taskSuggestions = items
            } catch {
                if Task.isCancelled {
                    return
                }

                taskSuggestions = []
            }
        }
    }

    private func selectTask(_ task: TimeTask) {
        suggestionTask?.cancel()
        selectedTask = task
        taskSuggestions = []
        taskSearchText = task.title
    }

    private func clearSelectedTask() {
        suggestionTask?.cancel()
        selectedTask = nil
        taskSearchText = ""
        taskSuggestions = []
    }

    private func beginEditing(_ entry: TimeEntry) {
        editingEntry = entry
        serviceDate = (
            Formatters.dateFromApiDate(
                entry.serviceDate
            )
            ?? Date()
        )
        suggestionTask?.cancel()
        selectedTask = entry.taskTemplate
        taskSuggestions = []
        taskSearchText = entry.taskTemplate?.title ?? ""

        if hasComponents(entry) {
            minutesText = ""
            workMinutesText = minutesText(for: entry.workMinutes)
            waitingMinutesText = minutesText(for: entry.waitingMinutes)
            materialMinutesText = minutesText(for: entry.materialMinutes)
            travelMinutesText = minutesText(for: entry.travelMinutes)
            documentationMinutesText = minutesText(for: entry.documentationMinutes)
            extraMinutesText = minutesText(for: entry.extraMinutes)
        } else {
            minutesText = "\(entry.minutes)"
            workMinutesText = ""
            waitingMinutesText = ""
            materialMinutesText = ""
            travelMinutesText = ""
            documentationMinutesText = ""
            extraMinutesText = ""
        }

        deviationReason = entry.deviationReason ?? ""
        note = entry.note ?? ""
    }

    private func saveTimeEntry() async {
        if editingEntry == nil && selectedTask == nil {
            errorMessage = "Bitte zuerst eine Position auswählen."
            return
        }

        let values = parsedTimeInput()
        if values.hasInvalidComponent {
            errorMessage = "Bitte gültige Minuten in den Zeitbausteinen eingeben."
            return
        }

        if values.hasComponentInput && values.componentSum <= 0 {
            errorMessage = "Bitte mindestens einen Zeitbaustein ausfüllen."
            return
        }

        if !values.hasComponentInput && (values.totalMinutes ?? 0) <= 0 {
            errorMessage = "Bitte eine Gesamtzeit oder Zeitbausteine eingeben."
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
                    taskTemplateId: selectedTask?.id,
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
                    deviationReason: deviationReason.isEmpty ? nil : deviationReason,
                    note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
                )
            } else {
                _ = try await session.apiClient.addTimeEntry(
                    commissionId: commission.id,
                    taskTemplateId: selectedTask?.id,
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
                    deviationReason: deviationReason.isEmpty ? nil : deviationReason,
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
        let workMinutes = integerValue(workMinutesText) ?? 0
        let waitingMinutes = integerValue(waitingMinutesText) ?? 0
        let materialMinutes = integerValue(materialMinutesText) ?? 0
        let travelMinutes = integerValue(travelMinutesText) ?? 0
        let documentationMinutes = integerValue(documentationMinutesText) ?? 0
        let extraMinutes = integerValue(extraMinutesText) ?? 0
        let hasInvalidComponent = componentTexts.contains { value in
            integerValue(value) == nil && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let componentSum = workMinutes + waitingMinutes + materialMinutes + travelMinutes + documentationMinutes + extraMinutes

        return ParsedTimeInput(
            totalMinutes: integerValue(minutesText),
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

    private func integerValue(_ value: String) -> Int? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedValue.isEmpty {
            return nil
        }
        return Int(trimmedValue)
    }

    private func minutesText(for value: Int?) -> String {
        guard let value, value > 0 else {
            return ""
        }

        return "\(value)"
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
        let workMinutes = entry.workMinutes ?? 0
        let waitingMinutes = entry.waitingMinutes ?? 0
        let materialMinutes = entry.materialMinutes ?? 0
        let travelMinutes = entry.travelMinutes ?? 0
        let documentationMinutes = entry.documentationMinutes ?? 0
        let extraMinutes = entry.extraMinutes ?? 0

        return "Arbeit \(workMinutes) · Warten \(waitingMinutes) · Material \(materialMinutes) · Fahrt \(travelMinutes) · Doku \(documentationMinutes) · Zusatz \(extraMinutes)"
    }

    private func canEdit(_ entry: TimeEntry) -> Bool {
        commission.canEditValue && entry.canEditValue
    }

    private func clearTimeInput() {
        minutesText = ""
        workMinutesText = ""
        waitingMinutesText = ""
        materialMinutesText = ""
        travelMinutesText = ""
        documentationMinutesText = ""
        extraMinutesText = ""
        deviationReason = ""
        note = ""
        editingEntry = nil
        serviceDate = Date()
        clearSelectedTask()
        restoreTaskSelection()
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

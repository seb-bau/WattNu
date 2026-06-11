import SwiftUI

struct TimeSectionView: View {
    @EnvironmentObject private var session: SessionStore

    let commission: Commission

    @State private var entries: [TimeEntry] = []
    @State private var taskSearchText = ""
    @State private var selectedTask: TimeTask?
    @State private var taskSuggestions: [TimeTask] = []
    @State private var minutesText = ""
    @State private var note = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var suggestionTask: Task<Void, Never>?

    var body: some View {
        List {
            Section("Zeit erfassen") {
                if commission.canEditValue == false {
                    Text("Zeiten sind für Kollegenaufträge nur lesend verfügbar.")
                        .foregroundStyle(.secondary)
                }

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

                TextField("Minuten", text: $minutesText)
                    .keyboardType(.numberPad)
                    .disabled(commission.canEditValue == false)

                TextField("Notiz", text: $note, axis: .vertical)
                    .disabled(commission.canEditValue == false)

                Button {
                    Task {
                        await addTimeEntry()
                    }
                } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Label("Zeit speichern", systemImage: "clock.badge.checkmark")
                    }
                }
                .disabled(selectedTask == nil || minutesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading || commission.canEditValue == false)
            }

            Section("Erfasste Zeiten") {
                if entries.isEmpty {
                    Text("Noch keine Zeiten erfasst.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(entry.taskTemplate?.title ?? "Zeitbuchung")
                                    .font(.headline)

                                Spacer()

                                Text("\(entry.minutes) Min.")
                                    .font(.subheadline.bold())
                            }

                            HStack {
                                Text(entry.reviewStatusLabel)
                                Spacer()
                                Text(Formatters.dateTimeText(entry.createdAt))
                            }
                            .font(.caption)
                            .foregroundStyle(entry.reviewStatus == "needs_review" ? .orange : .secondary)

                            Text(entry.user.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let note = entry.note, !note.isEmpty {
                                Text(note)
                                    .font(.caption)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .task {
            await loadEntries()
        }
        .refreshable {
            await loadEntries()
        }
        .onChange(of: taskSearchText) { _, newValue in
            handleTaskSearchTextChange(newValue)
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

    private func addTimeEntry() async {
        guard let selectedTask else {
            errorMessage = "Bitte zuerst eine Position auswählen."
            return
        }

        guard let minutes = Int(minutesText), minutes > 0 else {
            errorMessage = "Bitte gültige Minuten eingeben."
            return
        }

        isLoading = true

        defer {
            isLoading = false
        }

        do {
            _ = try await session.apiClient.addTimeEntry(
                commissionId: commission.id,
                taskTemplateId: selectedTask.id,
                minutes: minutes,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
            )

            minutesText = ""
            note = ""
            clearSelectedTask()

            await loadEntries()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

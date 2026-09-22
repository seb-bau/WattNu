import SwiftUI

struct MyTimeView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var selectedDate =
        Calendar.current.startOfDay(for: Date())
    @State private var summary: MyTimeDay?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isEditorPresented = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && summary == nil {
                    ProgressView(
                        "Zeiten werden geladen …"
                    )
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
                } else {
                    List {
                        Section {
                            HStack(spacing: 12) {
                                Button {
                                    moveDate(by: -1)
                                } label: {
                                    Image(
                                        systemName: "chevron.left"
                                    )
                                }
                                .buttonStyle(.borderless)

                                DatePicker(
                                    "Tag",
                                    selection: $selectedDate,
                                    displayedComponents: .date
                                )
                                .labelsHidden()
                                .frame(
                                    maxWidth: .infinity
                                )

                                Button {
                                    moveDate(by: 1)
                                } label: {
                                    Image(
                                        systemName: "chevron.right"
                                    )
                                }
                                .buttonStyle(.borderless)
                            }

                            if !Calendar.current.isDateInToday(
                                selectedDate
                            ) {
                                Button("Heute anzeigen") {
                                    selectedDate =
                                        Calendar.current
                                        .startOfDay(
                                            for: Date()
                                        )
                                }
                            }
                        }

                        if let summary {
                            Section("Tagesübersicht") {
                                summaryView(summary)
                            }

                            Section("Erfasste Zeiten") {
                                if summary.items.isEmpty {
                                    ContentUnavailableView(
                                        "Keine Zeiten",
                                        systemImage: "clock",
                                        description: Text(
                                            "Für diesen Tag wurden noch keine Zeiten erfasst."
                                        )
                                    )
                                } else {
                                    ForEach(
                                        summary.items
                                    ) { entry in
                                        entryRow(entry)
                                    }
                                }
                            }
                        }
                    }
                    .refreshable {
                        await loadSummary()
                    }
                }
            }
            .navigationTitle("Zeiten")
            .toolbar {
                ToolbarItem(
                    placement: .topBarTrailing
                ) {
                    Button {
                        isEditorPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(
                        "Freie Zeit erfassen"
                    )
                }
            }
            .task {
                await loadSummary()
            }
            .onChange(of: selectedDate) { _, _ in
                Task {
                    await loadSummary()
                }
            }
            .sheet(
                isPresented: $isEditorPresented
            ) {
                NavigationStack {
                    FreeTimeEntryFormView(
                        initialDate: selectedDate
                    ) { savedDate in
                        isEditorPresented = false
                        selectedDate = savedDate

                        Task {
                            await loadSummary()
                        }
                    }
                }
                .environmentObject(session)
            }
            .alert(
                "Fehler",
                isPresented: Binding(
                    get: {
                        errorMessage != nil
                    },
                    set: { newValue in
                        if !newValue {
                            errorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func summaryView(
        _ summary: MyTimeDay
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                valueCard(
                    title: "SOLL",
                    value: summary.expectedMinutes.map {
                        WorkTimeText.duration($0)
                    } ?? "Kein Profil"
                )

                valueCard(
                    title: "Erfasst",
                    value: WorkTimeText.duration(
                        summary.recordedMinutes
                    )
                )
            }

            HStack {
                if let difference =
                    summary.differenceMinutes
                {
                    Text(
                        "Differenz: \(WorkTimeText.signedDuration(difference))"
                    )
                    .font(
                        .subheadline.weight(.semibold)
                    )
                }

                Spacer()

                Text(summary.statusLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        summary.statusColor
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        summary.statusColor.opacity(0.14)
                    )
                    .clipShape(Capsule())
            }

            if let profile = summary.profile {
                Text("Profil: \(profile.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let targetOverride =
                summary.targetOverride
            {
                Label(
                    targetOverride.reason,
                    systemImage:
                        "calendar.badge.exclamationmark"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func valueCard(
        title: String,
        value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.headline)
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding(12)
        .background(
            Color(
                .secondarySystemGroupedBackground
            )
        )
        .clipShape(
            RoundedRectangle(cornerRadius: 12)
        )
    }

    private func entryRow(
        _ entry: MyTimeEntry
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(
                    entry.taskTemplate?.title
                    ?? "Keine Leistungsposition"
                )
                .font(.headline)

                Spacer()

                Text(
                    WorkTimeText.duration(
                        entry.minutes
                    )
                )
                .font(
                    .subheadline.weight(.semibold)
                )
            }

            if let commission = entry.commission {
                Text(
                    "Auftrag \(commission.number) · \(commission.title)"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Label(
                    "Freie Zeit",
                    systemImage: "plus.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let note = entry.note,
               !note.isEmpty
            {
                Text(note)
                    .font(.caption)
            }
        }
        .padding(.vertical, 3)
    }

    private func moveDate(by value: Int) {
        selectedDate = Calendar.current.date(
            byAdding: .day,
            value: value,
            to: selectedDate
        ) ?? selectedDate
    }

    private func loadSummary() async {
        guard !Task.isCancelled else {
            return
        }

        isLoading = true

        defer {
            isLoading = false
        }

        do {
            summary = try await session.apiClient
                .fetchMyTime(
                    date: selectedDate
                )
        } catch {
            if error.isRequestCancellation {
                return
            }

            errorMessage = error.localizedDescription
        }
    }
}


private struct FreeTimeEntryFormView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    let onSaved: (Date) -> Void

    @State private var tasks: [TimeTask] = []
    @State private var selectedTaskId: Int?
    @State private var serviceDate: Date
    @State private var minutesText = ""
    @State private var note = ""
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        initialDate: Date,
        onSaved: @escaping (Date) -> Void
    ) {
        self.onSaved = onSaved
        _serviceDate = State(
            initialValue: initialDate
        )
    }

    var body: some View {
        Form {
            if isLoading {
                ProgressView(
                    "Leistungspositionen werden geladen …"
                )
            } else if tasks.isEmpty {
                ContentUnavailableView(
                    "Keine freie Leistungsposition",
                    systemImage:
                        "list.bullet.clipboard",
                    description: Text(
                        "Im Backend muss mindestens eine Leistungsposition für freie Zeiten freigegeben werden."
                    )
                )
            } else {
                Section("Freie Zeit") {
                    Picker(
                        "Leistungsposition",
                        selection: $selectedTaskId
                    ) {
                        Text("Bitte auswählen")
                            .tag(nil as Int?)

                        ForEach(tasks) { task in
                            Text(task.title)
                                .tag(task.id as Int?)
                        }
                    }

                    DatePicker(
                        "Leistungsdatum",
                        selection: $serviceDate,
                        displayedComponents: .date
                    )

                    TextField(
                        "Minuten",
                        text: $minutesText
                    )
                    .keyboardType(.numberPad)

                    TextField(
                        "Notiz (optional)",
                        text: $note,
                        axis: .vertical
                    )
                    .lineLimit(2...5)
                }
            }
        }
        .navigationTitle("Freie Zeit erfassen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(
                placement: .cancellationAction
            ) {
                Button("Abbrechen") {
                    dismiss()
                }
            }

            ToolbarItem(
                placement: .confirmationAction
            ) {
                Button("Speichern") {
                    Task {
                        await save()
                    }
                }
                .disabled(
                    selectedTaskId == nil
                    || parsedMinutes == nil
                    || isSaving
                )
            }
        }
        .task {
            await loadTasks()
        }
        .alert(
            "Fehler",
            isPresented: Binding(
                get: {
                    errorMessage != nil
                },
                set: { newValue in
                    if !newValue {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var parsedMinutes: Int? {
        guard let value = Int(
            minutesText.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        ), 1...1440 ~= value else {
            return nil
        }

        return value
    }

    private func loadTasks() async {
        isLoading = true

        defer {
            isLoading = false
        }

        do {
            tasks = try await session.apiClient
                .fetchFreeTimeTasks()

            if tasks.count == 1 {
                selectedTaskId = tasks[0].id
            }
        } catch {
            if error.isRequestCancellation {
                return
            }

            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        guard let selectedTaskId,
              let parsedMinutes
        else {
            errorMessage = (
                "Bitte Leistungsposition und gültige "
                + "Minuten angeben."
            )
            return
        }

        isSaving = true

        defer {
            isSaving = false
        }

        do {
            _ = try await session.apiClient
                .addFreeTimeEntry(
                    taskTemplateId: selectedTaskId,
                    serviceDate: serviceDate,
                    minutes: parsedMinutes,
                    note: note
                )

            onSaved(serviceDate)
        } catch {
            if error.isRequestCancellation {
                return
            }

            errorMessage = error.localizedDescription
        }
    }
}


private enum WorkTimeText {
    static func duration(
        _ minutes: Int
    ) -> String {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours == 0 {
            return "\(remainingMinutes) Min."
        }

        if remainingMinutes == 0 {
            return "\(hours) Std."
        }

        return (
            "\(hours) Std. "
            + "\(remainingMinutes) Min."
        )
    }

    static func signedDuration(
        _ minutes: Int
    ) -> String {
        let prefix = minutes >= 0 ? "+" : "−"
        return prefix + duration(abs(minutes))
    }
}


private extension MyTimeDay {
    var statusLabel: String {
        switch status {
        case "complete":
            return "SOLL erfüllt"
        case "missing":
            return "Stunden fehlen"
        case "missing_profile":
            return "Kein Profil"
        case "not_evaluated":
            return "Noch nicht bewertet"
        default:
            return status
        }
    }

    var statusColor: Color {
        switch status {
        case "complete":
            return .green
        case "missing":
            return .red
        case "not_evaluated":
            return .secondary
        default:
            return .orange
        }
    }
}

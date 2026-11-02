import SwiftUI

enum InspectionVisitFilter: String, CaseIterable, Identifiable {
    case all
    case noAccess
    case followUps
    case due

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            return "Alle Prüfungen"
        case .noAccess:
            return "Kein Zugang"
        case .followUps:
            return "Mit Wiedervorlage"
        case .due:
            return "Wiedervorlage bis heute"
        }
    }

    func matches(
        _ job: SafetyInspectionJob,
        today: String
    ) -> Bool {
        if self == .all { return true }
        guard job.isOpenInspection else { return false }

        switch self {
        case .all:
            return true
        case .noAccess:
            return job.visit?.blocked == true
        case .followUps:
            return job.visit?.followUpOn != nil
        case .due:
            guard let date = job.visit?.followUpOn else {
                return false
            }
            return date <= today
        }
    }
}

enum InspectionVisitMode: Equatable {
    case noAccess
    case followUp

    var title: String {
        self == .noAccess
            ? "Kein Zugang"
            : "Wiedervorlage festlegen"
    }
}

struct InspectionVisitTarget: Identifiable {
    let id = UUID()
    let jobs: [SafetyInspectionJob]
    let title: String
    let mode: InspectionVisitMode
}

struct InspectionVisitBadge: View {
    let job: SafetyInspectionJob
    var showDetails = false

    var body: some View {
        if let label = job.visitLabel {
            VStack(alignment: .leading, spacing: 4) {
                Label(
                    label,
                    systemImage: job.visit?.blocked == true
                        ? "door.left.hand.closed"
                        : "calendar"
                )
                .font(.caption)
                .foregroundStyle(
                    job.visit?.blocked == true
                        ? Color.orange
                        : Color.blue
                )

                if showDetails, let visit = job.visit {
                    if let note = visit.note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(
                        "Vermerkt am \(Formatters.dateTimeText(visit.occurredAt))"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

@MainActor
struct SafetyInspectionVisitView: View {
    @EnvironmentObject private var inspections: SafetyInspectionOfflineStore
    @Environment(\.dismiss) private var dismiss

    let target: InspectionVisitTarget
    let onSaved: () -> Void

    @State private var note = ""
    @State private var useFollowUp = true
    @State private var followUpDate = Calendar.current.date(
        byAdding: .day,
        value: 1,
        to: Date()
    ) ?? Date()
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var canSave: Bool {
        let text = note.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return !text.isEmpty
            && text.unicodeScalars.count <= 2000
            && !target.jobs.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(target.title)
                        .font(.headline)

                    Text(
                        "Betrifft \(target.jobs.count) offene, bearbeitbare Prüfungen."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Section("Grund") {
                    TextField(
                        "Was hat die Prüfung verhindert?",
                        text: $note,
                        axis: .vertical
                    )
                    .lineLimit(3...8)

                    if note.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).unicodeScalars.count > 2000 {
                        Text(
                            "Bitte den Grund auf höchstens 2000 Zeichen kürzen."
                        )
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                }

                Section {
                    if target.mode == .noAccess {
                        Toggle(
                            "Wiedervorlage festlegen",
                            isOn: $useFollowUp
                        )
                    }

                    if useFollowUp || target.mode == .followUp {
                        DatePicker(
                            "Wiedervorlage am",
                            selection: $followUpDate,
                            in: Calendar.current.startOfDay(
                                for: Date()
                            )...,
                            displayedComponents: .date
                        )
                    }
                } footer: {
                    Text(
                        "Die Prüfungen bleiben offen. Die Prüffrist wird nicht verändert."
                    )

                    if target.mode == .followUp {
                        Text(
                            "Ein bestehender Zugangsvermerk bleibt erhalten."
                        )
                    }
                }
            }
            .disabled(isSaving)
            .navigationTitle(target.mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                        .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                        .disabled(!canSave || isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .alert(
                "Vermerk nicht gespeichert",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
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

    private func save() {
        guard canSave, !isSaving else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            try inspections.recordVisit(
                jobIds: target.jobs.map(\.id),
                blocked: target.mode == .noAccess ? true : nil,
                note: note,
                followUpOn: useFollowUp || target.mode == .followUp
                    ? Formatters.apiDateText(followUpDate)
                    : nil
            )

            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

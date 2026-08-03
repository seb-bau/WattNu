import SwiftUI

struct CommissionCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore

    let onCreated: () -> Void

    @State private var options: CommissionCreateOptions?
    @State private var tasks: [TimeTask] = []
    @State private var selectedCompanyCode = ""
    @State private var selectedCommissionTypeId = 0
    @State private var useUnitIdNum = ""
    @State private var buildingIdNum = ""
    @State private var licenseAgreementIdNum = ""
    @State private var title = ""
    @State private var damageLocation = ""
    @State private var contactPerson = ""
    @State private var hasExecutionPeriod = false
    @State private var executionFrom = Date()
    @State private var executionTo = Date()
        .addingTimeInterval(60 * 60)
    @State private var positions = [
        DraftCommissionPosition()
    ]
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var companyCodes: [CompanyCodeOption] {
        options?.companyCodes ?? []
    }

    private var commissionTypes: [CommissionTypeOption] {
        options?.commissionTypes ?? []
    }

    private var canSubmit: Bool {
        guard !isLoading,
              !isSaving,
              selectedCompanyCode.isEmpty == false,
              selectedCommissionTypeId != 0,
              options?.canCreate == true else {
            return false
        }

        let hasReference = [
            useUnitIdNum,
            buildingIdNum,
            licenseAgreementIdNum,
        ].contains {
            normalizedText($0) != nil
        }

        guard hasReference else {
            return false
        }

        if hasExecutionPeriod
            && executionTo < executionFrom {
            return false
        }

        return positions.isEmpty == false
            && positions.allSatisfy { position in
                position.task?.serviceCatalogId != nil
                    && normalizedText(
                        position.commissionText
                    ) != nil
                    && parsedQuantity(
                        position.quantity
                    ).map { $0 > 0 } == true
            }
    }

    var body: some View {
        Form {
            Section("Zuordnung") {
                Picker(
                    "Buchwerk",
                    selection: $selectedCompanyCode
                ) {
                    Text("Bitte auswählen")
                        .tag("")

                    ForEach(companyCodes) { item in
                        Text(item.displayName)
                            .tag(item.code)
                    }
                }

                Picker(
                    "Auftragsart",
                    selection: $selectedCommissionTypeId
                ) {
                    Text("Bitte auswählen")
                        .tag(0)

                    ForEach(commissionTypes) { item in
                        Text(item.displayName)
                            .tag(item.id)
                    }
                }

                LabeledContent(
                    "Handwerker",
                    value: session.user?.displayName ?? "-"
                )
            }

            Section("Objektbezug") {
                TextField(
                    "Nutzungseinheitsnummer (IdNum)",
                    text: $useUnitIdNum
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                TextField(
                    "Gebäudenummer (IdNum)",
                    text: $buildingIdNum
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                TextField(
                    "Mietvertragsnummer (IdNum)",
                    text: $licenseAgreementIdNum
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Text(
                    "Mindestens eine der drei fachlichen Nummern ist erforderlich."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Auftrag") {
                TextField(
                    "Kurztitel",
                    text: $title
                )

                TextField(
                    "Schadensort",
                    text: $damageLocation
                )

                TextField(
                    "Ansprechpartner vor Ort",
                    text: $contactPerson
                )
            }

            Section("Ausführungszeitraum") {
                Toggle(
                    "Ausführungszeitraum angeben",
                    isOn: $hasExecutionPeriod
                )

                if hasExecutionPeriod {
                    DatePicker(
                        "Von",
                        selection: $executionFrom
                    )

                    DatePicker(
                        "Bis",
                        selection: $executionTo
                    )

                    if executionTo < executionFrom {
                        Text(
                            "Das Ende darf nicht vor dem Beginn liegen."
                        )
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                }
            }

            Section {
                ForEach($positions) { $position in
                    CommissionPositionEditor(
                        position: $position,
                        tasks: tasks,
                        canRemove: positions.count > 1,
                        removeAction: {
                            removePosition(
                                id: position.id
                            )
                        }
                    )
                }

                Button {
                    positions.append(
                        DraftCommissionPosition()
                    )
                } label: {
                    Label(
                        "Position hinzufügen",
                        systemImage: "plus"
                    )
                }
            } header: {
                Text("Auftragspositionen")
            } footer: {
                Text(
                    "Für jede Position muss eine Wowiport-Leistungsposition ausgewählt werden."
                )
            }
        }
        .navigationTitle("Auftrag erfassen")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isSaving)
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
                Button("Erfassen") {
                    Task {
                        await submit()
                    }
                }
                .disabled(!canSubmit)
            }
        }
        .overlay {
            if isLoading || isSaving {
                ProgressView(
                    isSaving
                    ? "Auftrag wird erfasst …"
                    : "Daten werden geladen …"
                )
                .padding()
                .background(.regularMaterial)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 14
                    )
                )
            }
        }
        .task {
            await loadData()
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
            Button(
                "OK",
                role: .cancel
            ) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadData() async {
        isLoading = true

        defer {
            isLoading = false
        }

        do {
            async let loadedOptions = session.apiClient
                .fetchCommissionCreateOptions()
            async let loadedTasks = session.apiClient
                .fetchTimeTasks()

            let result = try await (
                loadedOptions,
                loadedTasks
            )

            options = result.0
            tasks = result.1.filter {
                $0.serviceCatalogId != nil
            }

            if selectedCompanyCode.isEmpty {
                selectedCompanyCode = result.0
                    .companyCodes
                    .first?
                    .code ?? ""
            }

            if selectedCommissionTypeId == 0 {
                selectedCommissionTypeId = result.0
                    .commissionTypes
                    .first?
                    .id ?? 0
            }

            if !result.0.canCreate {
                errorMessage = """
                Deinem Benutzer ist keine Wowiport-Handwerker-ID zugeordnet.
                """
            } else if result.0.companyCodes.isEmpty {
                errorMessage = """
                Es sind keine Buchwerke verfügbar.
                """
            } else if result.0.commissionTypes.isEmpty {
                errorMessage = """
                Es sind keine freigegebenen Auftragsarten verfügbar.
                """
            } else if tasks.isEmpty {
                errorMessage = """
                Es sind keine Wowiport-Leistungspositionen für deine Gewerke verfügbar.
                """
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submit() async {
        guard canSubmit else {
            errorMessage = """
            Bitte alle erforderlichen Angaben prüfen.
            """
            return
        }

        var positionRequests: [CommissionPositionRequest] = []

        for position in positions {
            guard let task = position.task,
                  let serviceCatalogId = task.serviceCatalogId,
                  let commissionText = normalizedText(
                    position.commissionText
                  ),
                  let quantity = parsedQuantity(
                    position.quantity
                  ),
                  quantity > 0 else {
                errorMessage = """
                Mindestens eine Auftragsposition ist unvollständig.
                """
                return
            }

            positionRequests.append(
                CommissionPositionRequest(
                    code: normalizedText(task.code),
                    commissionText: commissionText,
                    internalDescription: normalizedText(
                        position.internalDescription
                    ),
                    units: quantity,
                    serviceCatalogId: serviceCatalogId
                )
            )
        }

        let request = CommissionCreateRequest(
            companyCodeCode: selectedCompanyCode,
            commissionTypeId: selectedCommissionTypeId,
            useUnitIdNum: normalizedText(
                useUnitIdNum
            ),
            buildingIdNum: normalizedText(
                buildingIdNum
            ),
            licenseAgreementIdNum: normalizedText(
                licenseAgreementIdNum
            ),
            title: normalizedText(title),
            damageLocation: normalizedText(
                damageLocation
            ),
            contactPerson: normalizedText(
                contactPerson
            ),
            executionFrom: hasExecutionPeriod
                ? formattedDate(executionFrom)
                : nil,
            executionTo: hasExecutionPeriod
                ? formattedDate(executionTo)
                : nil,
            positions: positionRequests
        )

        isSaving = true

        defer {
            isSaving = false
        }

        do {
            _ = try await session.apiClient
                .createCommission(
                    body: request
                )

            onCreated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removePosition(id: UUID) {
        guard positions.count > 1 else {
            return
        }

        positions.removeAll {
            $0.id == id
        }
    }

    private func normalizedText(
        _ value: String
    ) -> String? {
        let result = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return result.isEmpty ? nil : result
    }

    private func parsedQuantity(
        _ value: String
    ) -> Double? {
        Double(
            value.replacingOccurrences(
                of: ",",
                with: "."
            )
        )
    }

    private func formattedDate(
        _ value: Date
    ) -> String {
        ISO8601DateFormatter()
            .string(from: value)
    }
}

struct DraftCommissionPosition: Identifiable {
    let id = UUID()
    var task: TimeTask?
    var commissionText = ""
    var internalDescription = ""
    var quantity = "1"
}

struct CommissionPositionEditor: View {
    @Binding var position: DraftCommissionPosition

    let tasks: [TimeTask]
    let canRemove: Bool
    let removeAction: () -> Void

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            NavigationLink {
                TimeTaskSelectionView(
                    tasks: tasks,
                    selectedTaskId: position.task?.id
                ) { task in
                    position.task = task

                    if position.commissionText
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        .isEmpty {
                        position.commissionText = task.title
                    }
                }
            } label: {
                LabeledContent("Leistung") {
                    Text(
                        position.task.map {
                            "\($0.code) · \($0.title)"
                        } ?? "Auswählen"
                    )
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(
                        position.task == nil
                        ? .secondary
                        : .primary
                    )
                }
            }

            if let craftActivity = position
                .task?
                .craftActivity {
                LabeledContent(
                    "Gewerk",
                    value: craftActivity.name
                    ?? craftActivity.code
                    ?? "-"
                )
            }

            TextField(
                "Auftragstext",
                text: $position.commissionText,
                axis: .vertical
            )
            .lineLimit(2...6)

            TextField(
                "Interne Beschreibung",
                text: $position.internalDescription,
                axis: .vertical
            )
            .lineLimit(2...6)

            TextField(
                "Menge",
                text: $position.quantity
            )
            .keyboardType(.decimalPad)

            if canRemove {
                Button(
                    role: .destructive,
                    action: removeAction
                ) {
                    Label(
                        "Position entfernen",
                        systemImage: "trash"
                    )
                }
            }
        }
        .padding(.vertical, 6)
    }
}

struct TimeTaskSelectionView: View {
    @Environment(\.dismiss) private var dismiss

    let tasks: [TimeTask]
    let selectedTaskId: Int?
    let selectionAction: (TimeTask) -> Void

    @State private var searchText = ""

    private var filteredTasks: [TimeTask] {
        let query = searchText
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .lowercased()

        guard !query.isEmpty else {
            return tasks
        }

        return tasks.filter { task in
            task.code.lowercased().contains(query)
                || task.title.lowercased().contains(query)
                || (
                    task.erpIdNum ?? ""
                ).lowercased().contains(query)
                || (
                    task.craftActivity?.code ?? ""
                ).lowercased().contains(query)
                || (
                    task.craftActivity?.name ?? ""
                ).lowercased().contains(query)
        }
    }

    var body: some View {
        List(filteredTasks) { task in
            Button {
                selectionAction(task)
                dismiss()
            } label: {
                HStack(
                    alignment: .top,
                    spacing: 10
                ) {
                    VStack(
                        alignment: .leading,
                        spacing: 4
                    ) {
                        Text(task.title)
                            .foregroundStyle(.primary)

                        Text(task.code)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let craftName = task
                            .craftActivity?
                            .name {
                            Text(craftName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if selectedTaskId == task.id {
                        Image(
                            systemName: "checkmark"
                        )
                        .foregroundStyle(.tint)
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Leistung auswählen")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            prompt: "Leistung suchen"
        )
    }
}

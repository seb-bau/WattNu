import SwiftUI

struct CommissionCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore

    let onCreated: () -> Void

    @State private var options: CommissionCreateOptions?
    @State private var tasks: [TimeTask] = []
    @State private var selectedCommissionTypeId = 0
    @State private var objectSearchText = ""
    @State private var objectSearchResults: [CommissionObjectChoice] = []
    @State private var selectedObject: CommissionObjectChoice?
    @State private var isSearchingObjects = false
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

    private var commissionTypes: [CommissionTypeOption] {
        options?.commissionTypes ?? []
    }

    private var canSubmit: Bool {
        guard !isLoading,
              !isSaving,
              selectedObject != nil,
              selectedCommissionTypeId != 0,
              options?.canCreate == true else {
            return false
        }

        if hasExecutionPeriod
            && executionTo < executionFrom {
            return false
        }

        let craftActivityIds = Set(
            positions.compactMap {
                $0.task?.craftActivity?.id
            }
        )

        return craftActivityIds.count == 1
            && positions.isEmpty == false
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

                Text(
                    "Handwerker und Buchwerk werden automatisch aus Objekt, Gewerk und Wowiport-Zuständigkeit ermittelt."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Objektbezug") {
                HStack {
                    TextField(
                        "Mieter, Vertrag oder Adresse",
                        text: $objectSearchText
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit {
                        Task {
                            await searchObjects()
                        }
                    }

                    Button {
                        Task {
                            await searchObjects()
                        }
                    } label: {
                        if isSearchingObjects {
                            ProgressView()
                        } else {
                            Image(
                                systemName: "magnifyingglass"
                            )
                        }
                    }
                    .disabled(
                        isSearchingObjects
                        || objectSearchText
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            .count < 2
                    )
                }

                ForEach(objectSearchResults) { item in
                    Button {
                        selectObject(item)
                    } label: {
                        VStack(
                            alignment: .leading,
                            spacing: 4
                        ) {
                            Text(item.label)
                                .foregroundStyle(.primary)

                            Text(
                                objectDescription(item)
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(
                                .leading
                            )
                        }
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let selectedObject {
                    SelectedCommissionObjectView(
                        item: selectedObject
                    )
                } else {
                    Text(
                        "Es kann ein Mietvertrag, ein Leerstand, eine Nutzungseinheit ohne Vertrag oder direkt ein Gebäude gewählt werden."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
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
                        tasks: compatibleTasks,
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
                    "Alle Positionen müssen demselben Gewerk angehören."
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
                .fetchCommissionCreateTasks()

            let result = try await (
                loadedOptions,
                loadedTasks
            )

            options = result.0
            tasks = result.1.filter {
                $0.serviceCatalogId != nil
            }

            if selectedCommissionTypeId == 0 {
                selectedCommissionTypeId = result.0
                    .commissionTypes
                    .first?
                    .id ?? 0
            }

            if !result.0.canCreate {
                errorMessage = """
                Die automatische Auftragszuordnung ist noch nicht vollständig konfiguriert.
                """
            } else if result.0.commissionTypes.isEmpty {
                errorMessage = """
                Es sind keine freigegebenen Auftragsarten verfügbar.
                """
            } else if tasks.isEmpty {
                errorMessage = """
                Es sind keine Leistungspositionen mit Gewerk-Zuständigkeit verfügbar.
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

        guard let selectedObject else {
            errorMessage = "Bitte ein Objekt auswählen."
            return
        }

        let request = CommissionCreateRequest(
            objectType: selectedObject.objectType,
            objectId: selectedObject.objectId,
            commissionTypeId: selectedCommissionTypeId,
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

    private func searchObjects() async {
        let query = objectSearchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard query.count >= 2 else {
            objectSearchResults = []
            return
        }

        isSearchingObjects = true

        defer {
            isSearchingObjects = false
        }

        do {
            objectSearchResults = try await session.apiClient
                .searchCommissionObjects(
                    query: query
                )
        } catch {
            objectSearchResults = []
            errorMessage = error.localizedDescription
        }
    }

    private func selectObject(
        _ item: CommissionObjectChoice
    ) {
        selectedObject = item
        objectSearchResults = []

        if contactPerson.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty,
           let tenantName = item.tenantName {
            contactPerson = tenantName
        }
    }

    private func objectDescription(
        _ item: CommissionObjectChoice
    ) -> String {
        var values = [String]()

        if let tenantName = item.tenantName {
            values.append(tenantName)
        }

        if item.isVacancy {
            values.append("Leerstand")
        }

        if let idNum = item.licenseAgreement?.idNum {
            values.append("Vertrag \(idNum)")
        }

        if let idNum = item.useUnit?.idNum {
            values.append("Nutzungseinheit \(idNum)")
        }

        if let address = item.building?.address {
            values.append(address)
        }

        if let idNum = item.building?.idNum {
            values.append("Gebäude \(idNum)")
        }

        return values.joined(separator: " · ")
    }

    private var compatibleTasks: [TimeTask] {
        guard let craftActivityId = positions
            .compactMap({
                $0.task?.craftActivity?.id
            })
            .first else {
            return tasks
        }

        return tasks.filter {
            $0.craftActivity?.id == craftActivityId
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
        let query = searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !query.isEmpty else {
            return tasks
        }

        return tasks.filter { task in
            let values = [
                task.code,
                task.title,
                task.craftActivity?.code,
                task.craftActivity?.name,
            ]
            .compactMap { $0 }
            .joined(separator: " ")
            .localizedCaseInsensitiveContains(query)

            return values
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
                    spacing: 12
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

                        if let craftActivity =
                            task.craftActivity {
                            Text(
                                craftActivity.name
                                ?? craftActivity.code
                                ?? ""
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if task.id == selectedTaskId {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Leistung auswählen")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            prompt: "Leistung oder Gewerk"
        )
        .overlay {
            if filteredTasks.isEmpty {
                ContentUnavailableView(
                    "Keine Leistungen gefunden",
                    systemImage: "magnifyingglass",
                    description: Text(
                        "Bitte einen anderen Suchbegriff verwenden."
                    )
                )
            }
        }
    }
}

struct SelectedCommissionObjectView: View {
    let item: CommissionObjectChoice

    private var economicUnitText: String {
        [
            item.economicUnit.idNum,
            item.economicUnit.name,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private var buildingText: String? {
        guard let building = item.building else {
            return nil
        }

        return [
            building.idNum,
            building.address,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private var useUnitText: String? {
        guard let useUnit = item.useUnit else {
            return nil
        }

        return [
            useUnit.idNum,
            useUnit.floor,
            useUnit.position,
            useUnit.description,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            Text(item.label)
                .font(.headline)

            if let tenantName = item.tenantName {
                LabeledContent(
                    "Mieter",
                    value: tenantName
                )
            } else if item.isVacancy {
                LabeledContent(
                    "Belegung",
                    value: "Leerstand"
                )
            }

            LabeledContent(
                "Buchwerk",
                value: item.companyCode.code ?? "-"
            )

            LabeledContent(
                "Wirtschaftseinheit",
                value: economicUnitText
            )

            if let buildingText {
                LabeledContent(
                    "Gebäude",
                    value: buildingText
                )
            }

            if let useUnitText {
                LabeledContent(
                    "Nutzungseinheit",
                    value: useUnitText
                )
            }

            if let agreementIdNum = item
                .licenseAgreement?
                .idNum {
                LabeledContent(
                    "Mietvertrag",
                    value: agreementIdNum
                )
            }
        }
    }
}

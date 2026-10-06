import SwiftUI

struct MaterialsSectionView: View {
    @EnvironmentObject private var session: SessionStore

    let commission: Commission

    @State private var movements: [InventoryMovement] = []
    @State private var taskSearchText = ""
    @State private var selectedTask: TimeTask?
    @State private var commissionTasks: [TimeTask] = []
    @State private var taskSuggestions: [TimeTask] = []
    @State private var code = ""
    @State private var quantityText = "1"
    @State private var materialSource = "warehouse"
    @State private var usageStatus = "installed"
    @State private var inventoryLocations: [InventoryLocation] = []
    @State private var selectedInventoryLocationId: Int?
    @State private var note = ""
    @State private var selectedItem: InventoryItem?
    @State private var searchSuggestions: [InventoryItem] = []
    @State private var scannerPresented = false
    @State private var isLoading = false
    @State private var isCancelling = false
    @State private var errorMessage: String?
    @State private var itemSuggestionTask: Task<Void, Never>?
    @State private var taskSuggestionTask: Task<Void, Never>?
    @State private var movementToCancel: InventoryMovement?
    @State private var suppressNextSuggestionSearch = false
    @State private var isCancelDialogPresented = false
    @State private var serialNumber = ""
    @State private var itemTypeFilterId: Int?

    private let materialSources = [
        ("warehouse", "Lager"),
        ("vehicle", "Fahrzeug"),
        ("direct_purchase", "Direktkauf"),
        ("on_site", "Vor Ort vorhanden")
    ]
    
    private var requiresInventoryLocation: Bool {
        materialSource == "warehouse"
        || materialSource == "vehicle"
    }

    private var availableInventoryLocations: [InventoryLocation] {
        switch materialSource {
        case "vehicle":
            return inventoryLocations.filter {
                $0.locationType == "vehicle"
            }

        case "warehouse":
            return inventoryLocations.filter {
                $0.locationType != "vehicle"
            }

        default:
            return []
        }
    }

    private let usageStatuses = [
        ("installed", "Verbaut"),
        ("not_installed", "Nicht verbaut"),
        ("returned", "Zurückgegeben"),
        ("defective", "Defekt"),
        ("in_vehicle", "Im Fahrzeug")
    ]

    var body: some View {
        List {
            Section("Leistungsposition") {
                if commission.canEditValue == false {
                    Text("Material ist für Kollegenaufträge nur lesend verfügbar.")
                        .foregroundStyle(.secondary)
                }

                TextField("Position eintippen", text: $taskSearchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(commission.canEditValue == false)

                if let selectedTask {
                    VStack(alignment: .leading, spacing: 8) {
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

                        if selectedTask.expectedMaterialsValue.isEmpty {
                            Text("Für diese Leistungsposition ist kein erwartetes Material hinterlegt.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Erwartetes Material")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(
                                selectedTask.expectedMaterialsValue
                            ) { expectedMaterial in
                                Button {
                                    selectExpectedMaterial(
                                        expectedMaterial
                                    )
                                } label: {
                                    HStack(alignment: .top) {
                                        VStack(
                                            alignment: .leading,
                                            spacing: 4
                                        ) {
                                            Text(
                                                expectedMaterial.displayName
                                            )
                                            .foregroundStyle(.primary)

                                            Text(
                                                "\(quantityText(for: expectedMaterial.quantity)) "
                                                + "\(expectedMaterial.unit) "
                                                + "· \(expectedMaterial.detailText)"
                                            )
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        Image(
                                            systemName: "plus.circle"
                                        )
                                        .foregroundStyle(.blue)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
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
            }

            Section("Material buchen") {
                HStack {
                    TextField("Artikelnummer, EAN oder QR-Code", text: $code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(commission.canEditValue == false)

                    Button {
                        scannerPresented = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                    .disabled(commission.canEditValue == false)
                }

                if let selectedItem {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedItem.name)
                            .font(.headline)

                        Text("Artikelnummer: \(selectedItem.itemNumber)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("Bestand: \(Formatters.quantityText(selectedItem.stockQuantity, unit: selectedItem.unit))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                if !searchSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Artikelvorschläge")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(searchSuggestions) { item in
                            Button {
                                selectItem(item)
                            } label: {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.name)
                                            .foregroundStyle(.primary)

                                        Text(item.itemNumber)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        if let ean = item.ean, !ean.isEmpty {
                                            Text("EAN \(ean)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .buttonStyle(.plain)

                            if item.id != searchSuggestions.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                TextField(
                    "Menge",
                    text: $quantityText
                )
                .keyboardType(.decimalPad)
                .disabled(
                    commission.canEditValue == false
                    || selectedItem?
                        .serialNumberRequiredValue == true
                )

                if selectedItem?
                    .serialNumberRequiredValue == true {
                    TextField(
                        "Seriennummer",
                        text: $serialNumber
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(
                        commission.canEditValue == false
                    )

                    Text(
                        "Dieser Artikel muss einzeln mit Menge 1 gebucht werden."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Picker("Quelle", selection: $materialSource) {
                    ForEach(materialSources, id: \.0) { source in
                        Text(source.1).tag(source.0)
                    }
                }
                .disabled(commission.canEditValue == false)
                
                if requiresInventoryLocation {
                    Picker(
                        "Lagerort",
                        selection: $selectedInventoryLocationId
                    ) {
                        Text("Bitte auswählen")
                            .tag(Int?.none)

                        ForEach(
                            availableInventoryLocations
                        ) { location in
                            Text(location.displayName)
                                .tag(Optional(location.id))
                        }
                    }
                    .disabled(
                        selectedItem == nil
                        || isLoading
                        || commission.canEditValue == false
                        || (
                            requiresInventoryLocation
                            && selectedInventoryLocationId == nil
                        )
                    )

                    if let selectedItem,
                       let selectedInventoryLocationId {
                        let availableQuantity = selectedItem.stockQuantity(
                            at: selectedInventoryLocationId
                        )

                        Text(
                            "Verfügbar: \(Formatters.quantityText(availableQuantity, unit: selectedItem.unit))"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }   

                    if availableInventoryLocations.isEmpty {
                        Text(
                            materialSource == "vehicle"
                            ? "Es ist kein Fahrzeug-Lagerort eingerichtet."
                            : "Es ist kein passender Lagerort eingerichtet."
                        )
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                }

                Picker("Status", selection: $usageStatus) {
                    ForEach(usageStatuses, id: \.0) { status in
                        Text(status.1).tag(status.0)
                    }
                }
                .disabled(commission.canEditValue == false)

                TextField("Notiz / Erläuterung", text: $note, axis: .vertical)
                    .disabled(commission.canEditValue == false)

                Button {
                    Task {
                        await addMaterial()
                    }
                } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Label("Material buchen", systemImage: "minus.circle")
                    }
                }
                .disabled(
                    selectedItem == nil
                    || isLoading
                    || commission.canEditValue == false
                    || (
                        selectedItem?
                            .serialNumberRequiredValue == true
                        && serialNumber
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            .isEmpty
                    )
                )
            }

            Section("Logbuch zum Auftrag") {
                if movements.isEmpty {
                    Text("Noch keine Materialbuchungen.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(movements) { movement in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(movement.item.name)
                                    .font(.headline)

                                Spacer()

                                Text(Formatters.quantityText(movement.quantity, unit: movement.item.unit))
                                    .font(.subheadline.bold())
                                    .foregroundStyle(movement.movementType == "cancellation" ? .green : .primary)
                            }

                            HStack {
                                Text(movement.movementTypeLabel)

                                if movement.isCancelledValue {
                                    Text("· storniert")
                                        .foregroundStyle(.red)
                                }

                                Spacer()

                                Text(Formatters.dateTimeText(movement.occurredAt))
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            if let task = movement.taskTemplate {
                                Text(task.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if !movement.sourceLabel.isEmpty || !movement.usageStatusLabel.isEmpty {
                                Text("\(movement.sourceLabel) · \(movement.usageStatusLabel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            if let sourceLocation = movement.sourceLocation {
                                Text("Entnommen aus: \(sourceLocation.name)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let targetLocation = movement.targetLocation {
                                Text("Zurückgebucht nach: \(targetLocation.name)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            if let serialNumber = movement.serialNumber,
                               !serialNumber.isEmpty {
                                Text(
                                    "Seriennummer: \(serialNumber)"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            if let user = movement.user {
                                Text(user.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let note = movement.note, !note.isEmpty {
                                Text(note)
                                    .font(.caption)
                            }

                            if movement.canCancelValue && commission.canEditValue {
                                Button(role: .destructive) {
                                    movementToCancel = movement
                                    isCancelDialogPresented = true
                                } label: {
                                    Label("Buchung stornieren", systemImage: "arrow.uturn.backward.circle")
                                        .font(.caption)
                                }
                                .disabled(isCancelling)
                                .padding(.top, 2)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if movement.canCancelValue && commission.canEditValue {
                                Button(role: .destructive) {
                                    movementToCancel = movement
                                    isCancelDialogPresented = true
                                } label: {
                                    Label("Stornieren", systemImage: "arrow.uturn.backward.circle")
                                }
                                .disabled(isCancelling)
                            }
                        }
                        .padding(.vertical, 4)
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
        .onChange(of: materialSource) { _, _ in
            configureInventoryLocation()
        }
        .onChange(of: code) { _, newValue in
            handleCodeChange(newValue)
        }
        .onChange(of: taskSearchText) { _, newValue in
            handleTaskSearchTextChange(newValue)
        }
        .sheet(isPresented: $scannerPresented) {
            NavigationStack {
                CodeScannerView { scannedCode in
                    itemSuggestionTask?.cancel()
                    selectedItem = nil
                    itemTypeFilterId = nil
                    serialNumber = ""
                    searchSuggestions = []
                    suppressNextSuggestionSearch = true
                    code = scannedCode
                    scannerPresented = false

                    Task {
                        await lookupOrSearchItem()
                    }
                }
                .navigationTitle("Code scannen")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .confirmationDialog(
            "Materialbuchung stornieren?",
            isPresented: $isCancelDialogPresented,
            titleVisibility: .visible
        ) {
            Button("Buchung stornieren", role: .destructive) {
                guard let movement = movementToCancel else {
                    return
                }

                Task {
                    await cancelMaterial(movement)
                }
            }

            Button("Abbrechen", role: .cancel) {
                movementToCancel = nil
            }
        } message: {
            if let movement = movementToCancel {
                Text("\(movement.item.name) · \(Formatters.quantityText(movement.quantity, unit: movement.item.unit))")
            } else {
                Text("")
            }
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
    
    private func loadData() async {
        do {
            async let loadedMovements =
                session.apiClient.fetchMaterials(
                    commissionId: commission.id
                )

            async let loadedLocations =
                session.apiClient
                    .fetchInventoryLocations()

            async let loadedTasks =
                session.apiClient.fetchTimeTasks()

            let result = try await (
                loadedMovements,
                loadedLocations,
                loadedTasks
            )

            movements = result.0
            inventoryLocations = result.1
            commissionTasks =
                commission.matchingTimeTasks(
                    in: result.2
                )

            configureInventoryLocation()
            restoreTaskSelection()
        } catch {
            if error.isRequestCancellation {
                return
            }

            errorMessage = error.localizedDescription
        }
    }

    private func restoreTaskSelection() {
        guard selectedTask == nil else {
            return
        }

        if commissionTasks.count == 1,
           let task = commissionTasks.first {
            selectTask(task)
        } else if taskSearchText.isEmpty {
            taskSuggestions = commissionTasks
        }
    }

    private func configureInventoryLocation() {
        guard requiresInventoryLocation else {
            selectedInventoryLocationId = nil
            return
        }

        if let selectedInventoryLocationId,
           availableInventoryLocations.contains(
            where: {
                $0.id == selectedInventoryLocationId
            }
           ) {
            return
        }

        selectedInventoryLocationId = (
            availableInventoryLocations.first {
                $0.isDefault
            }
            ?? availableInventoryLocations.first
        )?.id
    }

    private func loadMaterials() async {
        do {
            movements = try await session.apiClient.fetchMaterials(commissionId: commission.id)
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
        taskSuggestionTask?.cancel()

        let searchText = value.trimmingCharacters(in: .whitespacesAndNewlines)

        guard searchText.count >= 2 else {
            taskSuggestions = []
            return
        }

        taskSuggestionTask = Task { @MainActor in
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
        taskSuggestionTask?.cancel()
        selectedTask = task
        taskSuggestions = []
        taskSearchText = task.title
    }

    private func clearSelectedTask() {
        taskSuggestionTask?.cancel()
        selectedTask = nil
        taskSearchText = ""
        taskSuggestions = []
    }

    private func selectExpectedMaterial(
        _ expectedMaterial: ExpectedMaterial
    ) {
        searchSuggestions = []
        quantityText = quantityText(
            for: expectedMaterial.quantity
        )
        usageStatus = "installed"
        materialSource = "warehouse"
        serialNumber = ""

        if let item = expectedMaterial.item {
            selectItem(
                item
            )

            if !item.serialNumberRequiredValue {
                quantityText = quantityText(
                    for: expectedMaterial.quantity
                )
            }

            return
        }

        guard let itemType = (
            expectedMaterial.itemType
        ) else {
            return
        }

        itemSuggestionTask?.cancel()
        selectedItem = nil
        itemTypeFilterId = itemType.id
        suppressNextSuggestionSearch = true
        code = itemType.name

        scheduleSuggestionSearch(
            for: itemType.name
        )
    }

    private func handleCodeChange(
        _ value: String
    ) {
        if suppressNextSuggestionSearch {
            suppressNextSuggestionSearch = false
            return
        }

        if (
            selectedItem?.itemNumber == value
            || selectedItem?.ean == value
            || selectedItem?.qrCodePayload == value
        ) {
            return
        }

        selectedItem = nil
        itemTypeFilterId = nil
        serialNumber = ""

        scheduleSuggestionSearch(
            for: value
        )
    }

    private func scheduleSuggestionSearch(for value: String) {
        itemSuggestionTask?.cancel()

        let searchText = value.trimmingCharacters(in: .whitespacesAndNewlines)

        guard searchText.count >= 2 else {
            searchSuggestions = []
            return
        }
        
        let filteredItemTypeId = (
            itemTypeFilterId
        )

        itemSuggestionTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)

            if Task.isCancelled {
                return
            }

            do {
                let items =
                    try await session.apiClient
                        .searchInventory(
                            query: searchText,
                            itemTypeId: filteredItemTypeId
                        )

                if Task.isCancelled {
                    return
                }

                await MainActor.run {
                    searchSuggestions = items
                }
            } catch {
                if Task.isCancelled {
                    return
                }

                await MainActor.run {
                    searchSuggestions = []
                }
            }
        }
    }

    private func lookupOrSearchItem() async {
        let searchText = code.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !searchText.isEmpty else {
            return
        }

        do {
            let item =
                try await session.apiClient
                    .lookupInventory(
                        code: searchText
                    )

            selectItem(
                item
            )
            searchSuggestions = []
        } catch {
            await searchItems(showErrorWhenEmpty: true)
        }
    }

    private func searchItems(showErrorWhenEmpty: Bool) async {
        let searchText = code.trimmingCharacters(in: .whitespacesAndNewlines)

        guard searchText.count >= 2 else {
            searchSuggestions = []
            return
        }

        do {
            let items =
                try await session.apiClient
                    .searchInventory(
                        query: searchText,
                        itemTypeId: itemTypeFilterId
                    )

            if items.count == 1, let item = items.first {
                selectItem(item)
            } else {
                searchSuggestions = items

                if showErrorWhenEmpty && items.isEmpty {
                    errorMessage = "Kein Artikel gefunden."
                }
            }
        } catch {
            if showErrorWhenEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func selectItem(
        _ item: InventoryItem
    ) {
        itemSuggestionTask?.cancel()
        selectedItem = item
        itemTypeFilterId = nil
        searchSuggestions = []
        code = item.itemNumber
        serialNumber = ""

        if item.serialNumberRequiredValue {
            quantityText = "1"
        }
    }

    private func addMaterial() async {
        guard let selectedTask else {
            errorMessage = "Bitte zuerst eine Leistungsposition auswählen."
            return
        }

        guard let selectedItem else {
            errorMessage = "Bitte zuerst einen Artikel auswählen."
            return
        }

        let normalizedQuantity =
            quantityText.replacingOccurrences(
                of: ",",
                with: "."
            )

        guard let quantity = Double(normalizedQuantity), quantity > 0 else {
            errorMessage = "Bitte eine gültige Menge eingeben."
            return
        }
        
        let normalizedSerialNumber =
            serialNumber.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        if selectedItem.serialNumberRequiredValue {
            guard abs(quantity - 1.0) < 0.0001 else {
                errorMessage = (
                    "Seriennummernpflichtige Artikel "
                    + "müssen einzeln gebucht werden."
                )
                return
            }

            guard !normalizedSerialNumber.isEmpty else {
                errorMessage = (
                    "Bitte die Seriennummer eingeben."
                )
                return
            }
        }
        
        let locationId: Int?

        if requiresInventoryLocation {
            guard let selectedInventoryLocationId else {
                errorMessage = "Bitte einen Lagerort auswählen."
                return
            }

            let availableQuantity = selectedItem.stockQuantity(
                at: selectedInventoryLocationId
            )

            guard availableQuantity + 0.0001 >= quantity else {
                errorMessage = "Am ausgewählten Lagerort ist nicht genügend Bestand vorhanden."
                return
            }

            locationId = selectedInventoryLocationId
        } else {
            locationId = nil
        }

        isLoading = true

        defer {
            isLoading = false
        }

        do {
            _ = try await session.apiClient.addMaterial(
                commissionId: commission.id,
                code: selectedItem.itemNumber,
                quantity: quantity,
                taskTemplateId: selectedTask.id,
                usageStatus: usageStatus,
                source: materialSource,
                locationId: locationId,
                deviationReason: nil,
                note: (
                    note.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                    ? nil
                    : note
                ),
                serialNumber: (
                    normalizedSerialNumber.isEmpty
                    ? nil
                    : normalizedSerialNumber
                ),
            )

            clearMaterialInput()
            await loadMaterials()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancelMaterial(_ movement: InventoryMovement) async {
        isCancelling = true

        defer {
            isCancelling = false
            movementToCancel = nil
            isCancelDialogPresented = false
        }

        do {
            _ = try await session.apiClient.cancelMaterial(
                commissionId: commission.id,
                movementId: movement.id
            )

            await loadMaterials()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func quantityText(for value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(value)
    }

    private func clearMaterialInput() {
        itemSuggestionTask?.cancel()
        selectedItem = nil
        searchSuggestions = []
        code = ""
        quantityText = "1"
        usageStatus = "installed"
        materialSource = "warehouse"
        note = ""
        configureInventoryLocation()
        itemTypeFilterId = nil
        serialNumber = ""
    }
}

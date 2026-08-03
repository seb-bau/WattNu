import SwiftUI

struct MaterialsSectionView: View {
    @EnvironmentObject private var session: SessionStore

    let commission: Commission

    @State private var movements: [InventoryMovement] = []
    @State private var taskSearchText = ""
    @State private var selectedTask: TimeTask?
    @State private var taskSuggestions: [TimeTask] = []
    @State private var code = ""
    @State private var quantityText = "1"
    @State private var materialSource = "warehouse"
    @State private var usageStatus = "installed"
    @State private var deviationReason = ""
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

    private let materialSources = [
        ("warehouse", "Lager"),
        ("vehicle", "Fahrzeug"),
        ("direct_purchase", "Direktkauf"),
        ("on_site", "Vor Ort vorhanden")
    ]

    private let usageStatuses = [
        ("installed", "Verbaut"),
        ("not_installed", "Nicht verbaut"),
        ("returned", "Zurückgegeben"),
        ("defective", "Defekt"),
        ("in_vehicle", "Im Fahrzeug")
    ]

    private let deviationReasons = [
        ("", "Keine Abweichung"),
        ("different_material", "Anderes Material"),
        ("additional_material", "Zusätzliches Material"),
        ("not_needed", "Nicht benötigt"),
        ("not_available", "Nicht verfügbar"),
        ("direct_purchase", "Direktkauf"),
        ("other", "Sonstiges")
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

                            ForEach(selectedTask.expectedMaterialsValue) { expectedMaterial in
                                Button {
                                    selectExpectedMaterial(expectedMaterial)
                                } label: {
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(expectedMaterial.item.name)
                                                .foregroundStyle(.primary)
                                            Text("\(quantityText(for: expectedMaterial.quantity)) \(expectedMaterial.item.unit) · \(expectedMaterial.item.itemNumber)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        Image(systemName: "plus.circle")
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

                TextField("Menge", text: $quantityText)
                    .keyboardType(.decimalPad)
                    .disabled(commission.canEditValue == false)

                Picker("Quelle", selection: $materialSource) {
                    ForEach(materialSources, id: \.0) { source in
                        Text(source.1).tag(source.0)
                    }
                }
                .disabled(commission.canEditValue == false)

                Picker("Status", selection: $usageStatus) {
                    ForEach(usageStatuses, id: \.0) { status in
                        Text(status.1).tag(status.0)
                    }
                }
                .disabled(commission.canEditValue == false)

                Picker("Abweichungsgrund", selection: $deviationReason) {
                    ForEach(deviationReasons, id: \.0) { reason in
                        Text(reason.1).tag(reason.0)
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
                .disabled(selectedItem == nil || isLoading || commission.canEditValue == false)
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

                            if !movement.reviewLabel.isEmpty {
                                Text(movement.reviewLabel)
                                    .font(.caption)
                                    .foregroundStyle(movement.reviewStatus == "needs_review" ? .orange : .secondary)
                            }

                            if let user = movement.user {
                                Text(user.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let deviationReason = movement.deviationReason, !deviationReason.isEmpty {
                                Text(deviationReason)
                                    .font(.caption)
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
            await loadMaterials()
        }
        .refreshable {
            await loadMaterials()
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

    private func selectExpectedMaterial(_ expectedMaterial: ExpectedMaterial) {
        selectedItem = expectedMaterial.item
        searchSuggestions = []
        code = expectedMaterial.item.itemNumber
        quantityText = quantityText(for: expectedMaterial.quantity)
        usageStatus = "installed"
        materialSource = "warehouse"
        deviationReason = ""
    }

    private func handleCodeChange(_ value: String) {
        if suppressNextSuggestionSearch {
            suppressNextSuggestionSearch = false
            return
        }

        if selectedItem?.itemNumber == value || selectedItem?.ean == value || selectedItem?.qrCodePayload == value {
            return
        }

        selectedItem = nil
        scheduleSuggestionSearch(for: value)
    }

    private func scheduleSuggestionSearch(for value: String) {
        itemSuggestionTask?.cancel()

        let searchText = value.trimmingCharacters(in: .whitespacesAndNewlines)

        guard searchText.count >= 2 else {
            searchSuggestions = []
            return
        }

        itemSuggestionTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)

            if Task.isCancelled {
                return
            }

            do {
                let items = try await session.apiClient.searchInventory(query: searchText)

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
            selectedItem = try await session.apiClient.lookupInventory(code: searchText)
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
            let items = try await session.apiClient.searchInventory(query: searchText)

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

    private func selectItem(_ item: InventoryItem) {
        itemSuggestionTask?.cancel()
        selectedItem = item
        searchSuggestions = []
        code = item.itemNumber
    }

    private func addMaterial() async {
        guard let selectedItem else {
            errorMessage = "Bitte zuerst einen Artikel auswählen."
            return
        }

        let normalizedQuantity = quantityText.replacingOccurrences(of: ",", with: ".")

        guard let quantity = Double(normalizedQuantity), quantity > 0 else {
            errorMessage = "Bitte eine gültige Menge eingeben."
            return
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
                taskTemplateId: selectedTask?.id,
                usageStatus: usageStatus,
                source: materialSource,
                deviationReason: deviationReason.isEmpty ? nil : deviationReason,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
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
        deviationReason = ""
        note = ""
    }
}

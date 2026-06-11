import SwiftUI

struct MaterialsSectionView: View {
    @EnvironmentObject private var session: SessionStore

    let commission: Commission

    @State private var movements: [InventoryMovement] = []
    @State private var code = ""
    @State private var quantityText = "1"
    @State private var note = ""
    @State private var selectedItem: InventoryItem?
    @State private var searchSuggestions: [InventoryItem] = []
    @State private var scannerPresented = false
    @State private var isLoading = false
    @State private var isCancelling = false
    @State private var errorMessage: String?
    @State private var suggestionTask: Task<Void, Never>?
    @State private var movementToCancel: InventoryMovement?
    @State private var suppressNextSuggestionSearch = false
    @State private var isCancelDialogPresented = false

    var body: some View {
        List {
            Section("Material entnehmen") {
                if commission.canEditValue == false {
                    Text("Materialbuchungen sind für Kollegenaufträge nur lesend verfügbar.")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    TextField("Artikel suchen, QR-Code, EAN oder Artikelnummer", text: $code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button {
                        scannerPresented = true
                    } label: {
                        Image(systemName: "barcode.viewfinder")
                    }
                }

                HStack {
                    TextField("Menge", text: $quantityText)
                        .keyboardType(.decimalPad)

                    Button("Suchen") {
                        Task {
                            await lookupOrSearchItem()
                        }
                    }
                    .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let selectedItem {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedItem.name)
                            .font(.headline)

                        Text("Artikel \(selectedItem.itemNumber) · Bestand \(Formatters.quantityText(selectedItem.stockQuantity, unit: selectedItem.unit))")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let ean = selectedItem.ean, !ean.isEmpty {
                            Text("EAN \(ean)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if !searchSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Vorschläge")
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

                                        Text("Artikel \(item.itemNumber) · Bestand \(Formatters.quantityText(item.stockQuantity, unit: item.unit))")
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

                TextField("Notiz", text: $note, axis: .vertical)

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
            await loadMaterials()
        }
        .refreshable {
            await loadMaterials()
        }
        .onChange(of: code) { _, newValue in
            handleCodeChange(newValue)
        }
        .sheet(isPresented: $scannerPresented) {
            NavigationStack {
                CodeScannerView { scannedCode in
                    suggestionTask?.cancel()
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
        suggestionTask?.cancel()

        let searchText = value.trimmingCharacters(in: .whitespacesAndNewlines)

        guard searchText.count >= 2 else {
            searchSuggestions = []
            return
        }

        suggestionTask = Task {
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
    
    private func lookupScannedItem()  async {
        let searchText = code.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !searchText.isEmpty else {
            return
        }
        
        suggestionTask?.cancel()
        searchSuggestions = []
        
        do {
            selectedItem = try await session.apiClient.lookupInventory(code: searchText)
            searchSuggestions = []
        } catch {
            selectedItem = nil
            searchSuggestions = []
            errorMessage = "Kein Artikel für diesen QR-Code gefunden."
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
        suggestionTask?.cancel()
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

    private func clearMaterialInput() {
        suggestionTask?.cancel()
        selectedItem = nil
        searchSuggestions = []
        code = ""
        quantityText = "1"
        note = ""
    }
}

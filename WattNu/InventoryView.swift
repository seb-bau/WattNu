import SwiftUI

private enum InventoryBookingMode: String, CaseIterable, Identifiable {
    case transfer
    case receipt

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .transfer:
            return "Umbuchen"
        case .receipt:
            return "Einkauf"
        }
    }
}

struct InventoryView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var bookingMode: InventoryBookingMode = .transfer
    @State private var locations: [InventoryLocation] = []
    @State private var movements: [InventoryMovement] = []
    @State private var searchText = ""
    @State private var searchResults: [InventoryItem] = []
    @State private var selectedItem: InventoryItem?
    @State private var sourceLocationId: Int?
    @State private var targetLocationId: Int?
    @State private var quantityText = "1"
    @State private var note = ""
    @State private var scannerPresented = false
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Buchungsart") {
                    Picker(
                        "Buchungsart",
                        selection: $bookingMode
                    ) {
                        ForEach(
                            InventoryBookingMode.allCases
                        ) { mode in
                            Text(mode.label)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Artikel") {
                    HStack {
                        TextField(
                            "Artikelnummer, EAN oder QR-Code",
                            text: $searchText
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        Button {
                            scannerPresented = true
                        } label: {
                            Image(
                                systemName: "barcode.viewfinder"
                            )
                        }
                    }

                    Button("Artikel suchen") {
                        Task {
                            await searchItems()
                        }
                    }
                    .disabled(
                        searchText
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            .count < 2
                    )

                    ForEach(searchResults) { item in
                        Button {
                            selectItem(item)
                        } label: {
                            VStack(
                                alignment: .leading,
                                spacing: 3
                            ) {
                                Text(item.name)
                                    .foregroundStyle(.primary)

                                Text(
                                    "\(item.itemNumber) · Gesamt \(formatted(item.stockQuantity)) \(item.unit)"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let selectedItem {
                        VStack(
                            alignment: .leading,
                            spacing: 4
                        ) {
                            Text(selectedItem.name)
                                .font(.headline)

                            Text(selectedItem.itemNumber)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(
                                "Gesamtbestand: \(formatted(selectedItem.stockQuantity)) \(selectedItem.unit)"
                            )
                            .font(.subheadline)
                        }
                    }
                }

                Section("Lagerorte") {
                    if bookingMode == .transfer {
                        Picker(
                            "Von",
                            selection: $sourceLocationId
                        ) {
                            Text("Bitte auswählen")
                                .tag(Int?.none)

                            ForEach(locations) { location in
                                Text(location.displayName)
                                    .tag(
                                        Optional(location.id)
                                    )
                            }
                        }

                        if let selectedItem {
                            Text(
                                "Bestand am Quellort: \(formatted(selectedItem.stockQuantity(at: sourceLocationId))) \(selectedItem.unit)"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    Picker(
                        "Nach",
                        selection: $targetLocationId
                    ) {
                        Text("Bitte auswählen")
                            .tag(Int?.none)

                        ForEach(locations) { location in
                            Text(location.displayName)
                                .tag(
                                    Optional(location.id)
                                )
                        }
                    }
                }

                Section("Menge") {
                    TextField(
                        "Menge",
                        text: $quantityText
                    )
                    .keyboardType(.decimalPad)

                    TextField(
                        "Notiz",
                        text: $note,
                        axis: .vertical
                    )
                    .lineLimit(2...5)
                }

                Section {
                    Button {
                        Task {
                            await saveBooking()
                        }
                    } label: {
                        HStack {
                            Spacer()

                            if isWorking {
                                ProgressView()
                            } else {
                                Text(
                                    bookingMode == .transfer
                                    ? "Umbuchung speichern"
                                    : "Einkauf einbuchen"
                                )
                            }

                            Spacer()
                        }
                    }
                    .disabled(
                        isWorking
                        || selectedItem == nil
                        || targetLocationId == nil
                    )
                }

                if !movements.isEmpty {
                    Section("Meine letzten Buchungen") {
                        ForEach(movements) { movement in
                            VStack(
                                alignment: .leading,
                                spacing: 4
                            ) {
                                HStack {
                                    Text(
                                        movement.movementTypeLabel
                                    )
                                    .font(.headline)

                                    Spacer()

                                    Text(
                                        "\(formatted(movement.quantity)) \(movement.item.unit)"
                                    )
                                }

                                Text(movement.item.name)

                                if let locationText = locationText(
                                    for: movement
                                ) {
                                    Text(locationText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                if let note = movement.note,
                                   !note.isEmpty {
                                    Text(note)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Lager")
            .task {
                await loadData()
            }
            .refreshable {
                await loadData()
            }
            .onChange(of: bookingMode) { _, _ in
                configureLocations()
            }
            .onChange(of: sourceLocationId) { _, value in
                guard bookingMode == .transfer,
                      targetLocationId == value else {
                    return
                }

                targetLocationId = locations.first {
                    $0.id != value
                }?.id
            }
            .sheet(
                isPresented: $scannerPresented
            ) {
                NavigationStack {
                    CodeScannerView { scannedCode in
                        searchText = scannedCode
                        scannerPresented = false

                        Task {
                            await searchItems()
                        }
                    }
                    .navigationTitle("Artikel scannen")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
            .alert(
                "Hinweis",
                isPresented: Binding(
                    get: {
                        message != nil
                    },
                    set: { visible in
                        if !visible {
                            message = nil
                        }
                    }
                )
            ) {
                Button("OK") {
                    message = nil
                }
            } message: {
                Text(message ?? "")
            }
        }
    }

    private func loadData() async {
        do {
            async let loadedLocations =
                session.apiClient.fetchInventoryLocations()

            async let loadedMovements =
                session.apiClient.fetchInventoryMovements()

            let result = try await (
                loadedLocations,
                loadedMovements
            )

            locations = result.0
            movements = result.1
            configureLocations()

        } catch {
            message = error.localizedDescription
        }
    }

    private func configureLocations() {
        let defaultLocation = locations.first {
            $0.isDefault
        } ?? locations.first

        if sourceLocationId == nil {
            sourceLocationId = defaultLocation?.id
        }

        if targetLocationId == nil {
            targetLocationId = defaultLocation?.id
        }

        if bookingMode == .transfer,
           sourceLocationId == targetLocationId {
            targetLocationId = locations.first {
                $0.id != sourceLocationId
            }?.id
        }
    }

    private func searchItems() async {
        let query = searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard query.count >= 2 else {
            return
        }

        do {
            let items = try await session.apiClient.searchInventory(
                query: query,
                limit: 20
            )

            if items.count == 1,
               let item = items.first {
                selectItem(item)
            } else {
                searchResults = items

                if items.isEmpty {
                    message = "Kein Artikel gefunden."
                }
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func selectItem(
        _ item: InventoryItem
    ) {
        selectedItem = item
        searchText = item.itemNumber
        searchResults = []
    }

    private func saveBooking() async {
        guard let selectedItem else {
            message = "Bitte einen Artikel auswählen."
            return
        }

        let normalizedQuantity = quantityText
            .replacingOccurrences(
                of: ",",
                with: "."
            )

        guard let quantity = Double(
            normalizedQuantity
        ), quantity > 0 else {
            message = "Bitte eine gültige Menge eingeben."
            return
        }

        guard let targetLocationId else {
            message = "Bitte einen Ziel-Lagerort auswählen."
            return
        }

        isWorking = true

        defer {
            isWorking = false
        }

        do {
            let response: MaterialResponse

            switch bookingMode {
            case .transfer:
                guard let sourceLocationId else {
                    message = "Bitte einen Quell-Lagerort auswählen."
                    return
                }

                guard sourceLocationId != targetLocationId else {
                    message = "Quell- und Ziel-Lagerort müssen unterschiedlich sein."
                    return
                }

                response = try await session.apiClient.transferInventory(
                    code: selectedItem.itemNumber,
                    quantity: quantity,
                    sourceLocationId: sourceLocationId,
                    targetLocationId: targetLocationId,
                    note: normalizedNote
                )

                message = "Die Umbuchung wurde gespeichert."

            case .receipt:
                response = try await session.apiClient.receiveInventory(
                    code: selectedItem.itemNumber,
                    quantity: quantity,
                    targetLocationId: targetLocationId,
                    note: normalizedNote
                )

                message = "Der Einkauf wurde eingebucht."
            }

            self.selectedItem = response.inventoryItem
            movements.insert(
                response.item,
                at: 0
            )
            quantityText = "1"
            note = ""

        } catch {
            message = error.localizedDescription
        }
    }

    private var normalizedNote: String? {
        let value = note.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return value.isEmpty ? nil : value
    }

    private func locationText(
        for movement: InventoryMovement
    ) -> String? {
        if let source = movement.sourceLocation,
           let target = movement.targetLocation {
            return "\(source.name) → \(target.name)"
        }

        if let target = movement.targetLocation {
            return "Nach: \(target.name)"
        }

        if let source = movement.sourceLocation {
            return "Von: \(source.name)"
        }

        return nil
    }

    private func formatted(
        _ value: Double
    ) -> String {
        value.formatted(
            .number.precision(
                .fractionLength(0...2)
            )
        )
    }
}

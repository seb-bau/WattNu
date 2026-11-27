import PhotosUI
import SwiftUI
import UIKit

struct CommissionCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore
    @ObservedObject private var preferences = UserPreferencesStore.shared

    let onCreated: () -> Void

    @State private var options: SimpleCommissionCreateOptions?
    @State private var selectedCommissionTypeId = 0
    @State private var selectedCraftActivityId = 0
    @State private var selectedCraftsmanUserId = 0
    @State private var objectSearchText = ""
    @State private var objectSearchResults: [CommissionObjectSearchRow] = []
    @State private var objectSearchTask: Task<Void, Never>?
    @State private var objectSearchNotice: String?
    @State private var selectedObject: CommissionObjectChoice?
    @State private var tenantChargeChoices: CommissionTenantChargeChoices?
    @State private var tenantChargeRecipient = ""
    @State private var tenantChargeChoicesContext: String?
    @State private var tenantChargeError: String?
    @State private var isSearchingObjects = false
    @State private var title = ""
    @State private var commissionText = ""
    @State private var automaticTextField: OrderTextField?
    @State private var contactPerson = ""
    @State private var notifyTenants: Bool?
    @State private var hasExecutionDate = false
    @State private var executionDate = Date()
    @State private var photos: [DraftPhoto] = []
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var cameraPresented = false
    @State private var isImportingPhotos = false
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var requestId = UUID().uuidString
    @State private var submittedRequest: SimpleCommissionCreateRequest?
    @State private var errorMessage: String?

    private enum OrderTextField: Equatable {
        case title, text
    }

    private struct DraftPhoto: Identifiable {
        let id = UUID()
        let data: Data
        let preview: UIImage
    }

    private var selectedCraft: SimpleCommissionCraftOption? {
        options?.craftActivities.first { $0.id == selectedCraftActivityId }
    }

    private var craftError: String? {
        guard let selectedCraft else { return nil }

        if !selectedCraft.fallbackAvailable {
            return "Für dieses Gewerk fehlt eine gültige Fallback-Leistungsposition unter KI-Auftragsvorgaben."
        }

        if selectedCommissionTypeId != 0,
           !selectedCraft.commissionTypeIds.contains(selectedCommissionTypeId) {
            return "Die Auftragsart passt nicht zur Fallback-Leistungsposition dieses Gewerks."
        }

        return nil
    }

    private var effectiveTitle: String {
        normalizedText(title) ?? normalizedText(commissionText) ?? ""
    }

    private var canNotifyTenants: Bool {
        selectedObject?.licenseAgreement != nil && selectedObject?.isVacancy == false
    }

    private var shouldNotifyTenants: Bool {
        canNotifyTenants && (notifyTenants ?? options?.notifyTenantsDefault ?? false)
    }

    private var needsTenantChargeRecipient: Bool {
        options?.commissionTypes.first { $0.id == selectedCommissionTypeId }?.tenantCharge == true
    }

    private var tenantChargeChoicesKey: String? {
        guard needsTenantChargeRecipient, let selectedObject, selectedObject.useUnit != nil else { return nil }
        return "\(selectedCommissionTypeId):\(selectedObject.id)"
    }

    private var canSubmit: Bool {
        guard !isLoading, !isSaving, !isImportingPhotos else { return false }

        if submittedRequest != nil { return true }

        return options?.canCreate == true
            && selectedObject != nil
            && (!needsTenantChargeRecipient || (
                tenantChargeChoicesKey == tenantChargeChoicesContext && !tenantChargeRecipient.isEmpty
            ))
            && (options?.commissionTypes.contains(where: { $0.id == selectedCommissionTypeId }) ?? false)
            && selectedCraft != nil
            && craftError == nil
            && (options?.craftsmen.contains(where: { $0.id == selectedCraftsmanUserId }) ?? false)
            && !effectiveTitle.isEmpty
            && effectiveTitle.unicodeScalars.count <= 255
            && (normalizedText(contactPerson)?.unicodeScalars.count ?? 0) <= 255
    }

    private var tenantChargeSection: some View {
        Section("Wer soll belastet werden?") {
            if tenantChargeChoicesKey == nil {
                Text("Bitte zuerst einen Mietvertrag für die Wohnung auswählen.")
            } else if let tenantChargeError {
                Text(tenantChargeError)
                    .foregroundStyle(.secondary)
                Button("Erneut laden") {
                    Task { await loadTenantChargeChoices() }
                }
            } else if let tenantChargeChoices, tenantChargeChoicesContext == tenantChargeChoicesKey {
                if tenantChargeChoices.currentAvailable {
                    Toggle(
                        "Beauftragten Mieter belasten",
                        isOn: Binding(
                            get: { tenantChargeRecipient == "current" },
                            set: { tenantChargeRecipient = $0 ? "current" : "" }
                        )
                    )
                }
                if tenantChargeRecipient != "current" {
                    Picker("Vertragsnehmer dieser Wohnung", selection: $tenantChargeRecipient) {
                        Text("Bitte auswählen").tag("")
                        ForEach(tenantChargeChoices.items) { item in
                            Text(item.suggested ? "\(item.label) · Vorschlag Vormieter" : item.label).tag(item.value)
                        }
                    }
                }
                if tenantChargeChoices.items.isEmpty {
                    Text("Für diese Wohnung sind keine Vertragsnehmer verfügbar.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView("Mietverträge werden geladen …")
            }
        }
    }

    private var assignmentSection: some View {
        Section("Zuordnung") {
            Picker("Auftragsart", selection: $selectedCommissionTypeId) {
                Text("Bitte auswählen").tag(0)

                ForEach(options?.commissionTypes ?? []) { item in
                    Text(item.displayName).tag(item.id)
                }
            }

            Picker("Gewerk", selection: $selectedCraftActivityId) {
                Text("Bitte auswählen").tag(0)

                ForEach(options?.craftActivities ?? []) { item in
                    Text(item.name).tag(item.id)
                }
            }

            Picker("Handwerker", selection: $selectedCraftsmanUserId) {
                Text("Bitte auswählen").tag(0)

                ForEach(options?.craftsmen ?? []) { item in
                    Text(item.displayName).tag(item.id)
                }
            }

            if let craftError {
                Text(craftError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if options?.canCreate == false {
                Text("Für die Auftragserfassung müssen eine freigegebene Auftragsart, ein Gewerk mit gültiger Fallback-Leistungsposition und ein interner Handwerker verfügbar sein.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var objectSection: some View {
        Section("Objektbezug") {
            HStack {
                TextField("Mieter, Adresse oder Wowiport-Nummer", text: $objectSearchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit {
                        startObjectSearch(immediately: true)
                    }
                    .onChange(of: objectSearchText) { _, _ in
                        startObjectSearch()
                    }

                Button {
                    startObjectSearch(immediately: true)
                } label: {
                    if isSearchingObjects {
                        ProgressView()
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                }
                .disabled(
                    isSearchingObjects
                    || objectSearchText.trimmingCharacters(in: .whitespacesAndNewlines).count < 2
                )
                .accessibilityLabel("Objekte suchen")
            }

            ForEach(objectSearchResults) { row in
                if let item = row.selection {
                    Button {
                        selectObject(item)
                    } label: {
                        CommissionObjectSearchLabel(row: row)
                    }
                    .buttonStyle(.plain)
                } else {
                    CommissionObjectSearchLabel(row: row)
                }
            }

            if let objectSearchNotice {
                Text(objectSearchNotice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let selectedObject {
                SelectedCommissionObjectView(item: selectedObject)
            } else {
                Text("Wähle eine Wirtschaftseinheit, ein Gebäude, eine Nutzungseinheit oder einen Mietvertrag.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var orderSection: some View {
        Section("Auftrag") {
            TextField(
                "Kurztitel",
                text: Binding(get: { title }, set: updateTitle)
            )

            TextField(
                "Auftragstext",
                text: Binding(
                    get: { commissionText },
                    set: updateCommissionText
                ),
                axis: .vertical
            )
            .lineLimit(3...8)

            if effectiveTitle.unicodeScalars.count > 255 {
                Text("Bitte den Kurztitel auf höchstens 255 Zeichen kürzen.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            TextField("Ansprechpartner vor Ort", text: $contactPerson)

            if (normalizedText(contactPerson)?.unicodeScalars.count ?? 0) > 255 {
                Text("Der Ansprechpartner darf höchstens 255 Zeichen enthalten.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Toggle(
                "Mieter über Beauftragung informieren",
                isOn: Binding(
                    get: {
                        shouldNotifyTenants
                    },
                    set: {
                        notifyTenants = $0
                    }
                )
            )
            .disabled(!canNotifyTenants)
        }
    }

    private var executionSection: some View {
        Section("Ausführungsdatum") {
            Toggle("Ausführungsdatum angeben", isOn: $hasExecutionDate)

            if hasExecutionDate {
                DatePicker(
                    "Datum",
                    selection: $executionDate,
                    displayedComponents: .date
                )
            }
        }
    }

    private var photosSection: some View {
        Section("Fotos") {
            if !photos.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 100))],
                    spacing: 10
                ) {
                    ForEach(photos) { photo in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: photo.preview)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 110)
                                .clipped()
                                .clipShape(
                                    RoundedRectangle(cornerRadius: 10)
                                )

                            Button(role: .destructive) {
                                photos.removeAll { $0.id == photo.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(
                                        .white,
                                        .black.opacity(0.7)
                                    )
                                    .font(.title2)
                                    .padding(5)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Foto entfernen")
                        }
                    }
                }
            }

            PhotosPicker(
                selection: $selectedPhotoItems,
                matching: .images
            ) {
                Label("Fotos auswählen", systemImage: "photo.on.rectangle")
            }

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    cameraPresented = true
                } label: {
                    Label("Foto aufnehmen", systemImage: "camera")
                }
            }
        }
    }

    var body: some View {
        Form {
            Group {
                if !isLoading && options == nil {
                    Section {
                        Button("Erneut laden") {
                            Task { await loadData() }
                        }
                    }
                }

                assignmentSection
                objectSection
                if needsTenantChargeRecipient {
                    tenantChargeSection
                }
                orderSection
                executionSection
                photosSection
            }
            .disabled(
                isLoading
                || isSaving
                || isImportingPhotos
                || submittedRequest != nil
            )
        }
        .navigationTitle("Auftrag erfassen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(
                    submittedRequest == nil ? "Abbrechen" : "Schließen"
                ) {
                    dismiss()
                }
                .disabled(isSaving || isImportingPhotos)
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(
                    submittedRequest == nil ? "Erfassen" : "Erneut versuchen"
                ) {
                    Task { await submit() }
                }
                .disabled(!canSubmit)
            }
        }
        .interactiveDismissDisabled(
            isSaving || isImportingPhotos || submittedRequest != nil
        )
        .overlay {
            if isLoading || isSaving || isImportingPhotos {
                ProgressView(
                    isSaving
                    ? "Auftrag und Fotos werden gespeichert …"
                    : isImportingPhotos
                    ? "Fotos werden vorbereitet …"
                    : "Daten werden geladen …"
                )
                .padding()
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .task {
            await loadData()
        }
        .task(id: tenantChargeChoicesKey) {
            await loadTenantChargeChoices()
        }
        .onDisappear {
            stopObjectSearch()
        }
        .onChange(of: selectedCraftActivityId) { _, value in
            if value > 0 { preferences.values.lastCraftActivityId = value }
        }
        .onChange(of: selectedPhotoItems) { _, items in
            guard !items.isEmpty else { return }

            isImportingPhotos = true
            Task { await importPhotos(items) }
        }
        .sheet(isPresented: $cameraPresented) {
            CameraImagePicker { image in
                if let photo = makeDraftPhoto(image) {
                    photos.append(photo)
                } else {
                    errorMessage = "Das Foto konnte nicht vorbereitet werden."
                }
            }
            .ignoresSafeArea()
        }
        .alert(
            "Fehler",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: {
                    if !$0 {
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

    private func updateTitle(_ value: String) {
        title = value

        if automaticTextField == .title {
            automaticTextField = nil
        }

        if normalizedText(commissionText) == nil
            || automaticTextField == .text {
            commissionText = value
            automaticTextField = .text
        }
    }

    private func updateCommissionText(_ value: String) {
        commissionText = value

        if automaticTextField == .text {
            automaticTextField = nil
        }

        if normalizedText(title) == nil
            || automaticTextField == .title {
            title = value
            automaticTextField = .title
        }
    }

    private func loadData() async {
        guard options == nil else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let loaded = try await session.apiClient
                .fetchSimpleCommissionCreateOptions()

            options = loaded
            selectedCommissionTypeId = loaded.commissionTypes.first?.id ?? 0
            selectedCraftsmanUserId = loaded.defaultCraftsmanUserId ?? 0
            if let craftId = preferences.values.lastCraftActivityId,
               loaded.craftActivities.contains(where: { $0.id == craftId }) {
                selectedCraftActivityId = craftId
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadTenantChargeChoices() async {
        tenantChargeChoices = nil
        tenantChargeChoicesContext = nil
        tenantChargeRecipient = ""
        tenantChargeError = nil
        guard let key = tenantChargeChoicesKey, let selectedObject else { return }

        do {
            let choices = try await session.apiClient.fetchTenantChargeChoices(
                object: selectedObject, commissionTypeId: selectedCommissionTypeId
            )
            guard !Task.isCancelled, key == tenantChargeChoicesKey else { return }
            tenantChargeChoices = choices
            tenantChargeChoicesContext = key
        } catch {
            guard !Task.isCancelled, key == tenantChargeChoicesKey else { return }
            tenantChargeError = error.localizedDescription
        }
    }

    private func submit() async {
        guard canSubmit else { return }

        if submittedRequest == nil {
            guard let selectedObject else { return }

            title = effectiveTitle
            commissionText = normalizedText(commissionText) ?? title

            submittedRequest = SimpleCommissionCreateRequest(
                clientRequestId: requestId,
                objectType: selectedObject.objectType,
                objectId: selectedObject.objectId,
                commissionTypeId: selectedCommissionTypeId,
                craftActivityId: selectedCraftActivityId,
                craftsmanUserId: selectedCraftsmanUserId,
                title: title,
                commissionText: commissionText,
                contactPerson: normalizedText(contactPerson),
                executionDate: hasExecutionDate
                    ? formattedExecutionDate()
                    : nil,
                notifyTenants: shouldNotifyTenants,
                tenantChargeRecipient: needsTenantChargeRecipient ? tenantChargeRecipient : nil
            )
        }

        guard let submittedRequest else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await session.apiClient.createSimpleCommission(
                body: submittedRequest,
                photos: photos.map(\.data)
            )

            onCreated()
            dismiss()
        } catch {
            if let apiError = error as? APIError {
                switch apiError {
                case .serverStatus(let status, _)
                    where [400, 403, 404, 409, 413, 422].contains(status):
                    self.submittedRequest = nil
                    requestId = UUID().uuidString

                case .unauthorized, .missingToken, .invalidBaseURL:
                    self.submittedRequest = nil

                default:
                    break
                }
            }

            if self.submittedRequest == nil {
                errorMessage = error.localizedDescription
            } else {
                errorMessage = "Die Speicherung konnte nicht bestätigt werden. Der Auftrag wurde möglicherweise bereits gespeichert. Mit „Erneut versuchen“ wird dieselbe Anfrage wiederholt.\n\n\(error.localizedDescription)"
            }
        }
    }

    private func formattedExecutionDate() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: executionDate)
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        defer {
            selectedPhotoItems = []
            isImportingPhotos = false
        }

        var failedCount = 0

        for item in items {
            do {
                if let data = try await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data),
                   let photo = makeDraftPhoto(image) {
                    photos.append(photo)
                } else {
                    failedCount += 1
                }
            } catch {
                failedCount += 1
            }
        }

        if failedCount > 0 {
            errorMessage = "\(failedCount) Foto(s) konnten nicht eingelesen werden. Bitte erneut auswählen."
        }
    }

    private func makeDraftPhoto(_ image: UIImage) -> DraftPhoto? {
        let dimension = max(image.size.width, image.size.height)
        guard dimension > 0 else { return nil }

        let scale = min(1, 2560 / dimension)
        let size = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let resized = UIGraphicsImageRenderer(
            size: size,
            format: format
        ).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }

        guard let data = resized.jpegData(
            compressionQuality: 0.82
        ) else {
            return nil
        }

        let previewScale = min(1, 240 / max(size.width, size.height))
        let previewSize = CGSize(
            width: size.width * previewScale,
            height: size.height * previewScale
        )

        let preview = UIGraphicsImageRenderer(
            size: previewSize,
            format: format
        ).image { _ in
            resized.draw(in: CGRect(origin: .zero, size: previewSize))
        }

        return DraftPhoto(data: data, preview: preview)
    }

    private func startObjectSearch(immediately: Bool = false) {
        if immediately && isSearchingObjects { return }
        stopObjectSearch()
        objectSearchResults = []
        objectSearchNotice = nil

        let query = objectSearchText.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard query.count >= 2 else { return }

        objectSearchTask = Task {
            defer {
                if !Task.isCancelled {
                    isSearchingObjects = false
                    objectSearchTask = nil
                }
            }
            do {
                if !immediately {
                    try await Task.sleep(for: .milliseconds(300))
                }
                try Task.checkCancellation()
                isSearchingObjects = true
                let items = try await session.apiClient.searchCommissionObjects(query: query)
                try Task.checkCancellation()
                objectSearchResults = CommissionObjectSearchRow.grouped(items)
                if objectSearchResults.isEmpty {
                    objectSearchNotice = "Keine passenden Objekte gefunden."
                }
                if immediately {
                    session.commissionStore.rememberCommissionObjectSearch(query)
                }
            } catch {
                guard !Task.isCancelled, !error.isRequestCancellation else { return }
                objectSearchNotice = "Die Objektsuche konnte nicht geladen werden. \(error.localizedDescription)"
            }
        }
    }

    private func stopObjectSearch() {
        objectSearchTask?.cancel()
        objectSearchTask = nil
        isSearchingObjects = false
    }

    private func selectObject(_ item: CommissionObjectChoice) {
        if normalizedText(contactPerson) == nil || normalizedText(contactPerson) == selectedObject?.tenantName {
            contactPerson = item.tenantName ?? ""
        }
        session.commissionStore.rememberCommissionObjectSearch(objectSearchText)
        stopObjectSearch()
        selectedObject = item
        objectSearchResults = []
        objectSearchNotice = nil
    }

    private func normalizedText(_ value: String) -> String? {
        let result = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return result.isEmpty ? nil : result
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

    var body: some View {
        if let level = CommissionObjectLevel(rawValue: item.objectType) {
            let title = item.displayTitle(at: level)
            VStack(alignment: .leading, spacing: 5) {
                Label(title, systemImage: level.icon)
                    .font(.headline)
                Text(item.displayDetails(at: level, includeNumber: true))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let address = item.useUnit?.address ?? item.building?.address ?? item.economicUnit.address,
                   address != title {
                    Text(address)
                        .font(.caption)
                }
                if level != .economicUnit, let name = item.economicUnit.name {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text(item.label)
        }
    }
}

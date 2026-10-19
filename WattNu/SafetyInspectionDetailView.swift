import PhotosUI
import SwiftUI
import UIKit

struct SafetyInspectionDetailView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var inspections: SafetyInspectionOfflineStore
    @Environment(\.scenePhase) private var scenePhase

    let jobId: Int

    @State private var job: SafetyInspectionJob?
    @State private var overallNote = ""
    @State private var storedOverallNote = ""
    @State private var isLoading = false
    @State private var isCompleting = false
    @State private var completionConfirmationPresented = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && job == nil {
                ProgressView(
                    "Prüfauftrag wird geladen …"
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
            } else if let job {
                Form {
                    Section("Prüfung") {
                        LabeledContent("Prüfgruppe") {
                            Text(job.group.name)
                                .multilineTextAlignment(
                                    .trailing
                                )
                        }

                        LabeledContent("Status") {
                            Text(job.statusLabel)
                                .foregroundStyle(
                                    job.isOverdue
                                    ? Color.red
                                    : Color.secondary
                                )
                        }

                        LabeledContent("Auszuführen") {
                            Text(
                                "\(Formatters.dateText(job.dueFrom)) "
                                + "bis "
                                + "\(Formatters.dateText(job.dueTo))"
                            )
                            .multilineTextAlignment(.trailing)
                        }

                        if job.isOverdue {
                            Label(
                                "Dieser Prüfauftrag ist überfällig.",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(.red)
                        }

                        if let assignedUser = job.assignedUser {
                            LabeledContent("Zuständig") {
                                Text(
                                    assignedUser.displayName
                                )
                            }
                        }

                        if let department = job.department {
                            LabeledContent("Abteilung") {
                                Text(department.name)
                            }
                        }
                    }

                    Section("Objekt") {
                        LabeledContent("Adresse") {
                            Text(job.objectTitle)
                                .multilineTextAlignment(.trailing)
                        }

                        if let location = job.object.location,
                           !location.isEmpty {
                            LabeledContent("Lage") {
                                Text(location)
                                    .multilineTextAlignment(.trailing)
                            }
                        }

                        switch job.object.level {
                        case "economic_unit":
                            if let value = job.object.economicUnitIdnum {
                                LabeledContent("Wirtschaftseinheit", value: value)
                            }
                        case "building":
                            if let value = job.object.buildingIdnum {
                                LabeledContent("Gebäude", value: value)
                            }
                        case "use_unit":
                            if let value = job.object.useUnitIdnum {
                                LabeledContent("Nutzungseinheit", value: value)
                            }
                        default:
                            EmptyView()
                        }
                    }

                    ForEach(resultSections(job.results ?? [])) { section in
                        Section(section.title) {
                            ForEach(section.results) { result in
                                NavigationLink {
                                    SafetyInspectionResultEditorView(
                                        jobId: job.id,
                                        initialResult: result,
                                        canEdit: job.canEdit,
                                        onChanged: { updatedResult in
                                            updateCachedResult(updatedResult)
                                        }
                                    )
                                } label: {
                                    SafetyInspectionResultRowView(result: result)
                                }
                            }
                        }
                        .textCase(nil)
                    }

                    if job.canEdit {
                        Section("Abschluss") {
                            TextField(
                                "Gesamthinweis",
                                text: $overallNote,
                                axis: .vertical
                            )
                            .lineLimit(3...8)

                            Button {
                                completionConfirmationPresented = true
                            } label: {
                                HStack {
                                    Spacer()

                                    if isCompleting {
                                        ProgressView()
                                    } else {
                                        Label(
                                            "Prüfung abschließen",
                                            systemImage: "checkmark.seal.fill"
                                        )
                                    }

                                    Spacer()
                                }
                            }
                            .disabled(
                                isCompleting
                                || job.results?.isEmpty != false
                            )
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Prüfauftrag nicht verfügbar",
                    systemImage: "exclamationmark.triangle"
                )
            }
        }
        .navigationTitle("Prüfauftrag")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(
                placement: .topBarTrailing
            ) {
                Button {
                    Task {
                        await loadJob()
                    }
                } label: {
                    Image(
                        systemName: "arrow.clockwise"
                    )
                }
                .disabled(isLoading)
            }
        }
        .task {
            await loadJob()
        }
        .onChange(of: inspections.revision) { _, _ in
            if let cached = try? inspections.cachedJob(jobId) {
                acceptJob(cached)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await loadJob()
                }
            }
        }
        .confirmationDialog(
            "Prüfung abschließen?",
            isPresented: $completionConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Prüfung abschließen") {
                Task {
                    await completeJob()
                }
            }

            Button("Abbrechen", role: .cancel) {
            }
        } message: {
            Text(
                "Nach dem Abschluss können die "
                + "Prüfpunkte nicht mehr verändert werden."
            )
        }
        .alert(
            "Fehler",
            isPresented: Binding(
                get: {
                    errorMessage != nil
                },
                set: { visible in
                    if !visible {
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

    private func loadJob() async {
        isLoading = true

        if let cached = try? inspections.cachedJob(jobId) {
            acceptJob(cached)
        }

        defer {
            isLoading = false
        }

        do {
            let loadedJob = try await session.apiClient
                .fetchSafetyInspection(id: jobId)

            acceptJob(loadedJob)
        } catch {
            if error.isRequestCancellation {
                return
            }

            errorMessage = error.localizedDescription
        }
    }

    private func acceptJob(_ value: SafetyInspectionJob) {
        let savedNote = value.overallNote ?? ""
        if overallNote == storedOverallNote {
            overallNote = savedNote
        }
        storedOverallNote = savedNote
        job = value
    }

    private func completeJob() async {
        guard !isCompleting else {
            return
        }

        isCompleting = true

        defer {
            isCompleting = false
        }

        do {
            let completedJob = try await session.apiClient
                .completeSafetyInspection(
                    jobId: jobId,
                    overallNote: normalizedOverallNote
                )
            acceptJob(completedJob)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private struct ResultSection: Identifiable {
        let id: Int
        let key: String?
        let title: String
        var results: [SafetyInspectionResult]
    }

    private func resultSections(_ results: [SafetyInspectionResult]) -> [ResultSection] {
        var sections: [ResultSection] = []
        let orderedResults = results.sorted {
            if $0.positionIndex == $1.positionIndex { return $0.id < $1.id }
            return $0.positionIndex < $1.positionIndex
        }
        for result in orderedResults {
            if let lastIndex = sections.indices.last,
               sections[lastIndex].key == result.sectionKey {
                sections[lastIndex].results.append(result)
            } else {
                sections.append(ResultSection(
                    id: result.id,
                    key: result.sectionKey,
                    title: result.sectionTitle ?? "Prüfpunkte",
                    results: [result]
                ))
            }
        }
        return sections
    }

    private func updateCachedResult(
        _ result: SafetyInspectionResult
    ) {
        guard var currentJob = job,
              var results = currentJob.results,
              let index = results.firstIndex(
                where: {
                    $0.id == result.id
                }
              ) else {
            return
        }

        results[index] = result
        currentJob.results = results

        currentJob.progress.checkedCount =
            results.filter {
                $0.state != "not_checked"
            }.count

        currentJob.progress.photoCount =
            results.reduce(0) {
                $0 + $1.photos.count
            }

        job = currentJob
    }

    private var normalizedOverallNote: String? {
        normalizedText(overallNote)
    }

    private func normalizedText(
        _ value: String
    ) -> String? {
        let normalized = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return normalized.isEmpty
        ? nil
        : normalized
    }
}

struct SafetyInspectionResultRowView: View {
    let result: SafetyInspectionResult

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(result.positionIndex + 1)")
                .font(.caption)
                .fontWeight(.bold)
                .frame(width: 28, height: 28)
                .background(
                    statusColor.opacity(0.15)
                )
                .foregroundStyle(statusColor)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 5) {
                if let catalogPosition = result.catalogPosition,
                   !catalogPosition.isEmpty {
                    Text("Katalogposition: \(catalogPosition)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Text(result.title)
                    .foregroundStyle(.primary)

                Text(result.stateLabel)
                    .font(.caption)
                    .foregroundStyle(statusColor)

                if !result.photos.isEmpty {
                    Label(
                        "\(result.photos.count) Fotos",
                        systemImage: "photo.on.rectangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statusColor: Color {
        switch result.state {
        case "no_defect":
            return .green
        case "not_present":
            return .gray
        case "defect_info":
            return .orange
        case "defect_urgent":
            return .red
        default:
            return .secondary
        }
    }
}

struct SafetyInspectionResultEditorView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var inspections: SafetyInspectionOfflineStore
    @Environment(\.dismiss) private var dismiss

    let jobId: Int
    let canEdit: Bool
    let onChanged: (SafetyInspectionResult) -> Void

    @State private var result: SafetyInspectionResult
    @State private var selectedState: String
    @State private var note: String
    @State private var immediateAction: String
    @State private var thumbnails: [Int: UIImage] = [:]
    @State private var selectedPhoto: SafetyInspectionPhoto?
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var photoPickerPresented = false
    @State private var cameraPresented = false
    @State private var sourceDialogPresented = false
    @State private var isSaving = false
    @State private var isUploading = false
    @State private var deletingPhotoIds: Set<Int> = []
    @State private var errorMessage: String?

    private let photoColumns = [
        GridItem(
            .adaptive(
                minimum: 100,
                maximum: 150
            ),
            spacing: 10
        )
    ]

    init(
        jobId: Int,
        initialResult: SafetyInspectionResult,
        canEdit: Bool,
        onChanged: @escaping (
            SafetyInspectionResult
        ) -> Void
    ) {
        self.jobId = jobId
        self.canEdit = canEdit
        self.onChanged = onChanged

        _result = State(
            initialValue: initialResult
        )
        _selectedState = State(
            initialValue: initialResult.state
        )
        _note = State(
            initialValue: initialResult.note ?? ""
        )
        _immediateAction = State(
            initialValue:
                initialResult.immediateAction ?? ""
        )
    }

    var body: some View {
        Form {
            Section("Prüfpunkt") {
                if let sectionTitle = result.sectionTitle {
                    Text(sectionTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let catalogPosition = result.catalogPosition,
                   !catalogPosition.isEmpty {
                    LabeledContent("Katalogposition", value: catalogPosition)
                }
                
                Text(result.title)
                    .font(.headline)

                if let description = result.description,
                   !description.isEmpty {
                    Text(description)
                        .foregroundStyle(.secondary)
                }

                if let helpText = result.helpText,
                   !helpText.isEmpty {
                    Label(
                        helpText,
                        systemImage: "info.circle"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Ergebnis") {
                Picker(
                    "Bewertung",
                    selection: $selectedState
                ) {
                    ForEach(availableChoices) { choice in
                        Text(choice.label)
                            .tag(choice.rawValue)
                    }
                }
                .disabled(!canEdit)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Feststellung")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $note)
                        .frame(minHeight: 90)
                        .disabled(!canEdit)
                }

                if isDefectState {
                    VStack(
                        alignment: .leading,
                        spacing: 6
                    ) {
                        Text("Sofortmaßnahme")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextEditor(
                            text: $immediateAction
                        )
                        .frame(minHeight: 75)
                        .disabled(!canEdit)
                    }
                }

                if photoRequired {
                    Label(
                        "Für dieses Ergebnis ist mindestens "
                        + "ein Foto erforderlich.",
                        systemImage: "camera.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(
                        result.photos.isEmpty
                        ? Color.red
                        : Color.green
                    )
                }
            }

            Section("Fotos") {
                if result.photos.isEmpty {
                    ContentUnavailableView(
                        "Keine Fotos",
                        systemImage: "photo.on.rectangle",
                        description: Text(
                            "Zu diesem Prüfpunkt wurden noch "
                            + "keine Fotos gespeichert."
                        )
                    )
                    .frame(minHeight: 130)
                } else {
                    LazyVGrid(
                        columns: photoColumns,
                        spacing: 10
                    ) {
                        ForEach(result.photos) { photo in
                            photoTile(photo)
                        }
                    }
                    .padding(.vertical, 6)
                }

                if canEdit {
                    Button {
                        sourceDialogPresented = true
                    } label: {
                        HStack {
                            Spacer()

                            if isUploading {
                                ProgressView()
                            } else {
                                Label(
                                    "Fotos hinzufügen",
                                    systemImage: "camera.fill"
                                )
                            }

                            Spacer()
                        }
                    }
                    .disabled(isUploading)
                }
            }
            
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if canEdit {
                Button {
                    Task {
                        await saveResult()
                    }
                } label: {
                    HStack {
                        Spacer()

                        if isSaving {
                            ProgressView()
                        } else {
                            Label(
                                "Prüfpunkt speichern",
                                systemImage: "checkmark"
                            )
                        }

                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isSaving || isUploading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.bar)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadThumbnails()
        }
        .onChange(of: inspections.revision) { _, _ in
            if let cached = try? inspections.cachedJob(jobId),
               let updated = cached.results?.first(where: { $0.id == result.id }) {
                let previous = Dictionary(
                    uniqueKeysWithValues: result.photos.map {
                        ($0.publicId, $0.id)
                    }
                )
                for photo in updated.photos {
                    if let oldId = previous[photo.publicId],
                       let image = thumbnails[oldId] {
                        thumbnails[photo.id] = image
                    }
                }
                result.photos = updated.photos
            }
        }
        .confirmationDialog(
            "Foto hinzufügen",
            isPresented: $sourceDialogPresented,
            titleVisibility: .visible
        ) {
            if UIImagePickerController
                .isSourceTypeAvailable(.camera) {
                Button("Kamera") {
                    cameraPresented = true
                }
            }

            Button("Fotomediathek") {
                photoPickerPresented = true
            }

            Button("Abbrechen", role: .cancel) {
            }
        }
        .photosPicker(
            isPresented: $photoPickerPresented,
            selection: $selectedPhotoItems,
            maxSelectionCount: 0,
            matching: .images
        )
        .onChange(
            of: selectedPhotoItems
        ) { _, newItems in
            guard !newItems.isEmpty else {
                return
            }

            Task {
                await importPhotoItems(newItems)
            }
        }
        .sheet(
            isPresented: $cameraPresented
        ) {
            CameraImagePicker { image in
                Task {
                    await uploadImage(
                        image,
                        source: "camera"
                    )
                }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $selectedPhoto) { photo in
            SafetyInspectionPhotoPreview(
                photo: photo
            )
            .environmentObject(session)
        }
        .alert(
            "Fehler",
            isPresented: Binding(
                get: {
                    errorMessage != nil
                },
                set: { visible in
                    if !visible {
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

    @ViewBuilder
    private func photoTile(
        _ photo: SafetyInspectionPhoto
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                selectedPhoto = photo
            } label: {
                ZStack {
                    RoundedRectangle(
                        cornerRadius: 12
                    )
                    .fill(
                        Color.secondary.opacity(0.12)
                    )

                    if let image = thumbnails[photo.id] {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 112)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 12
                    )
                )
            }
            .buttonStyle(.plain)

            if canEdit {
                Button(role: .destructive) {
                    Task {
                        await deletePhoto(photo)
                    }
                } label: {
                    if deletingPhotoIds.contains(
                        photo.id
                    ) {
                        ProgressView()
                            .padding(7)
                    } else {
                        Image(systemName: "trash.fill")
                            .font(.caption)
                            .padding(8)
                            .background(
                                .ultraThinMaterial
                            )
                            .clipShape(Circle())
                    }
                }
                .disabled(
                    deletingPhotoIds.contains(
                        photo.id
                    )
                )
                .padding(5)
            }
        }
    }

    private func saveResult() async {
        guard !isSaving else {
            return
        }

        isSaving = true

        defer {
            isSaving = false
        }

        do {
            let updatedResult =
                try await session.apiClient
                    .updateSafetyInspectionResult(
                        jobId: jobId,
                        resultId: result.id,
                        state: selectedState,
                        note: normalizedText(note),
                        immediateAction:
                            isDefectState
                            ? normalizedText(
                                immediateAction
                            )
                            : nil,
                        version: result.version,
                        baseResult: InspectionResultSnapshot(result)
                    )

            result = updatedResult
            selectedState = updatedResult.state
            note = updatedResult.note ?? ""
            immediateAction =
                updatedResult.immediateAction ?? ""

            onChanged(updatedResult)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importPhotoItems(
        _ items: [PhotosPickerItem]
    ) async {
        defer {
            selectedPhotoItems = []
        }

        for item in items {
            do {
                guard let data = try await item
                    .loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    errorMessage = (
                        "Ein ausgewähltes Bild konnte "
                        + "nicht gelesen werden."
                    )
                    continue
                }

                await uploadImage(
                    image,
                    source: "gallery"
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func uploadImage(
        _ image: UIImage,
        source: String
    ) async {
        let scale = min(
            1,
            2560 / max(image.size.width, image.size.height)
        )
        let size = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1

        let normalized = UIGraphicsImageRenderer(
            size: size,
            format: format
        ).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }

        guard let imageData = normalized.jpegData(compressionQuality: 0.82) else {
            errorMessage = (
                "Das Foto konnte nicht "
                + "vorbereitet werden."
            )
            return
        }

        isUploading = true

        defer {
            isUploading = false
        }

        do {
            let response =
                try await session.apiClient
                    .uploadSafetyInspectionPhoto(
                        jobId: jobId,
                        resultId: result.id,
                        imageData: imageData,
                        source: source
                    )

            if let index = result.photos.firstIndex(
                where: {
                    $0.id == response.item.id
                }
            ) {
                result.photos[index] = response.item
            } else {
                result.photos.append(response.item)
            }

            onChanged(result)
            await loadThumbnail(
                for: response.item
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deletePhoto(
        _ photo: SafetyInspectionPhoto
    ) async {
        guard !deletingPhotoIds.contains(
            photo.id
        ) else {
            return
        }

        deletingPhotoIds.insert(photo.id)

        defer {
            deletingPhotoIds.remove(photo.id)
        }

        do {
            try await session.apiClient
                .deleteSafetyInspectionPhoto(
                    jobId: jobId,
                    resultId: result.id,
                    photoId: photo.id
                )

            result.photos.removeAll {
                $0.id == photo.id
            }
            thumbnails[photo.id] = nil
            onChanged(result)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadThumbnails() async {
        for photo in result.photos {
            if thumbnails[photo.id] == nil {
                await loadThumbnail(for: photo)
            }
        }
    }

    private func loadThumbnail(
        for photo: SafetyInspectionPhoto
    ) async {
        do {
            let data = try await session.apiClient
                .downloadSafetyInspectionPhoto(
                    path: photo.thumbnailPath
                )

            if let image = UIImage(data: data) {
                thumbnails[photo.id] = image
            }
        } catch {
            if !error.isRequestCancellation,
               !InspectionOfflineError.isConnectionError(error),
               errorMessage == nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var availableChoices:
        [SafetyInspectionResultChoice] {

        SafetyInspectionResultChoice.allCases.filter {
            $0 != .notPresent
            || result.allowNotPresent
        }
    }

    private var isDefectState: Bool {
        selectedState == "defect_info"
        || selectedState == "defect_urgent"
    }

    private var photoRequired: Bool {
        switch selectedState {
        case "no_defect":
            return result.photoRequirements.noDefect
        case "not_present":
            return result.photoRequirements.notPresent
        case "defect_info":
            return result.photoRequirements.defectInfo
        case "defect_urgent":
            return result.photoRequirements.defectUrgent
        default:
            return false
        }
    }

    private func normalizedText(
        _ value: String
    ) -> String? {
        let normalized = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return normalized.isEmpty
        ? nil
        : normalized
    }
}

struct SafetyInspectionPhotoPreview: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var inspections: SafetyInspectionOfflineStore
    @Environment(\.dismiss) private var dismiss

    let photo: SafetyInspectionPhoto

    @State private var image: UIImage?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let image {
                    ScrollView(
                        [.horizontal, .vertical]
                    ) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    }
                } else if let errorMessage {
                    ContentUnavailableView(
                        "Foto nicht verfügbar",
                        systemImage:
                            "photo.badge.exclamationmark",
                        description: Text(
                            errorMessage
                        )
                    )
                } else {
                    ProgressView(
                        "Foto wird geladen …"
                    )
                }
            }
            .navigationTitle(photo.sourceLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button("Schließen") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadImage()
            }
        }
    }

    private func loadImage() async {
        do {
            let data = try await session.apiClient
                .downloadSafetyInspectionPhoto(
                    path: photo.contentPath
                )

            image = UIImage(data: data)

            if image == nil {
                errorMessage = (
                    "Die Bilddatei konnte "
                    + "nicht gelesen werden."
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum SafetyInspectionResultChoice: String,
    CaseIterable,
    Identifiable {

    case notChecked = "not_checked"
    case noDefect = "no_defect"
    case notPresent = "not_present"
    case defectInfo = "defect_info"
    case defectUrgent = "defect_urgent"

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .notChecked:
            return "Nicht geprüft"
        case .noDefect:
            return "Ohne Mangel"
        case .notPresent:
            return "Nicht vorhanden"
        case .defectInfo:
            return "Mangel (Info)"
        case .defectUrgent:
            return "Mangel (dringend)"
        }
    }
}

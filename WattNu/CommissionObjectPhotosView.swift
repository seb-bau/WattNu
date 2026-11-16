import SwiftUI
import UIKit

enum CommissionObjectPhotoFilter:
    String,
    CaseIterable,
    Identifiable {

    case all = "Alle"
    case building = "Gebäude"
    case useUnit = "Wohnung"

    var id: String {
        rawValue
    }

    func includes(
        _ photo: CommissionPhoto
    ) -> Bool {
        switch self {
        case .all:
            return true
        case .building:
            return photo.externalEntityName?
                .caseInsensitiveCompare(
                    "Building"
                ) == .orderedSame
        case .useUnit:
            return photo.externalEntityName?
                .caseInsensitiveCompare(
                    "UseUnit"
                ) == .orderedSame
        }
    }
}

struct CommissionObjectPhotosView: View {
    @EnvironmentObject private var session: SessionStore

    let commission: Commission

    @State private var photos: [CommissionPhoto] = []
    @State private var thumbnails: [Int: UIImage] = [:]
    @State private var thumbnailItems: [Int: CommissionPhoto] = [:]
    @State private var selectedPhoto: CommissionPhoto?
    @State private var selectedFilter:
        CommissionObjectPhotoFilter = .all
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?

    private let columns = [
        GridItem(
            .adaptive(
                minimum: 120,
                maximum: 180
            ),
            spacing: 12
        )
    ]

    private var filteredPhotos: [CommissionPhoto] {
        photos.filter {
            selectedFilter.includes($0)
        }
    }

    var body: some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: 16
            ) {
                Picker(
                    "Bestandsobjekt",
                    selection: $selectedFilter
                ) {
                    ForEach(
                        CommissionObjectPhotoFilter
                            .allCases
                    ) { filter in
                        Text(filter.rawValue)
                            .tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                if isLoading && photos.isEmpty {
                    ProgressView(
                        "Fotos werden geladen …"
                    )
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 240
                    )
                } else if filteredPhotos.isEmpty {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage:
                            "photo.on.rectangle.angled",
                        description: Text(
                            emptyDescription
                        )
                    )
                    .frame(minHeight: 240)
                } else {
                    LazyVGrid(
                        columns: columns,
                        spacing: 12
                    ) {
                        ForEach(
                            filteredPhotos
                        ) { photo in
                            photoButton(photo)
                        }
                    }
                }
            }
            .padding()
        }
        .refreshForCommissionChanges { await loadPhotos(refresh: false) }
        .refreshOnActivation(id: commission.id) {
            await loadPhotos()
        }
        .refreshable {
            await loadPhotos()
        }
        .sheet(
            item: $selectedPhoto
        ) { photo in
            CommissionPhotoDetailView(
                commission: commission,
                initialPhoto: photo,
                allowsEditing: false,
                onUpdated: { _ in
                },
                onDeleted: { _ in
                }
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

    private func photoButton(
        _ photo: CommissionPhoto
    ) -> some View {
        Button {
            selectedPhoto = photo
        } label: {
            VStack(
                alignment: .leading,
                spacing: 8
            ) {
                CommissionPhotoThumbnail(
                    image: thumbnails[photo.id],
                    height: 130
                )

                Text(photo.displayCaption)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Label(
                    photo.entityLabel,
                    systemImage: (
                        photo.externalEntityName?
                            .caseInsensitiveCompare(
                                "Building"
                            ) == .orderedSame
                        ? "building.2"
                        : "door.left.hand.open"
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyTitle: String {
        switch selectedFilter {
        case .all:
            return "Keine Bestandsfotos"
        case .building:
            return "Keine Gebäudefotos"
        case .useUnit:
            return "Keine Wohnungsfotos"
        }
    }

    private var emptyDescription: String {
        switch selectedFilter {
        case .all:
            return (
                "Zu Gebäude und Wohnung "
                + "wurden keine Fotos gefunden."
            )
        case .building:
            return (
                "Zu diesem Gebäude wurden "
                + "keine Fotos gefunden."
            )
        case .useUnit:
            return (
                "Zu dieser Wohnung wurden "
                + "keine Fotos gefunden."
            )
        }
    }

    private func loadPhotos(refresh: Bool = true) async {
        let showLoading = !hasLoaded
        if showLoading { isLoading = true }

        defer {
            if showLoading { isLoading = false }
        }

        do {
            let loadedPhotos = try await session.apiClient
                .fetchCommissionPhotos(
                    commissionId: commission.id,
                    context: "object",
                    refresh: refresh
                )

            guard !Task.isCancelled else { return }
            let photosToLoad = CommissionMediaRefresh.itemsRequiringThumbnails(
                loadedPhotos, previousItems: thumbnailItems, thumbnails: thumbnails
            )
            if photos != loadedPhotos {
                photos = loadedPhotos
                thumbnails = CommissionMediaRefresh.retainedThumbnails(thumbnails, for: loadedPhotos)
                thumbnailItems = CommissionMediaRefresh.retainedThumbnails(thumbnailItems, for: loadedPhotos)
            }
            if !hasLoaded { hasLoaded = true }

            for photo in photosToLoad {
                guard !Task.isCancelled else { return }
                await loadThumbnail(
                    for: photo
                )
            }
        } catch {
            if error.isRequestCancellation {
                return
            }

            errorMessage = error.localizedDescription
        }
    }

    private func loadThumbnail(
        for photo: CommissionPhoto
    ) async {
        do {
            let data = try await session.apiClient
                .downloadCommissionPhoto(
                    path: photo.thumbnailPath
                )

            guard !Task.isCancelled, photos.contains(photo) else { return }
            if let image = UIImage(
                data: data
            ) {
                thumbnails[
                    photo.id
                ] = image
                thumbnailItems[photo.id] = photo
            }
        } catch {
            if error.isRequestCancellation {
                return
            }

            if errorMessage == nil {
                errorMessage = error.localizedDescription
            }
        }
    }
}

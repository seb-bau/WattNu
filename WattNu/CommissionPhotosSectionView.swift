import PhotosUI
import SwiftUI
import UIKit

struct CommissionPhotosSectionView: View {
    @EnvironmentObject private var session: SessionStore

    let commission: Commission

    @State private var photos: [CommissionPhoto] = []
    @State private var thumbnails: [Int: UIImage] = [:]
    @State private var selectedPhoto: CommissionPhoto?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var photoPickerPresented = false
    @State private var cameraPresented = false
    @State private var sourceDialogPresented = false
    @State private var isLoading = false
    @State private var isUploading = false
    @State private var errorMessage: String?

    private let columns = [
        GridItem(
            .adaptive(
                minimum: 92,
                maximum: 140
            ),
            spacing: 10
        )
    ]

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack {
                Text("Fotos")
                    .font(.headline)

                Spacer()

                if isUploading {
                    ProgressView()
                }

                if commission.canEditValue
                    && commission.isActionableValue {
                    Button {
                        sourceDialogPresented = true
                    } label: {
                        Label(
                            "Hinzufügen",
                            systemImage: "camera.fill"
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(isUploading)
                }
            }

            if isLoading && photos.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if photos.isEmpty {
                ContentUnavailableView(
                    "Keine Fotos",
                    systemImage: "photo.on.rectangle",
                    description: Text(
                        "Zu diesem Auftrag wurden noch keine Fotos gespeichert."
                    )
                )
                .frame(minHeight: 130)
            } else {
                LazyVGrid(
                    columns: columns,
                    spacing: 10
                ) {
                    ForEach(photos) { photo in
                        Button {
                            selectedPhoto = photo
                        } label: {
                            ZStack {
                                RoundedRectangle(
                                    cornerRadius: 12
                                )
                                .fill(
                                    Color.secondary.opacity(
                                        0.12
                                    )
                                )

                                if let image = thumbnails[
                                    photo.id
                                ] {
                                    Image(
                                        uiImage: image
                                    )
                                    .resizable()
                                    .scaledToFill()
                                } else {
                                    ProgressView()
                                }
                            }
                            .frame(height: 110)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 12
                                )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding()
        .background(.thinMaterial)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18
            )
        )
        .task {
            await loadPhotos()
        }
        .refreshable {
            await loadPhotos()
        }
        .confirmationDialog(
            "Foto hinzufügen",
            isPresented: $sourceDialogPresented,
            titleVisibility: .visible
        ) {
            if UIImagePickerController.isSourceTypeAvailable(
                .camera
            ) {
                Button("Kamera") {
                    cameraPresented = true
                }
            }

            Button("Fotomediathek") {
                photoPickerPresented = true
            }

            Button(
                "Abbrechen",
                role: .cancel
            ) {
            }
        }
        .photosPicker(
            isPresented: $photoPickerPresented,
            selection: $selectedPhotoItem,
            matching: .images
        )
        .onChange(
            of: selectedPhotoItem
        ) { _, newItem in
            guard let newItem else {
                return
            }

            Task {
                await importPhotoItem(
                    newItem
                )
            }
        }
        .sheet(
            isPresented: $cameraPresented
        ) {
            CameraImagePicker { image in
                Task {
                    await uploadImage(image)
                }
            }
            .ignoresSafeArea()
        }
        .sheet(
            item: $selectedPhoto
        ) { photo in
            CommissionPhotoDetailView(
                commission: commission,
                initialPhoto: photo,
                onUpdated: { updatedPhoto in
                    replacePhoto(
                        updatedPhoto
                    )
                },
                onDeleted: { photoId in
                    photos.removeAll {
                        $0.id == photoId
                    }
                    thumbnails[
                        photoId
                    ] = nil
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

    private func loadPhotos() async {
        isLoading = true

        defer {
            isLoading = false
        }

        do {
            photos = try await session.apiClient
                .fetchCommissionPhotos(
                    commissionId: commission.id
                )

            thumbnails = [:]

            for photo in photos {
                await loadThumbnail(
                    for: photo
                )
            }
        } catch {
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

            if let image = UIImage(
                data: data
            ) {
                thumbnails[
                    photo.id
                ] = image
            }
        } catch {
            if errorMessage == nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func importPhotoItem(
        _ item: PhotosPickerItem
    ) async {
        defer {
            selectedPhotoItem = nil
        }

        do {
            guard let data = try await item.loadTransferable(
                type: Data.self
            ),
            let image = UIImage(data: data) else {
                errorMessage = "Das ausgewählte Bild konnte nicht gelesen werden."
                return
            }

            await uploadImage(image)

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func uploadImage(
        _ image: UIImage
    ) async {
        guard !isUploading else {
            return
        }

        guard let imageData = image.jpegData(
            compressionQuality: 0.82
        ) else {
            errorMessage = "Das Foto konnte nicht vorbereitet werden."
            return
        }

        isUploading = true

        defer {
            isUploading = false
        }

        do {
            let response = try await session.apiClient
                .uploadCommissionPhoto(
                    commissionId: commission.id,
                    imageData: imageData,
                    caption: nil
                )

            if let index = photos.firstIndex(
                where: {
                    $0.id == response.item.id
                }
            ) {
                photos[
                    index
                ] = response.item
            } else {
                photos.insert(
                    response.item,
                    at: 0
                )
            }

            await loadThumbnail(
                for: response.item
            )

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func replacePhoto(
        _ photo: CommissionPhoto
    ) {
        guard let index = photos.firstIndex(
            where: {
                $0.id == photo.id
            }
        ) else {
            return
        }

        photos[index] = photo
    }
}

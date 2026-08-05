import SwiftUI
import UIKit

struct CommissionPhotoDetailView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    let commission: Commission
    let onUpdated: (CommissionPhoto) -> Void
    let onDeleted: (Int) -> Void
    let allowsEditing: Bool
    let allowsDeleting: Bool

    @State private var photo: CommissionPhoto
    @State private var image: UIImage?
    @State private var caption: String
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var deleteConfirmationPresented = false
    @State private var errorMessage: String?

    init(
        commission: Commission,
        initialPhoto: CommissionPhoto,
        allowsEditing: Bool = true,
        allowsDeleting: Bool = true,
        onUpdated: @escaping (
            CommissionPhoto
        ) -> Void,
        onDeleted: @escaping (
            Int
        ) -> Void
    ) {
        self.commission = commission
        self.allowsEditing = allowsEditing
        self.allowsDeleting = allowsDeleting
        self.onUpdated = onUpdated
        self.onDeleted = onDeleted
        _photo = State(
            initialValue: initialPhoto
        )
        _caption = State(
            initialValue: initialPhoto.caption
            ?? initialPhoto.pictureTypeName
            ?? ""
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: 16
                ) {
                    if isLoading && image == nil {
                        ProgressView(
                            "Foto wird geladen …"
                        )
                        .frame(
                            maxWidth: .infinity,
                            minHeight: 300
                        )
                    } else if let image {
                        Image(
                            uiImage: image
                        )
                        .resizable()
                        .scaledToFit()
                        .frame(
                            maxWidth: .infinity
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 14
                            )
                        )
                    }

                    VStack(
                        alignment: .leading,
                        spacing: 6
                    ) {
                        Text("Beschreibung")
                            .font(.headline)

                        TextEditor(
                            text: $caption
                        )
                        .frame(minHeight: 90)
                        .padding(6)
                        .background(
                            Color.secondary.opacity(
                                0.08
                            )
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 10
                            )
                        )
                        .disabled(
                            !allowsEditing
                            || !commission.canEditValue
                        )
                    }

                    HStack {
                        Text(photo.sourceLabel)

                        Spacer()

                        if let uploadedBy = photo.uploadedBy {
                            Text(
                                uploadedBy.displayName
                            )
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Text(
                        Formatters.dateTimeText(
                            photo.createdAt
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    
                    if allowsEditing
                        && !allowsDeleting {
                        Label(
                            "Bereits an Wowiport übertragen. "
                            + "Das Foto kann nur dort entfernt werden.",
                            systemImage: "lock.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle(
                allowsEditing
                ? "Auftragsfoto"
                : "Bestandsfoto"
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button("Schließen") {
                        dismiss()
                    }
                }

                if allowsEditing
                    && commission.canEditValue {
                    ToolbarItem(
                        placement: .primaryAction
                    ) {
                        Button("Speichern") {
                            Task {
                                await saveCaption()
                            }
                        }
                        .disabled(isSaving)
                    }
                }

                if allowsEditing
                    && allowsDeleting
                    && commission.canEditValue {
                    ToolbarItem(
                        placement: .bottomBar
                    ) {
                        Button(
                            role: .destructive
                        ) {
                            deleteConfirmationPresented = true
                        } label: {
                            Label(
                                "Foto löschen",
                                systemImage: "trash"
                            )
                        }
                    }
                }
            }
            .task {
                await loadImage()
            }
            .confirmationDialog(
                "Foto wirklich löschen?",
                isPresented: $deleteConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button(
                    "Foto löschen",
                    role: .destructive
                ) {
                    Task {
                        await deletePhoto()
                    }
                }

                Button(
                    "Abbrechen",
                    role: .cancel
                ) {
                }
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
    }

    private func loadImage() async {
        isLoading = true

        defer {
            isLoading = false
        }

        do {
            let data = try await session.apiClient
                .downloadCommissionPhoto(
                    path: photo.contentPath
                )

            image = UIImage(
                data: data
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveCaption() async {
        isSaving = true

        defer {
            isSaving = false
        }

        let normalizedCaption = caption
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        do {
            let updatedPhoto = try await session.apiClient
                .updateCommissionPhoto(
                    commissionId: commission.id,
                    photoId: photo.id,
                    caption: (
                        normalizedCaption.isEmpty
                        ? nil
                        : normalizedCaption
                    )
                )

            photo = updatedPhoto
            caption = updatedPhoto.caption ?? ""
            onUpdated(updatedPhoto)

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deletePhoto() async {
        do {
            try await session.apiClient
                .deleteCommissionPhoto(
                    commissionId: commission.id,
                    photoId: photo.id
                )

            onDeleted(photo.id)
            dismiss()

        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

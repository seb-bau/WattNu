import QuickLook
import SwiftUI
import UIKit

struct CommissionAttachmentsSectionView: View {
    @EnvironmentObject private var session: SessionStore

    let commission: Commission

    @State private var attachments: [CommissionAttachment] = []
    @State private var thumbnails: [Int: UIImage] = [:]
    @State private var thumbnailItems: [Int: CommissionAttachment] = [:]
    @State private var previewItem: CommissionAttachmentPreview?
    @State private var previewFileURL: URL?
    @State private var loadingAttachmentId: Int?
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoading || !attachments.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Dateien")
                            .font(.headline)

                        Spacer()

                        if isLoading {
                            ProgressView()
                        }
                    }

                    if isLoading && attachments.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView("Dateien werden geladen …")
                            Spacer()
                        }
                        .padding(.vertical, 20)
                    } else if !attachments.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(
                                Array(attachments.enumerated()),
                                id: \.element.id
                            ) { index, attachment in
                                Button {
                                    Task {
                                        await openAttachment(attachment)
                                    }
                                } label: {
                                    attachmentRow(attachment)
                                }
                                .buttonStyle(.plain)
                                .disabled(loadingAttachmentId != nil)

                                if index < attachments.count - 1 {
                                    Divider()
                                        .padding(.leading, 70)
                                }
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
                    RoundedRectangle(cornerRadius: 18)
                )
                .padding(.top, 18)
            }
        }
        .refreshForCommissionChanges { await loadAttachments(refresh: false) }
        .refreshOnActivation(id: commission.id) {
            await loadAttachments()
        }
        .sheet(
            item: $previewItem,
            onDismiss: clearPreviewFile
        ) { item in
            if QLPreviewController.canPreview(item.fileURL as NSURL) {
                CommissionAttachmentPreviewView(fileURL: item.fileURL)
                    .ignoresSafeArea()
            } else {
                NavigationStack {
                    ContentUnavailableView {
                        Label("Keine Vorschau verfügbar", systemImage: "doc")
                    } description: {
                        Text("Diese Datei kann in einer anderen App geöffnet werden.")
                    } actions: {
                        ShareLink(item: item.fileURL) {
                            Label("Datei teilen oder öffnen", systemImage: "square.and.arrow.up")
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Schließen") { previewItem = nil }
                        }
                    }
                }
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

    @ViewBuilder
    private func attachmentRow(
        _ attachment: CommissionAttachment
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: 10
                )
                .fill(
                    Color.secondary.opacity(
                        0.12
                    )
                )

                if let image = thumbnails[
                    attachment.id
                ] {
                    Image(
                        uiImage: image
                    )
                    .resizable()
                    .scaledToFill()
                } else {
                    Image(
                        systemName: attachment.iconName
                    )
                    .font(.title2)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(
                width: 54,
                height: 54
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 10
                )
            )

            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                Text(
                    attachment.originalFilename
                )
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(2)

                Text(
                    "\(attachment.sourceLabel) · \(attachment.sizeLabel)"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if let createdAt = attachment.createdAt {
                    Text(
                        Formatters.dateTimeText(
                            createdAt
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if loadingAttachmentId
                == attachment.id {
                ProgressView()
            } else {
                Image(
                    systemName: "chevron.right"
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private func loadAttachments(refresh: Bool = true) async {
        let showLoading = !hasLoaded
        if showLoading { isLoading = true }

        defer {
            if showLoading { isLoading = false }
        }

        do {
            let loadedAttachments = try await session.apiClient
                .fetchCommissionAttachments(
                    commissionId: commission.id,
                    refresh: refresh
                )

            guard !Task.isCancelled else { return }
            let attachmentsToLoad = CommissionMediaRefresh.itemsRequiringThumbnails(
                loadedAttachments, previousItems: thumbnailItems, thumbnails: thumbnails
            )
            if attachments != loadedAttachments {
                attachments = loadedAttachments
                thumbnails = CommissionMediaRefresh.retainedThumbnails(thumbnails, for: loadedAttachments)
                thumbnailItems = CommissionMediaRefresh.retainedThumbnails(thumbnailItems, for: loadedAttachments)
            }
            if !hasLoaded { hasLoaded = true }

            for attachment in attachmentsToLoad
            where attachment.isImage {
                guard !Task.isCancelled else { return }
                await loadThumbnail(
                    for: attachment
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
        for attachment: CommissionAttachment
    ) async {
        guard let thumbnailPath =
            attachment.thumbnailPath else {
            return
        }

        do {
            let data = try await session.apiClient
                .downloadCommissionAttachment(
                    path: thumbnailPath
                )

            guard !Task.isCancelled, attachments.contains(attachment) else { return }
            if let image = UIImage(
                data: data
            ) {
                thumbnails[
                    attachment.id
                ] = image
                thumbnailItems[attachment.id] = attachment
            }
        } catch {
            if error.isRequestCancellation {
                return
            }
        }
    }

    private func openAttachment(
        _ attachment: CommissionAttachment
    ) async {
        guard loadingAttachmentId == nil else {
            return
        }

        loadingAttachmentId = attachment.id

        defer {
            loadingAttachmentId = nil
        }

        do {
            let data = try await session.apiClient
                .downloadCommissionAttachment(
                    path: attachment.contentPath
                )

            guard !Task.isCancelled else { return }
            let fileURL = try CommissionAttachmentPreviewFile.write(data, attachment: attachment)
            previewFileURL = fileURL
            previewItem = CommissionAttachmentPreview(
                attachmentId: attachment.id,
                fileURL: fileURL
            )
        } catch {
            if error.isRequestCancellation {
                return
            }

            errorMessage = error.localizedDescription
        }
    }

    private func clearPreviewFile() {
        if let fileURL = previewFileURL {
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        }
        previewFileURL = nil
    }
}

struct CommissionAttachmentPreview: Identifiable {
    let attachmentId: Int
    let fileURL: URL

    var id: Int {
        attachmentId
    }
}

struct CommissionAttachmentPreviewView:
    UIViewControllerRepresentable {

    let fileURL: URL
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(
            fileURL: fileURL
        )
    }

    func makeUIViewController(
        context: Context
    ) -> UINavigationController {
        let previewController =
            QLPreviewController()

        previewController.dataSource =
            context.coordinator
        previewController.navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Schließen", primaryAction: UIAction { _ in dismiss() }
        )

        return UINavigationController(
            rootViewController:
                previewController
        )
    }

    func updateUIViewController(
        _ uiViewController:
            UINavigationController,
        context: Context
    ) {
    }

    @MainActor
    final class Coordinator:
        NSObject,
        QLPreviewControllerDataSource {

        private let fileURL: URL

        init(
            fileURL: URL
        ) {
            self.fileURL = fileURL
        }

        func numberOfPreviewItems(
            in controller: QLPreviewController
        ) -> Int {
            1
        }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> QLPreviewItem {
            fileURL as NSURL
        }
    }
}


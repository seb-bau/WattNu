import Foundation
import UniformTypeIdentifiers

enum CommissionAttachmentPreviewError: LocalizedError {
    case emptyFile

    var errorDescription: String? {
        "Die Datei ist leer und kann nicht angezeigt werden."
    }
}

enum CommissionAttachmentPreviewFile {
    static func write(_ data: Data, attachment: CommissionAttachment, rootURL: URL = FileManager.default.temporaryDirectory) throws -> URL {
        guard !data.isEmpty else {
            throw CommissionAttachmentPreviewError.emptyFile
        }
        let directoryURL = rootURL.appendingPathComponent("WattNuAttachments", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = directoryURL.appendingPathComponent(attachment.previewFilename)
        do {
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            try? FileManager.default.removeItem(at: directoryURL)
            throw error
        }
        return fileURL
    }
}

extension CommissionAttachment {
    var normalizedMimeType: String {
        mimeType.components(separatedBy: ";")[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var isPDF: Bool {
        normalizedMimeType == "application/pdf" || (originalFilename as NSString).pathExtension.lowercased() == "pdf"
    }

    var previewFilename: String {
        let basename = (originalFilename.replacingOccurrences(of: "\\", with: "/") as NSString).lastPathComponent
        var filename = ["", ".", ".."].contains(basename) ? "Datei-\(id)" : basename
        if normalizedMimeType == "application/pdf", (filename as NSString).pathExtension.lowercased() != "pdf" {
            filename += ".pdf"
        } else if (filename as NSString).pathExtension.isEmpty,
                  let fileExtension = UTType(mimeType: normalizedMimeType)?.preferredFilenameExtension {
            filename += "." + fileExtension
        }
        return filename
    }
}

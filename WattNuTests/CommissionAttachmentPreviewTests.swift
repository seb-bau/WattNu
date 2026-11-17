import Foundation
import QuickLook
import Testing
import UIKit
@testable import WattNu

@MainActor
struct CommissionAttachmentPreviewTests {
    private func attachment(filename: String = "auftrag.pdf", mimeType: String = "application/pdf") throws -> CommissionAttachment {
        let payload: [String: Any] = [
            "id": 12, "commission_id": 34, "source_entity_name": "Commission",
            "original_filename": filename, "mime_type": mimeType, "size_bytes": 100,
            "is_image": false, "content_path": "/api/commissions/34/attachments/12/content"
        ]
        return try JSONDecoder().decode(CommissionAttachment.self, from: JSONSerialization.data(withJSONObject: payload))
    }

    @Test func pdfWithoutAnExtensionGetsAPreviewableFilename() throws {
        let item = try attachment(filename: "Auftragsunterlagen", mimeType: "Application/PDF; charset=binary")
        #expect(item.previewFilename == "Auftragsunterlagen.pdf")
        #expect(item.isPDF)
        #expect(item.iconName == "doc.richtext")
    }

    @Test func existingDocumentExtensionsArePreserved() throws {
        for (filename, mimeType) in [
            ("Auftrag.PDF", "application/octet-stream"),
            ("Auftrag.docx", "application/vnd.openxmlformats-officedocument.wordprocessingml.document"),
            ("Notiz.txt", "text/plain"),
            ("Unterlagen.zip", "application/zip")
        ] {
            #expect(try attachment(filename: filename, mimeType: mimeType).previewFilename == filename)
        }
    }

    @Test func unsafePathsAndMissingNamesStayInsideThePreviewDirectory() throws {
        #expect(try attachment(filename: "../../auftrag.pdf").previewFilename == "auftrag.pdf")
        #expect(try attachment(filename: "C:\\Unterlagen\\auftrag.pdf").previewFilename == "auftrag.pdf")
        #expect(try attachment(filename: "..").previewFilename == "Datei-12.pdf")
        #expect(try attachment(filename: "").previewFilename == "Datei-12.pdf")
    }

    @Test func pdfBytesRemainIntactAndCanBeOpenedByQuickLook() throws {
        let item = try attachment()
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 200))
        let data = renderer.pdfData { context in
            context.beginPage()
            ("Auftrag 34" as NSString).draw(at: CGPoint(x: 20, y: 20), withAttributes: nil)
        }
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let fileURL = try CommissionAttachmentPreviewFile.write(data, attachment: item, rootURL: rootURL)
        #expect(fileURL.lastPathComponent == "auftrag.pdf")
        #expect(try Data(contentsOf: fileURL) == data)
        #expect(QLPreviewController.canPreview(fileURL as NSURL))
    }

    @Test func repeatedAttachmentIdsUseSeparateFiles() throws {
        let item = try attachment()
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let first = try CommissionAttachmentPreviewFile.write(Data("first".utf8), attachment: item, rootURL: rootURL)
        let second = try CommissionAttachmentPreviewFile.write(Data("second".utf8), attachment: item, rootURL: rootURL)
        #expect(first != second)
        #expect(try Data(contentsOf: first) == Data("first".utf8))
        #expect(try Data(contentsOf: second) == Data("second".utf8))
    }

    @Test func emptyDownloadsProduceADescriptiveError() throws {
        let item = try attachment()
        #expect(throws: CommissionAttachmentPreviewError.self) {
            try CommissionAttachmentPreviewFile.write(Data(), attachment: item)
        }
    }
}

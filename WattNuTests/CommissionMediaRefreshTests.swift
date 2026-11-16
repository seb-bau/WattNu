import Foundation
import Testing
@testable import WattNu

@MainActor
struct CommissionMediaRefreshTests {
    private final class Thumbnail {}

    private func photo(_ id: Int, fields: [String: Any] = [:]) throws -> CommissionPhoto {
        let payload: [String: Any] = [
            "id": id, "commission_id": 10, "source": "app", "context": "order",
            "original_filename": "foto.jpg", "mime_type": "image/jpeg", "size_bytes": 5,
            "content_path": "/photos/\(id)/content", "thumbnail_path": "/photos/\(id)/thumbnail"
        ].merging(fields) { _, value in value }
        return try JSONDecoder().decode(CommissionPhoto.self, from: JSONSerialization.data(withJSONObject: payload))
    }

    @Test func repeatedIdenticalRefreshesKeepExistingThumbnails() throws {
        let items = try [photo(1), photo(2)]
        let first = Thumbnail()
        let second = Thumbnail()
        let thumbnails = [1: first, 2: second]
        let previousItems = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        for _ in 0..<30 {
            let refreshed = try JSONDecoder().decode([CommissionPhoto].self, from: JSONEncoder().encode(items))
            let pending = CommissionMediaRefresh.itemsRequiringThumbnails(refreshed, previousItems: previousItems, thumbnails: thumbnails)
            let retained = CommissionMediaRefresh.retainedThumbnails(thumbnails, for: refreshed)
            #expect(pending.isEmpty)
            #expect(retained[1] === first)
            #expect(retained[2] === second)
        }
    }

    @Test func onlyNewAndChangedPhotosReloadWhilePreviousImagesStayVisible() throws {
        let first = try photo(1)
        let second = try photo(2)
        let changed = try photo(2, fields: ["updated_at": "2026-11-16T10:00:00Z", "caption": "Geändert"])
        let added = try photo(3)
        let oldImage = Thumbnail()
        let thumbnails = [1: Thumbnail(), 2: oldImage]
        let items = [first, changed, added]

        let pending = CommissionMediaRefresh.itemsRequiringThumbnails(items, previousItems: [1: first, 2: second], thumbnails: thumbnails)
        let retained = CommissionMediaRefresh.retainedThumbnails(thumbnails, for: items)

        #expect(pending.map(\.id) == [2, 3])
        #expect(retained[2] === oldImage)
    }

    @Test func interruptedReplacementIsRetriedUntilTheNewThumbnailIsLoaded() throws {
        let original = try photo(1)
        let changed = try photo(1, fields: ["thumbnail_path": "/photos/1/thumbnail?v=2"])
        let thumbnails = [1: Thumbnail()]

        for _ in 0..<2 {
            let pending = CommissionMediaRefresh.itemsRequiringThumbnails([changed], previousItems: [1: original], thumbnails: thumbnails)
            #expect(pending == [changed])
        }
        let completed = CommissionMediaRefresh.itemsRequiringThumbnails([changed], previousItems: [1: changed], thumbnails: thumbnails)
        #expect(completed.isEmpty)
    }

    @Test func missingImagesAreRetriedEvenWithUnchangedPhotoMetadata() throws {
        let item = try photo(1)
        let thumbnails: [Int: Thumbnail] = [:]
        let pending = CommissionMediaRefresh.itemsRequiringThumbnails([item], previousItems: [1: item], thumbnails: thumbnails)
        #expect(pending == [item])
    }

    @Test func removalAndReorderingKeepOnlyTheRemainingImages() throws {
        let first = try photo(1)
        let second = try photo(2)
        let image = Thumbnail()
        let thumbnails = [1: Thumbnail(), 2: image]
        let retained = CommissionMediaRefresh.retainedThumbnails(thumbnails, for: [second])
        #expect(retained.count == 1)
        #expect(retained[2] === image)

        let reordered = CommissionMediaRefresh.itemsRequiringThumbnails([second, first], previousItems: [1: first, 2: second], thumbnails: thumbnails)
        #expect(reordered.isEmpty)
        #expect(CommissionMediaRefresh.retainedThumbnails(thumbnails, for: [CommissionPhoto]()).isEmpty)
    }

    @Test func attachmentRefreshAlsoKeepsUnchangedImages() throws {
        let payload: [String: Any] = [
            "id": 1, "commission_id": 10, "source_entity_name": "Commission",
            "original_filename": "foto.jpg", "mime_type": "image/jpeg", "size_bytes": 5,
            "is_image": true, "content_path": "/attachments/1/content", "thumbnail_path": "/attachments/1/thumbnail"
        ]
        let item = try JSONDecoder().decode(CommissionAttachment.self, from: JSONSerialization.data(withJSONObject: payload))
        let image = Thumbnail()
        let thumbnails = [1: image]
        let pending = CommissionMediaRefresh.itemsRequiringThumbnails([item], previousItems: [1: item], thumbnails: thumbnails)
        #expect(pending.isEmpty)
        #expect(CommissionMediaRefresh.retainedThumbnails(thumbnails, for: [item])[1] === image)
    }
}

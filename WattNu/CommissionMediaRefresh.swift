import Foundation

enum CommissionMediaRefresh {
    static func itemsRequiringThumbnails<Item: Identifiable & Equatable, Thumbnail>(
        _ items: [Item],
        previousItems: [Item.ID: Item],
        thumbnails: [Item.ID: Thumbnail]
    ) -> [Item] {
        return items.filter { thumbnails[$0.id] == nil || previousItems[$0.id] != $0 }
    }

    static func retainedThumbnails<Item: Identifiable, Thumbnail>(
        _ thumbnails: [Item.ID: Thumbnail],
        for items: [Item]
    ) -> [Item.ID: Thumbnail] {
        let ids = Set(items.map(\.id))
        return thumbnails.filter { ids.contains($0.key) }
    }
}

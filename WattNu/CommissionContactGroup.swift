import Foundation

struct CommissionContactGroup: Identifiable {
    let id: String
    let title: String?
    let location: String?
    let contacts: [CommissionContactItem]

    static func groups(from contacts: [CommissionContactItem]) -> [CommissionContactGroup] {
        let grouped = Dictionary(grouping: contacts) { contact in
            if let useUnitId = contact.useUnitId { return "unit:\(useUnitId)" }
            if contact.useUnitNumber != nil || contact.useUnitLocation != nil {
                return "unit:\(contact.useUnitNumber ?? ""):\(contact.useUnitLocation ?? "")"
            }
            return "contacts"
        }

        return grouped.map { key, items in
            let first = items.first
            let number = first?.useUnitNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title: String?
            if let number, !number.isEmpty {
                title = "Wohnung \(number)"
            } else if first?.useUnitId != nil || first?.useUnitLocation != nil {
                title = "Wohnung"
            } else {
                title = nil
            }
            return CommissionContactGroup(id: key, title: title, location: first?.useUnitLocation, contacts: items.sorted { left, right in
                if (left.isFutureContract == true) != (right.isFutureContract == true) {
                    return left.isFutureContract != true
                }
                if left.contractStart != right.contractStart {
                    return (left.contractStart ?? "") < (right.contractStart ?? "")
                }
                let comparison = (left.name ?? "").localizedStandardCompare(right.name ?? "")
                return comparison == .orderedSame ? left.id < right.id : comparison == .orderedAscending
            })
        }.sorted { left, right in
            for (leftValue, rightValue) in [(left.title ?? "", right.title ?? ""), (left.location ?? "", right.location ?? "")] {
                let comparison = leftValue.localizedStandardCompare(rightValue)
                if comparison != .orderedSame { return comparison == .orderedAscending }
            }
            return left.id < right.id
        }
    }
}

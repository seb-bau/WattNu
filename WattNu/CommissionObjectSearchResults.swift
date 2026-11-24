import SwiftUI

enum CommissionObjectLevel: String {
    case economicUnit = "economic_unit"
    case building
    case useUnit = "use_unit"
    case agreement = "license_agreement"

    var title: String {
        switch self {
        case .economicUnit: "Wirtschaftseinheit"
        case .building: "Gebäude"
        case .useUnit: "Wohnung / Nutzungseinheit"
        case .agreement: "Mietvertrag"
        }
    }

    var icon: String {
        switch self {
        case .economicUnit: "building.2"
        case .building: "house"
        case .useUnit: "door.left.hand.open"
        case .agreement: "doc.text"
        }
    }

    var indentation: CGFloat {
        switch self {
        case .economicUnit: 0
        case .building: 8
        case .useUnit, .agreement: 16
        }
    }
}

struct CommissionObjectSearchRow: Identifiable {
    let id: String
    let level: CommissionObjectLevel
    let title: String
    let details: String
    let selection: CommissionObjectChoice?

    init(item: CommissionObjectChoice, level: CommissionObjectLevel) {
        id = item.id
        self.level = level
        selection = item
        title = item.displayTitle(at: level)
        details = item.displayDetails(at: level, includeNumber: true)
    }

    init(parentOf item: CommissionObjectChoice, level: CommissionObjectLevel, erpId: Int) {
        id = "parent-\(level.rawValue):\(erpId)"
        self.level = level
        title = item.displayTitle(at: level)
        details = level.title
        selection = item.parentChoice(at: level)
    }

    static func grouped(_ items: [CommissionObjectChoice]) -> [CommissionObjectSearchRow] {
        let known = items.filter { CommissionObjectLevel(rawValue: $0.objectType) != nil }
        let byEconomy = Dictionary(grouping: known, by: { $0.economicUnit.erpId })
        var economies = Set<Int>()
        var rows: [CommissionObjectSearchRow] = []

        for item in known where economies.insert(item.economicUnit.erpId).inserted {
            let group = byEconomy[item.economicUnit.erpId] ?? []
            if let direct = group.first(where: { $0.objectType == CommissionObjectLevel.economicUnit.rawValue }) {
                rows.append(CommissionObjectSearchRow(item: direct, level: .economicUnit))
            } else {
                rows.append(CommissionObjectSearchRow(parentOf: item, level: .economicUnit, erpId: item.economicUnit.erpId))
            }

            let byBuilding = Dictionary(grouping: group.filter { $0.building != nil }, by: { $0.building?.erpId })
            var buildings = Set<Int>()
            for child in group {
                guard let building = child.building, buildings.insert(building.erpId).inserted else { continue }
                let children = byBuilding[building.erpId] ?? []
                if let direct = children.first(where: { $0.objectType == CommissionObjectLevel.building.rawValue }) {
                    rows.append(CommissionObjectSearchRow(item: direct, level: .building))
                } else {
                    rows.append(CommissionObjectSearchRow(parentOf: child, level: .building, erpId: building.erpId))
                }

                var leaves = Set<String>()
                for leaf in children where leaves.insert(leaf.id).inserted {
                    guard let level = CommissionObjectLevel(rawValue: leaf.objectType),
                          level == .agreement || level == .useUnit else { continue }
                    rows.append(CommissionObjectSearchRow(item: leaf, level: level))
                }
            }
        }

        return rows
    }
}

extension CommissionObjectChoice {
    func displayTitle(at level: CommissionObjectLevel) -> String {
        switch level {
        case .economicUnit:
            economicUnit.name ?? economicUnit.address ?? level.title
        case .building:
            building?.address ?? level.title
        case .useUnit:
            isVacancy ? "Leerstand" : "Wohnung"
        case .agreement:
            tenantName ?? (isVacancy ? "Leerstand" : level.title)
        }
    }

    func displayDetails(at level: CommissionObjectLevel, includeNumber: Bool) -> String {
        var values = [level.title]
        if includeNumber {
            let number: String? = switch level {
            case .economicUnit: economicUnit.idNum
            case .building: building?.idNum
            case .useUnit: useUnit?.idNum
            case .agreement: licenseAgreement?.idNum
            }
            if let number, !number.isEmpty { values.append(number) }
        }
        if level == .agreement || level == .useUnit,
           let location = useUnit?.description, !location.isEmpty {
            values.append(location)
        }
        return values.joined(separator: " · ")
    }

    func parentChoice(at level: CommissionObjectLevel) -> CommissionObjectChoice? {
        let objectId: Int? = switch level {
        case .economicUnit: economicUnit.objectId
        case .building: building?.objectId
        case .useUnit, .agreement: nil
        }
        guard let objectId else { return nil }

        return CommissionObjectChoice(
            objectType: level.rawValue, objectId: objectId, label: displayTitle(at: level),
            tenantName: nil, isVacancy: false, companyCode: companyCode,
            economicUnit: economicUnit, building: level == .building ? building : nil,
            useUnit: nil, licenseAgreement: nil
        )
    }
}

struct CommissionObjectSearchLabel: View {
    let row: CommissionObjectSearchRow

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: row.level.icon)
                .frame(width: 18)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(row.level == .economicUnit ? .headline : .body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(row.details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, row.level.indentation)
        .padding(.vertical, row.level == .economicUnit ? 5 : 2)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

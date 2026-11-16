//
//  CommissionFilters.swift
//  WattNu
//
//  Created by Sebastian Bauhaus on 09.06.26.
//

import Foundation

enum CommissionSortMode: String, CaseIterable, Identifiable {
    case oldestFirst
    case newestFirst
    case defaultOrder
    case distance
    case title

    var id: String { rawValue }

    var label: String {
        switch self {
        case .oldestFirst: return "Erstellt: älteste zuerst"
        case .newestFirst: return "Erstellt: neueste zuerst"
        case .defaultOrder: return "Priorität und Termine"
        case .distance: return "Entfernung"
        case .title: return "Titel"
        }
    }

    func sortedByCreationDate(_ commissions: [Commission]) -> [Commission] {
        let dated = commissions.map { ($0, Formatters.commissionCreationDate($0.recordingDate)) }
        return dated.sorted { left, right in
            switch (left.1, right.1) {
            case let (leftDate?, rightDate?) where leftDate != rightDate:
                return self == .newestFirst ? leftDate > rightDate : leftDate < rightDate
            case (_?, nil): return true
            case (nil, _?): return false
            default: return self == .newestFirst ? left.0.id > right.0.id : left.0.id < right.0.id
            }
        }.map { $0.0 }
    }

    func sorted(_ commissions: [Commission], at currentDate: Date = Date(), distance: (Commission) -> Double? = { _ in nil }) -> [Commission] {
        let ordered: [Commission]
        switch self {
        case .oldestFirst, .newestFirst:
            ordered = sortedByCreationDate(commissions)
        case .title:
            ordered = commissions.sorted {
                $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
            }
        case .distance:
            let nearby = commissions.enumerated().map {
                (index: $0.offset, commission: $0.element, meters: distance($0.element) ?? Double.infinity)
            }
            ordered = nearby.sorted {
                $0.meters == $1.meters ? $0.index < $1.index : $0.meters < $1.meters
            }.map { $0.commission }
        case .defaultOrder:
            ordered = commissions
        }

        var groups = [[Commission]](repeating: [], count: 3)
        for commission in ordered {
            let priority: Int
            if commission.isHighPriorityValue {
                priority = 0
            } else if Formatters.isAppointmentToday(commission.acceptedAppointmentFrom, at: currentDate) {
                priority = 1
            } else {
                priority = 2
            }
            groups[priority].append(commission)
        }
        return groups.flatMap { $0 }
    }
}

enum CommissionOwnerFilter: Hashable {
    case mine
    case user(Int)
    case all

    var scope: CommissionScopeFilter {
        switch self {
        case .mine:
            return .mine
        case .user, .all:
            return .all
        }
    }

    var userId: Int? {
        switch self {
        case .user(let userId):
            return userId
        case .mine, .all:
            return nil
        }
    }
}

enum CommissionScopeFilter: String, CaseIterable, Identifiable {
    case mine
    case all

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .mine:
            return "Meine"
        case .all:
            return "Alle"
        }
    }
}

enum CommissionStatusFilter: String, CaseIterable, Identifiable {
    case active
    case unreadInfos = "unread_infos"
    case all
    case recorded
    case waitingForAcceptance = "waiting_for_acceptance"
    case open
    case inProgress = "in_progress"
    case completionReview = "completion_review"
    case tenantChargeReview = "tenant_charge_review"
    case done

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .active:
            return "Aktive"
        case .unreadInfos:
            return "Ungelesene Infos"
        case .all:
            return "Alle Status"
        case .recorded:
            return "Ausstehend"
        case .waitingForAcceptance:
            return "Warte auf Annahme"
        case .open:
            return "Offen"
        case .inProgress:
            return "In Bearbeitung"
        case .completionReview:
            return "Abschlussprüfung"
        case .tenantChargeReview:
            return "Mieterbelastung"
        case .done:
            return "Abgeschlossen"
        }
    }

    var apiFilter: CommissionStatusFilter {
        self == .unreadInfos ? .all : self
    }

    static let activeLocalStatuses: Set<String> = [
        "waiting_for_acceptance",
        "open",
        "in_progress"
    ]
}

//
//  CommissionFilters.swift
//  WattNu
//
//  Created by Sebastian Bauhaus on 09.06.26.
//

import Foundation

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
    
    static let activeLocalStatuses: Set<String> = [
        "waiting_for_acceptance",
        "open",
        "in_progress"
    ]
}

import Combine
import CryptoKit
import Foundation

struct SavedUserPreferences: Codable, Equatable {
    var commissionOwner = "mine"
    var commissionStatus = "active"
    var commissionSort = "oldestFirst"
    var commissionSearch = ""
    var inspectionOwner = "mine"
    var inspectionStatus = "active"
    var inspectionSearch = ""
    var inspectionVisit = "all"
    var inspectionTemplateId: Int?
    var lastCraftActivityId: Int?
    var lastFreeTimeTaskId: Int?
}

@MainActor
final class UserPreferencesStore: ObservableObject {
    static let shared = UserPreferencesStore()

    @Published var values = SavedUserPreferences() {
        didSet {
            guard !isRestoring, let accountKey,
                  let data = try? JSONEncoder().encode(values) else { return }
            defaults.set(data, forKey: accountKey)
        }
    }

    private let defaults: UserDefaults
    private var accountKey: String?
    private var isRestoring = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func activate(baseURL: URL, userId: Int?) {
        let key = userId.map { id in
            "userPreferences." + SHA256.hash(data: Data("\(baseURL.absoluteString)|\(id)".utf8))
                .map { String(format: "%02x", $0) }.joined()
        }
        guard key != accountKey else { return }
        accountKey = key
        isRestoring = true
        defer { isRestoring = false }
        values = key.flatMap { defaults.data(forKey: $0) }
            .flatMap { try? JSONDecoder().decode(SavedUserPreferences.self, from: $0) }
            ?? SavedUserPreferences()
    }

    var commissionOwnerFilter: CommissionOwnerFilter {
        get { CommissionOwnerFilter(savedValue: values.commissionOwner) }
        set { values.commissionOwner = newValue.savedValue }
    }

    var commissionStatusFilter: CommissionStatusFilter {
        get { CommissionStatusFilter(rawValue: values.commissionStatus) ?? .active }
        set { values.commissionStatus = newValue.rawValue }
    }

    var commissionSortMode: CommissionSortMode {
        get { CommissionSortMode(rawValue: values.commissionSort) ?? .oldestFirst }
        set { values.commissionSort = newValue.rawValue }
    }

    var inspectionOwnerFilter: CommissionOwnerFilter {
        get { CommissionOwnerFilter(savedValue: values.inspectionOwner) }
        set { values.inspectionOwner = newValue.savedValue }
    }

    var inspectionStatusFilter: SafetyInspectionListFilter {
        get { SafetyInspectionListFilter(rawValue: values.inspectionStatus) ?? .active }
        set { values.inspectionStatus = newValue.rawValue }
    }

    func preferredFreeTimeTask(in tasks: [TimeTask]) -> Int? {
        if let task = tasks.first(where: { $0.id == values.lastFreeTimeTaskId }),
           values.lastCraftActivityId == nil || task.craftActivity == nil || task.craftActivity?.id == values.lastCraftActivityId {
            return task.id
        }
        if let craftId = values.lastCraftActivityId {
            let matching = tasks.filter { $0.craftActivity?.id == craftId }
            if matching.count == 1 { return matching[0].id }
        }
        return tasks.count == 1 ? tasks[0].id : nil
    }
}

extension CommissionOwnerFilter {
    init(savedValue: String) {
        if savedValue == "all" { self = .all }
        else if savedValue.hasPrefix("user:"), let id = Int(savedValue.dropFirst(5)), id > 0 { self = .user(id) }
        else { self = .mine }
    }

    var savedValue: String {
        switch self {
        case .mine: return "mine"
        case .all: return "all"
        case .user(let id): return "user:\(id)"
        }
    }
}

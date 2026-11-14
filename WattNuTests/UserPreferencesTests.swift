import Foundation
import Testing
@testable import WattNu

@MainActor
struct UserPreferencesTests {
    private func task(_ id: Int, craftId: Int) -> TimeTask {
        TimeTask(id: id, code: "T\(id)", title: "Position", suggestedMinutes: nil, serviceCatalogId: nil, erpIdNum: nil,
                 craftActivity: CraftActivity(id: craftId, erpId: nil, code: "G\(craftId)", name: "Gewerk"), expectedMaterials: nil)
    }

    @Test func filtersSearchesSortAndCraftSelectionsSurviveReopening() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let url = URL(string: "https://one.example.invalid")!
        let store = UserPreferencesStore(defaults: defaults)
        store.activate(baseURL: url, userId: 1)
        #expect(store.commissionSortMode == .oldestFirst)
        store.commissionOwnerFilter = .user(42)
        store.commissionStatusFilter = .done
        store.commissionSortMode = .newestFirst
        store.values.commissionSearch = "Heizung"
        store.inspectionOwnerFilter = .all
        store.inspectionStatusFilter = .completedWithDefects
        store.values.inspectionSearch = "Haus 2"
        store.values.inspectionVisit = InspectionVisitFilter.allCases.last!.rawValue
        store.values.inspectionTemplateId = 20
        store.values.lastCraftActivityId = 7
        store.values.lastFreeTimeTaskId = 70

        let reopened = UserPreferencesStore(defaults: defaults)
        reopened.activate(baseURL: url, userId: 1)

        #expect(reopened.values == store.values)
        #expect(reopened.commissionOwnerFilter == .user(42))
        #expect(reopened.commissionSortMode == .newestFirst)
        #expect(reopened.inspectionStatusFilter == .completedWithDefects)
    }

    @Test func accountsServersAndLogoutKeepPreferencesSeparate() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let firstURL = URL(string: "https://one.example.invalid")!
        let secondURL = URL(string: "https://two.example.invalid")!
        let store = UserPreferencesStore(defaults: defaults)
        store.activate(baseURL: firstURL, userId: 1)
        store.commissionSortMode = .newestFirst
        store.values.lastCraftActivityId = 7
        store.activate(baseURL: firstURL, userId: 2)
        #expect(store.commissionSortMode == .oldestFirst)
        #expect(store.values.lastCraftActivityId == nil)
        store.values.lastCraftActivityId = 8
        store.activate(baseURL: secondURL, userId: 1)
        #expect(store.values.lastCraftActivityId == nil)
        store.activate(baseURL: firstURL, userId: 1)
        #expect(store.values.lastCraftActivityId == 7)
        store.activate(baseURL: firstURL, userId: nil)
        #expect(store.values == SavedUserPreferences())
        store.activate(baseURL: firstURL, userId: 2)
        #expect(store.values.lastCraftActivityId == 8)
    }

    @Test func inspectionNavigationChangesArePersisted() throws {
        let name = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let url = URL(string: "https://one.example.invalid")!
        let store = UserPreferencesStore(defaults: defaults)
        store.activate(baseURL: url, userId: 1)
        let navigation = AppNavigationStore(preferences: store)
        navigation.safetyInspectionOwnerFilter = .user(3)
        navigation.safetyInspectionStatusFilter = .missed
        navigation.safetyInspectionSearchText = "Innenhof"
        let reopened = UserPreferencesStore(defaults: defaults)
        reopened.activate(baseURL: url, userId: 1)
        #expect(reopened.inspectionOwnerFilter == .user(3))
        #expect(reopened.inspectionStatusFilter == .missed)
        #expect(reopened.values.inspectionSearch == "Innenhof")
    }

    @Test func unknownFilterValuesUseValidDefaults() {
        let store = UserPreferencesStore()
        store.values.commissionOwner = "user:invalid"
        store.values.commissionStatus = "unknown"
        store.values.commissionSort = "unknown"
        store.values.inspectionOwner = "user:-1"
        store.values.inspectionStatus = "unknown"
        #expect(store.commissionOwnerFilter == .mine)
        #expect(store.commissionStatusFilter == .active)
        #expect(store.commissionSortMode == .oldestFirst)
        #expect(store.inspectionOwnerFilter == .mine)
        #expect(store.inspectionStatusFilter == .active)
    }

    @Test func freeTimeRestoresTheLastTaskAndRespectsAChangedCraft() {
        let store = UserPreferencesStore()
        let tasks = [task(70, craftId: 7), task(71, craftId: 7), task(80, craftId: 8)]
        store.values.lastFreeTimeTaskId = 71
        store.values.lastCraftActivityId = 7
        #expect(store.preferredFreeTimeTask(in: tasks) == 71)
        store.values.lastCraftActivityId = 8
        #expect(store.preferredFreeTimeTask(in: tasks) == 80)
        store.values.lastCraftActivityId = 7
        store.values.lastFreeTimeTaskId = 999
        #expect(store.preferredFreeTimeTask(in: tasks) == nil)
        #expect(store.preferredFreeTimeTask(in: []) == nil)
    }
}

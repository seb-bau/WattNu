import Foundation
import Testing
@testable import WattNu

@MainActor
struct CommissionSortingTests {
    private func commission(_ id: Int, date: String?, urgent: Bool = false) throws -> Commission {
        var item: [String: Any] = ["id": id, "local_status": "open", "positions": [], "is_high_priority": urgent]
        item["recording_date"] = date
        return try JSONDecoder().decode(Commission.self, from: JSONSerialization.data(withJSONObject: item))
    }

    @Test func creationDateSortIsChronologicalInBothDirections() throws {
        let newest = try commission(1, date: "2026-11-14T12:00:00Z", urgent: true)
        let oldest = try commission(100, date: "2020-01-01")
        let middle = try commission(2, date: "2025-01-01T12:00:00.123Z")
        let values = [newest, oldest, middle]
        #expect(CommissionSortMode.oldestFirst.sortedByCreationDate(values).map(\.id) == [100, 2, 1])
        #expect(CommissionSortMode.newestFirst.sortedByCreationDate(values).map(\.id) == [1, 2, 100])
    }

    @Test func missingAndInvalidDatesFollowDatedOrdersInBothDirections() throws {
        let known = try commission(3, date: "2026-01-01")
        let invalid = try commission(2, date: "invalid")
        let missing = try commission(1, date: nil)
        #expect(CommissionSortMode.oldestFirst.sortedByCreationDate([invalid, known, missing]).map(\.id) == [3, 1, 2])
        #expect(CommissionSortMode.newestFirst.sortedByCreationDate([invalid, known, missing]).map(\.id) == [3, 2, 1])
    }

    @Test func timeZonesAreComparedAsDatesAndTiesAreStable() throws {
        let first = try commission(1, date: "2026-01-01T10:00:00+01:00")
        let second = try commission(2, date: "2026-01-01T09:30:00Z")
        let tie = try commission(3, date: "2026-01-01T09:00:00Z")
        #expect(CommissionSortMode.oldestFirst.sortedByCreationDate([second, tie, first]).map(\.id) == [1, 3, 2])
    }
}

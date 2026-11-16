import Foundation
import Testing
@testable import WattNu

@MainActor
struct CommissionSortingTests {
    private func commission(_ id: Int, date: String?, urgent: Bool = false, appointment: String? = nil, title: String? = nil) throws -> Commission {
        var item: [String: Any] = ["id": id, "local_status": "open", "positions": [], "is_high_priority": urgent]
        item["recording_date"] = date
        item["accepted_appointment_from"] = appointment
        item["title"] = title
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

    @Test(arguments: ["oldestFirst", "newestFirst", "defaultOrder", "distance", "title"])
    func highPriorityAndTodayAppointmentsAlwaysLead(rawMode: String) throws {
        let mode = try #require(CommissionSortMode(rawValue: rawMode))
        let now = ISO8601DateFormatter().date(from: "2026-11-14T12:00:00Z")!
        let regular = try commission(1, date: "2010-01-01", title: "A")
        let scheduled = try commission(2, date: "2015-01-01", appointment: now.addingTimeInterval(86400).ISO8601Format(), title: "B")
        let today = try commission(3, date: "2020-01-01", appointment: now.ISO8601Format(), title: "C")
        let urgent = try commission(4, date: "2026-01-01", urgent: true, title: "Z")

        let sorted = mode.sorted([regular, scheduled, today, urgent], at: now, distance: { Double($0.id) })

        let expected = mode == .newestFirst ? [4, 3, 2, 1] : [4, 3, 1, 2]
        #expect(sorted.map(\.id) == expected)
    }

    @Test(arguments: ["oldestFirst", "newestFirst"])
    func selectedDateDirectionIsPreservedWithinEveryPriorityGroup(rawMode: String) throws {
        let mode = try #require(CommissionSortMode(rawValue: rawMode))
        let now = ISO8601DateFormatter().date(from: "2026-11-14T12:00:00Z")!
        let tomorrow = now.addingTimeInterval(86400).ISO8601Format()
        let items = [
            try commission(42, date: "2026-01-01"),
            try commission(22, date: "2022-01-01", appointment: now.ISO8601Format()),
            try commission(11, date: "2023-01-01", urgent: true),
            try commission(32, date: "2021-01-01", appointment: tomorrow),
            try commission(41, date: "2018-01-01"),
            try commission(12, date: "2025-01-01", urgent: true),
            try commission(31, date: "2019-01-01", appointment: tomorrow),
            try commission(21, date: "2020-01-01", appointment: now.ISO8601Format()),
        ]
        let expected = mode == .oldestFirst ? [11, 12, 21, 22, 41, 31, 32, 42] : [12, 11, 22, 21, 42, 32, 31, 41]

        #expect(mode.sorted(items, at: now).map(\.id) == expected)
    }

    @Test func highPriorityTakesPrecedenceOverTodayEvenWithAnUnknownCreationDate() throws {
        let now = ISO8601DateFormatter().date(from: "2026-11-14T12:00:00Z")!
        let urgent = try commission(1, date: nil, urgent: true, appointment: now.ISO8601Format())
        let today = try commission(2, date: "2010-01-01", appointment: now.ISO8601Format())
        let regular = try commission(3, date: "2000-01-01")
        #expect(CommissionSortMode.oldestFirst.sorted([regular, today, urgent], at: now).map(\.id) == [1, 2, 3])
    }

    @Test(arguments: ["oldestFirst", "newestFirst", "defaultOrder", "distance", "title"])
    func appointmentsOutsideTodayDoNotOverrideTheSelectedSort(rawMode: String) throws {
        let mode = try #require(CommissionSortMode(rawValue: rawMode))
        let now = ISO8601DateFormatter().date(from: "2026-11-16T12:00:00Z")!
        let items = [
            try commission(5, date: "2026-01-01", appointment: "", title: "E"),
            try commission(4, date: "2024-01-01", appointment: "invalid", title: "D"),
            try commission(3, date: "2022-01-01", appointment: now.addingTimeInterval(-86400).ISO8601Format(), title: "C"),
            try commission(2, date: "2020-01-01", appointment: now.addingTimeInterval(86400).ISO8601Format(), title: "B"),
            try commission(1, date: "2010-01-01", title: "A"),
        ]
        let expected = mode == .newestFirst || mode == .defaultOrder ? [5, 4, 3, 2, 1] : [1, 2, 3, 4, 5]
        #expect(mode.sorted(items, at: now, distance: { Double($0.id) }).map(\.id) == expected)
    }
}

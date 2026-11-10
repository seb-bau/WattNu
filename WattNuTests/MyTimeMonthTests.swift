import Foundation
import Testing
@testable import WattNu

@MainActor
struct MyTimeMonthTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day)
        )!
    }

    @Test func includesEveryDayOfLeapFebruary() {
        let month = MyTimeMonth(
            containing: date(2024, 2, 29),
            calendar: calendar
        )

        #expect(month.startDate == date(2024, 2, 1))
        #expect(month.dates.count == 29)
        #expect(month.dates.first == date(2024, 2, 1))
        #expect(month.dates.last == date(2024, 2, 29))
        #expect(month.leadingEmptyDays == 3)
        #expect(month.title == "Februar 2024")
    }

    @Test func handlesNonLeapFebruary() {
        let month = MyTimeMonth(
            containing: date(2025, 2, 14),
            calendar: calendar
        )

        #expect(month.dates.count == 28)
        #expect(month.dates.last == date(2025, 2, 28))
    }

    @Test func alignsMondayAndSundayWithGermanWeekdays() {
        let mondayMonth = MyTimeMonth(
            containing: date(2026, 6, 10),
            calendar: calendar
        )
        let sundayMonth = MyTimeMonth(
            containing: date(2026, 11, 10),
            calendar: calendar
        )

        #expect(mondayMonth.leadingEmptyDays == 0)
        #expect(sundayMonth.leadingEmptyDays == 6)
        #expect(mondayMonth.dates.count == 30)
        #expect(sundayMonth.dates.count == 30)
    }

    @Test func movesAcrossYearsAndShorterMonths() {
        let january = MyTimeMonth(
            containing: date(2026, 1, 31),
            calendar: calendar
        )
        let february = january.moving(by: 1)
        let december = january.moving(by: -1)

        #expect(february.startDate == date(2026, 2, 1))
        #expect(february.dates.count == 28)
        #expect(february.moving(by: -1).startDate == january.startDate)
        #expect(december.startDate == date(2025, 12, 1))
        #expect(december.moving(by: 1).startDate == january.startDate)
    }

    @Test func preservesLocalDaysAcrossDaylightSavingChanges() throws {
        let march = MyTimeMonth(
            containing: date(2026, 3, 1),
            calendar: calendar
        )
        let october = MyTimeMonth(
            containing: date(2026, 10, 1),
            calendar: calendar
        )

        for month in [march, october] {
            #expect(month.dates.count == 31)
            #expect(Set(month.dates).count == 31)
            #expect(month.dates.allSatisfy {
                calendar.component(.hour, from: $0) == 0
            })
            #expect(month.dates.map {
                calendar.component(.day, from: $0)
            } == Array(1...31))
        }

        let springDay = try #require(march.dates.firstIndex(of: date(2026, 3, 29)))
        let autumnDay = try #require(october.dates.firstIndex(of: date(2026, 10, 25)))
        #expect(
            march.dates[springDay + 1].timeIntervalSince(march.dates[springDay])
                == 23 * 60 * 60
        )
        #expect(
            october.dates[autumnDay + 1].timeIntervalSince(october.dates[autumnDay])
                == 25 * 60 * 60
        )
    }
}

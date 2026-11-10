import Foundation

struct MyTimeMonth {
    let calendar: Calendar
    let startDate: Date
    let dates: [Date]
    let leadingEmptyDays: Int

    init(
        containing date: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        self.calendar = calendar

        let startDate = calendar.dateInterval(
            of: .month,
            for: date
        )?.start ?? calendar.startOfDay(for: date)
        self.startDate = startDate

        let dayRange = calendar.range(
            of: .day,
            in: .month,
            for: startDate
        ) ?? 1..<1

        dates = dayRange.compactMap { day in
            calendar.date(
                byAdding: .day,
                value: day - 1,
                to: startDate
            )
        }

        leadingEmptyDays = (
            calendar.component(.weekday, from: startDate) + 5
        ) % 7
    }

    var title: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: startDate)
    }

    func moving(by value: Int) -> MyTimeMonth {
        let date = calendar.date(
            byAdding: .month,
            value: value,
            to: startDate
        ) ?? startDate

        return MyTimeMonth(containing: date, calendar: calendar)
    }
}

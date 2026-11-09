//
//  Formatters.swift
//  WattNu
//
//  Created by Sebastian Bauhaus on 09.06.26.
//

import Foundation

enum Formatters {
    private static let appointmentDateCache: NSCache<NSString, NSDate> = {
        let cache = NSCache<NSString, NSDate>()
        cache.countLimit = 4096
        return cache
    }()

    private static let appointmentISOFormatters: [ISO8601DateFormatter] = {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]

        let plainFormatter = ISO8601DateFormatter()
        plainFormatter.formatOptions = [.withInternetDateTime]
        return [fractionalFormatter, plainFormatter]
    }()

    private static let appointmentLocalFormatters: [DateFormatter] = [
        "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
        "yyyy-MM-dd'T'HH:mm:ss.SSS",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd"
    ].map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = format
        return formatter
    }
    
    static func dateTimeText(_ value: String?) -> String {
        guard let value, !value.isEmpty else {
            return "-"
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: value) {
            return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
        }

        formatter.formatOptions = [.withInternetDateTime]

        if let date = formatter.date(from: value) {
            return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
        }

        return value
    }

    static func quantityText(_ value: Double, unit: String) -> String {
        "\(String(format: "%.2f", value)) \(unit)"
    }
    
    static func appointmentRangeText(
        fromValue: String?,
        toValue: String?
    ) -> String? {
        guard let fromDate = appointmentDate(from: fromValue) else {
            return nil
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "de_DE")
        dateFormatter.timeZone = .current
        dateFormatter.dateFormat = "d. MMMM yyyy"
        
        if fromValue?.count == 10 {
            return dateFormatter.string(from: fromDate)
        }

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "de_DE")
        timeFormatter.timeZone = .current
        timeFormatter.dateFormat = "HH:mm"

        let fromDateText = dateFormatter.string(from: fromDate)
        let fromTimeText = timeFormatter.string(from: fromDate)

        guard let toDate = appointmentDate(from: toValue) else {
            return "\(fromDateText), \(fromTimeText) Uhr"
        }

        let toTimeText = timeFormatter.string(from: toDate)

        if Calendar.autoupdatingCurrent.isDate(
            fromDate,
            inSameDayAs: toDate
        ) {
            return "\(fromDateText), \(fromTimeText)–\(toTimeText) Uhr"
        }

        let toDateText = dateFormatter.string(from: toDate)

        return "\(fromDateText), \(fromTimeText) Uhr bis \(toDateText), \(toTimeText) Uhr"
    }
    
    static func isAppointmentToday(
        _ value: String?,
        at currentDate: Date
    ) -> Bool {
        guard let appointmentDate = appointmentDate(from: value) else {
            return false
        }

        return Calendar.autoupdatingCurrent.isDate(
            appointmentDate,
            inSameDayAs: currentDate
        )
    }

    private static func appointmentDate(from value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }

        let key = "\(TimeZone.current.identifier)|\(value)" as NSString
        if let cachedDate = appointmentDateCache.object(forKey: key) {
            return cachedDate as Date
        }

        let parsedDate = appointmentISOFormatters.lazy
            .compactMap { $0.date(from: value) }
            .first
            ?? appointmentLocalFormatters.lazy
                .compactMap { $0.date(from: value) }
                .first

        if let parsedDate {
            appointmentDateCache.setObject(parsedDate as NSDate, forKey: key)
        }

        return parsedDate
    }

    static func percentText(_ value: Double) -> String {
        "\(String(format: "%.1f", value)) %"
    }
    
    static func apiDateText(
        _ value: Date
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(
            identifier: .gregorian
        )
        formatter.locale = Locale(
            identifier: "en_US_POSIX"
        )
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"

        return formatter.string(
            from: value
        )
    }

    static func dateFromApiDate(
        _ value: String?
    ) -> Date? {
        guard let value, !value.isEmpty else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(
            identifier: .gregorian
        )
        formatter.locale = Locale(
            identifier: "en_US_POSIX"
        )
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"

        return formatter.date(
            from: value
        )
    }

    static func dateText(
        _ value: String?
    ) -> String {
        guard let date = dateFromApiDate(
            value
        ) else {
            return value ?? "-"
        }

        return DateFormatter.localizedString(
            from: date,
            dateStyle: .medium,
            timeStyle: .none
        )
    }
}

enum WorkTimeText {
    static func minutes(fromHours text: String) -> Int? {
        let normalizedText = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")

        guard normalizedText.range(
            of: #"^(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$"#,
            options: .regularExpression
        ) != nil,
              let hours = Double(normalizedText),
              hours.isFinite else {
            return nil
        }

        return Int(exactly: (hours * 60).rounded())
    }

    static func hoursInput(_ minutes: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2

        return formatter.string(
            from: NSNumber(value: Double(minutes) / 60)
        ) ?? "0"
    }

    static func duration(_ minutes: Int) -> String {
        "\(hoursInput(minutes)) Std."
    }

    static func signedDuration(_ minutes: Int) -> String {
        let prefix = minutes >= 0 ? "+" : "−"
        return prefix + duration(abs(minutes))
    }
}

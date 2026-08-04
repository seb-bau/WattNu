import Foundation
import UserNotifications

enum AppointmentReminderService {
    static func schedule(
        for commission: Commission
    ) async {
        guard let value = commission.acceptedAppointmentFrom,
              let appointmentDate = parseDate(value) else {
            return
        }

        let center = UNUserNotificationCenter.current()

        do {
            let settings = await center.notificationSettings()

            if settings.authorizationStatus == .notDetermined {
                _ = try await center.requestAuthorization(
                    options: [
                        .alert,
                        .badge,
                        .sound
                    ]
                )
            }

            let currentSettings = await center.notificationSettings()

            guard currentSettings.authorizationStatus == .authorized
                    || currentSettings.authorizationStatus == .provisional else {
                return
            }

            let identifiers = [
                identifier(
                    commissionId: commission.id,
                    suffix: "day"
                ),
                identifier(
                    commissionId: commission.id,
                    suffix: "hour"
                )
            ]

            center.removePendingNotificationRequests(
                withIdentifiers: identifiers
            )

            await addReminder(
                center: center,
                commission: commission,
                appointmentDate: appointmentDate,
                offset: -24 * 60 * 60,
                identifier: identifiers[0],
                title: "Termin morgen"
            )

            await addReminder(
                center: center,
                commission: commission,
                appointmentDate: appointmentDate,
                offset: -60 * 60,
                identifier: identifiers[1],
                title: "Termin in einer Stunde"
            )

        } catch {
            return
        }
    }
    
    static func cancel(
        for commission: Commission
    ) {
        let identifiers = [
            identifier(
                commissionId: commission.id,
                suffix: "day"
            ),
            identifier(
                commissionId: commission.id,
                suffix: "hour"
            )
        ]

        let center = UNUserNotificationCenter.current()

        center.removePendingNotificationRequests(
            withIdentifiers: identifiers
        )

        center.removeDeliveredNotifications(
            withIdentifiers: identifiers
        )
    }

    private static func addReminder(
        center: UNUserNotificationCenter,
        commission: Commission,
        appointmentDate: Date,
        offset: TimeInterval,
        identifier: String,
        title: String
    ) async {
        let reminderDate = appointmentDate.addingTimeInterval(
            offset
        )

        guard reminderDate > Date() else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = [
            commission.displayTitle,
            commission.apartmentAddress
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
        content.sound = .default
        content.userInfo = [
            "commission_id": commission.id
        ]

        let components = Calendar.current.dateComponents(
            [
                .year,
                .month,
                .day,
                .hour,
                .minute
            ],
            from: reminderDate
        )

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        try? await center.add(request)
    }

    private static func identifier(
        commissionId: Int,
        suffix: String
    ) -> String {
        "commission-\(commissionId)-appointment-\(suffix)"
    }

    private static func parseDate(
        _ value: String
    ) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]

        if let date = formatter.date(
            from: value
        ) {
            return date
        }

        formatter.formatOptions = [
            .withInternetDateTime
        ]

        return formatter.date(
            from: value
        )
    }
}

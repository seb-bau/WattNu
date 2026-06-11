//
//  Formatters.swift
//  WattNu
//
//  Created by Sebastian Bauhaus on 09.06.26.
//

import Foundation

enum Formatters {
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

    static func percentText(_ value: Double) -> String {
        "\(String(format: "%.1f", value)) %"
    }
}

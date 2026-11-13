import SwiftUI

struct CommissionRowView: View {
    let commission: Commission
    @EnvironmentObject private var locationStore: LocationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    Label {
                        Text(commission.objectDisplayTitle)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                    } icon: {
                        Image(systemName: commission.isEconomicUnitOrder ? "building.2.fill" : "house.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )

                    VStack(
                        alignment: .trailing,
                        spacing: 6
                    ) {
                        statusPill

                        if commission.isHighPriorityValue {
                            priorityPill
                        }
                    }
                    .fixedSize(
                        horizontal: true,
                        vertical: false
                    )
                }

                if commission.isEconomicUnitOrder {
                    if let name = commission.economicUnitDisplayName {
                        Text(name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                    }
                    if let address = commission.apartmentAddress, !address.isEmpty {
                        Text("Orientierungsadresse: \(address)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                if let tenantName = commission.tenantName,
                   !tenantName.isEmpty {
                    Label(
                        tenantName,
                        systemImage: "person.text.rectangle"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                }

                if let location = commission.apartmentLocation,
                   !location.isEmpty {
                    Label(
                        location,
                        systemImage: "rectangle.split.2x1"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                }
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                if let appointmentText = acceptedAppointmentText {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        let isToday = Formatters.isAppointmentToday(
                            commission.acceptedAppointmentFrom,
                            at: context.date
                        )

                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: "calendar.badge.checkmark")
                                .font(.title3)
                                .foregroundStyle(
                                    isToday ? Color.green : Color.secondary
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Vereinbarter Termin")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(
                                        isToday ? Color.green : Color.secondary
                                    )

                                Text(appointmentText)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    isToday
                                        ? Color.green.opacity(0.12)
                                        : Color.secondary.opacity(0.08)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(
                                    isToday
                                        ? Color.green.opacity(0.3)
                                        : Color.secondary.opacity(0.15),
                                    lineWidth: 1
                                )
                        )
                    }
                }
                Text(commission.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Label(
                    commission.displayNumber,
                    systemImage: "number"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if let distance =
                    locationStore.distanceText(
                        to: commission
                    ) {
                    Label(
                        distance,
                        systemImage: "location"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let commissionDateText {
                    Label(
                        commissionDateText,
                        systemImage: "calendar.badge.clock"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let executionFrom = commission.executionFrom,
                   !executionFrom.isEmpty {
                    Label(
                        "Ausführung ab: \(Formatters.dateTimeText(executionFrom))",
                        systemImage: "calendar"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Label(
                    commission.assigneeName,
                    systemImage: "person"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if commission.canEditValue == false {
                    Label(
                        "Nur Ansicht",
                        systemImage: "eye"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
            .fill(
                Color(
                    .secondarySystemGroupedBackground
                )
            )
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
            .stroke(
                Color(.separator).opacity(0.35),
                lineWidth: 1
            )
        )
        .shadow(
            color: Color.black.opacity(0.04),
            radius: 5,
            x: 0,
            y: 2
        )
    }
    
    private var commissionDateText: String? {
        if let releaseDate = commission.releaseDate,
           !releaseDate.isEmpty {
            return (
                "Freigegeben: "
                + Formatters.dateTimeText(
                    releaseDate
                )
            )
        }

        if let recordingDate = commission.recordingDate,
           !recordingDate.isEmpty {
            return (
                "Erstellt: "
                + Formatters.dateTimeText(
                    recordingDate
                )
            )
        }

        return nil
    }

    private var acceptedAppointmentText: String? {
        guard
            let appointmentFrom =
                commission.acceptedAppointmentFrom,
            !appointmentFrom.isEmpty
        else {
            return nil
        }

        return Formatters.appointmentRangeText(
            fromValue: appointmentFrom,
            toValue: commission.acceptedAppointmentTo
        )
    }

    private var statusPill: some View {
        Text(commission.localStatusLabel)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                statusColor.opacity(0.15)
            )
            .foregroundStyle(statusColor)
            .clipShape(Capsule())
    }

    private var priorityPill: some View {
        Label(
            "Hoch",
            systemImage:
                "exclamationmark.triangle.fill"
        )
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Color.red.opacity(0.15)
        )
        .foregroundStyle(.red)
        .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch commission.localStatus {
        case "open":
            return .blue
        case "in_progress":
            return .orange
        case "done":
            return .green
        default:
            return .gray
        }
    }
}

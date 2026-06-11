import SwiftUI

struct CommissionRowView: View {
    let commission: Commission
    @EnvironmentObject private var locationStore: LocationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "house.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 8) {
                    Text(primaryAddressText)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(3)

                    if let tenantName = commission.tenantName, !tenantName.isEmpty {
                        Label(tenantName, systemImage: "person.text.rectangle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    if let location = commission.apartmentLocation, !location.isEmpty {
                        Label(location, systemImage: "rectangle.split.2x1")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                Text(commission.localStatusLabel)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(statusColor.opacity(0.15))
                    .foregroundStyle(statusColor)
                    .clipShape(Capsule())
            }

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                Text(commission.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Label(commission.displayNumber, systemImage: "number")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let distance = locationStore.distanceText(to: commission) {
                    Label(distance, systemImage: "location")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Label(Formatters.dateTimeText(commission.executionFrom), systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label(commission.assigneeName, systemImage: "person")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if commission.canEditValue == false {
                    Label("Nur Ansicht", systemImage: "eye")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 5, x: 0, y: 2)
    }

    private var primaryAddressText: String {
        if let address = commission.apartmentAddress, !address.isEmpty {
            return address
        }

        if let location = commission.apartmentLocation, !location.isEmpty {
            return location
        }

        return commission.displayTitle
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

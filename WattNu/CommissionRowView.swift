import SwiftUI

struct CommissionRowView: View {
    let commission: Commission
    @EnvironmentObject private var locationStore: LocationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(primaryAddressText)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                } icon: {
                    Image(systemName: "house.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
                .padding(.trailing, 115)

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
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                if commission.isHighPriorityValue {
                    Label(
                        "Hohe Priorität",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                }
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
        .overlay(alignment: .topTrailing) {
            Text(commission.localStatusLabel)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(statusColor.opacity(0.15))
                .foregroundStyle(statusColor)
                .clipShape(Capsule())
                .padding(.top, 14)
                .padding(.trailing, 14)
        }
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

import SwiftUI

struct CommissionRowView: View {
    let commission: Commission
    @EnvironmentObject private var locationStore: LocationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(commission.displayTitle)
                    .font(.headline)

                Spacer()

                Text(commission.localStatusLabel)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.15))
                    .foregroundStyle(statusColor)
                    .clipShape(Capsule())
            }

            HStack {
                Label(commission.displayNumber, systemImage: "number")
                Spacer()
                Label(Formatters.dateTimeText(commission.executionFrom), systemImage: "calendar")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let address = commission.apartmentAddress, !address.isEmpty {
                Label(address, systemImage: "house")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let location = commission.apartmentLocation, !location.isEmpty {
                Label(location, systemImage: "rectangle.split.2x1")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let tenantName = commission.tenantName, !tenantName.isEmpty {
                Label(tenantName, systemImage: "person.text.rectangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            
            if let distance = locationStore.distanceText(to: commission) {
                Label(distance, systemImage: "location")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Label(commission.assigneeName, systemImage: "person")
                .font(.caption)
                .foregroundStyle(.secondary)

            if commission.canEditValue == false {
                Label("Nur Ansicht", systemImage: "eye")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
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

import SwiftUI

struct SafetyInspectionRowView: View {
    let job: SafetyInspectionJob

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checklist")
                    .font(.title3)
                    .foregroundStyle(
                        job.isOverdue
                        ? Color.red
                        : Color.orange
                    )
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 6) {
                    Text(job.group.name)
                        .font(.headline)

                    Text(job.objectTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)

                    if let location = job.object.location,
                       !location.isEmpty {
                        Text(location)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                Text(job.statusLabel)
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
                Label(
                    "Fällig bis \(Formatters.dateText(job.dueTo))",
                    systemImage: "calendar.badge.clock"
                )
                .foregroundStyle(
                    job.isOverdue
                    ? Color.red
                    : Color.secondary
                )

                Label(
                    "\(job.progress.checkedCount) von "
                    + "\(job.progress.resultCount) Prüfpunkten",
                    systemImage: "list.bullet.rectangle"
                )
                .foregroundStyle(.secondary)

                if job.progress.defectCount > 0 {
                    Label(
                        "\(job.progress.defectCount) Mängel",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                }

                Label(
                    job.assignedUser?.displayName
                    ?? "Nicht zugeordnet",
                    systemImage: "person"
                )
                .foregroundStyle(.secondary)
            }
            .font(.caption)
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
                job.isOverdue
                ? Color.red.opacity(0.08)
                : Color(.secondarySystemGroupedBackground)
            )
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
            .stroke(
                job.isOverdue
                ? Color.red.opacity(0.45)
                : Color(.separator).opacity(0.35),
                lineWidth: 1
            )
        )
    }

    private var statusColor: Color {
        if job.isOverdue {
            return .red
        }

        switch job.status {
        case "planned":
            return .orange
        case "in_progress":
            return .blue
        case "completed", "completed_with_defects":
            return .green
        default:
            return .gray
        }
    }
}

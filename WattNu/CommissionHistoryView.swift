import SwiftUI

struct CommissionHistoryView: View {
    @EnvironmentObject private var session: SessionStore

    let commission: Commission

    @State private var entries: [CommissionHistoryEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && entries.isEmpty {
                ProgressView(
                    "Verlauf wird geladen …"
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
            } else if entries.isEmpty {
                ContentUnavailableView(
                    "Kein Verlauf",
                    systemImage: "clock.arrow.circlepath",
                    description: Text(
                        "Für diesen Auftrag wurden noch keine Aktionen protokolliert."
                    )
                )
            } else {
                List(entries) { entry in
                    HStack(
                        alignment: .top,
                        spacing: 12
                    ) {
                        Image(
                            systemName: iconName(
                                for: entry.action
                            )
                        )
                        .foregroundStyle(
                            iconColor(
                                for: entry.action
                            )
                        )
                        .frame(width: 24)

                        VStack(
                            alignment: .leading,
                            spacing: 6
                        ) {
                            Text(entry.title)
                                .font(.headline)

                            if let detail = entry.detail,
                               !detail.isEmpty {
                                Text(detail)
                                    .font(.subheadline)
                                    .foregroundStyle(
                                        .secondary
                                    )
                            }

                            HStack(spacing: 6) {
                                Label(
                                    entry.actorName,
                                    systemImage: "person"
                                )

                                Spacer()

                                Text(
                                    Formatters.dateTimeText(
                                        entry.createdAt
                                    )
                                )
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 5)
                }
                .listStyle(.plain)
                .refreshable {
                    await loadHistory()
                }
            }
        }
        .refreshForCommissionChanges { await loadHistory(refresh: false) }
        .refreshWhileActive(id: commission.id) {
            await loadHistory()
        }
        .alert(
            "Fehler",
            isPresented: Binding(
                get: {
                    errorMessage != nil
                },
                set: { newValue in
                    if !newValue {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button(
                "OK",
                role: .cancel
            ) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadHistory(refresh: Bool = true) async {
        isLoading = true

        defer {
            isLoading = false
        }

        do {
            entries = try await session.apiClient
                .fetchCommissionHistory(
                    commissionId: commission.id,
                    refresh: refresh
                )
        } catch {
            if error.isRequestCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    private func iconName(
        for action: String
    ) -> String {
        if action.hasPrefix("erp.") {
            return "arrow.triangle.2.circlepath"
        }

        if action.hasPrefix("inventory.") {
            return "shippingbox"
        }

        if action.hasPrefix("time.") {
            return "clock"
        }

        if action == "commission.start" {
            return "play.fill"
        }

        if action == "commission.complete" {
            return "checkmark.circle"
        }

        if action.hasPrefix("commission.create") {
            return "plus.circle"
        }

        if action == "webhook.wowiport" {
            return "arrow.down.circle"
        }

        return "circle.fill"
    }

    private func iconColor(
        for action: String
    ) -> Color {
        if action == "erp.outbox.failed" {
            return .red
        }

        if action == "erp.outbox.succeeded" {
            return .green
        }

        if action.hasPrefix("inventory.") {
            return .orange
        }

        if action.hasPrefix("time.") {
            return .blue
        }

        return .secondary
    }
}

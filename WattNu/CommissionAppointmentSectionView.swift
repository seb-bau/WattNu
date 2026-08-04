import SwiftUI

struct CommissionAppointmentSectionView: View {
    @EnvironmentObject private var session: SessionStore

    let commission: Commission

    @State private var requests: [CommissionAppointmentRequest] = []
    @State private var composerPresented = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack {
                Text("Terminvereinbarung")
                    .font(.headline)

                Spacer()

                Button {
                    Task {
                        await loadRequests()
                    }
                } label: {
                    Image(
                        systemName: "arrow.clockwise"
                    )
                }
                .disabled(isLoading)
            }

            if let appointmentFrom = commission.acceptedAppointmentFrom {
                VStack(
                    alignment: .leading,
                    spacing: 6
                ) {
                    Label(
                        "Termin bestätigt",
                        systemImage: "calendar.badge.checkmark"
                    )
                    .font(.headline)
                    .foregroundStyle(.green)

                    Text(
                        appointmentText(
                            from: appointmentFrom,
                            to: commission.acceptedAppointmentTo
                        )
                    )

                    if let comment = commission.acceptedAppointmentComment,
                       !comment.isEmpty {
                        Text(comment)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .background(
                    Color.green.opacity(0.12)
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 12
                    )
                )
            }

            if isLoading && requests.isEmpty {
                ProgressView()
            } else {
                ForEach(
                    requests.prefix(5)
                ) { item in
                    VStack(
                        alignment: .leading,
                        spacing: 5
                    ) {
                        HStack {
                            Text(item.statusLabel)
                                .font(.subheadline.bold())
                                .foregroundStyle(
                                    statusColor(
                                        item.status
                                    )
                                )

                            Spacer()

                            Text(
                                Formatters.dateTimeText(
                                    item.sentAt
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Text(item.recipientEmail)
                            .font(.caption)

                        ForEach(item.proposals) { proposal in
                            HStack {
                                Image(
                                    systemName: proposal.accepted
                                    ? "checkmark.circle.fill"
                                    : "circle"
                                )
                                .foregroundStyle(
                                    proposal.accepted
                                    ? .green
                                    : .secondary
                                )

                                Text(
                                    proposal.displayText
                                )
                            }
                            .font(.caption)
                        }

                        if let tenantComment = item.tenantComment,
                           !tenantComment.isEmpty {
                            Text(
                                "Kommentar: \(tenantComment)"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    Divider()
                }
            }

            if commission.canEditValue
                && commission.isActionableValue {
                Button {
                    composerPresented = true
                } label: {
                    Label(
                        "Terminvorschläge senden",
                        systemImage: "calendar.badge.plus"
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding()
        .background(.thinMaterial)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18
            )
        )
        .task {
            await loadRequests()

            await AppointmentReminderService.schedule(
                for: commission
            )
        }
        .sheet(
            isPresented: $composerPresented
        ) {
            NavigationStack {
                AppointmentProposalComposerView(
                    commission: commission
                ) { newRequest in
                    requests.insert(
                        newRequest,
                        at: 0
                    )
                }
            }
            .environmentObject(session)
        }
        .alert(
            "Fehler",
            isPresented: Binding(
                get: {
                    errorMessage != nil
                },
                set: { visible in
                    if !visible {
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

    private func loadRequests() async {
        isLoading = true

        defer {
            isLoading = false
        }

        do {
            requests = try await session.apiClient
                .fetchCommissionAppointments(
                    commissionId: commission.id
                )
        } catch {
            if error.isRequestCancellation {
                return
            }

            errorMessage = error.localizedDescription
        }
    }

    private func statusColor(
        _ status: String
    ) -> Color {
        switch status {
        case "accepted":
            return .green
        case "rejected":
            return .red
        case "pending":
            return .orange
        default:
            return .secondary
        }
    }

    private func appointmentText(
        from: String,
        to: String?
    ) -> String {
        let startText = Formatters.dateTimeText(
            from
        )

        guard let to else {
            return startText
        }

        return "\(startText) bis \(Formatters.dateTimeText(to))"
    }
}

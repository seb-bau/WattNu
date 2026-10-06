import SwiftUI

struct CommissionAppointmentSectionView: View {
    @EnvironmentObject private var session: SessionStore

    let commission: Commission
    let onCommissionUpdated: (Commission) -> Void

    @State private var requests: [CommissionAppointmentRequest] = []
    @State private var composerPresented = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var cancellationConfirmationPresented = false
    @State private var isCancelling = false
    @State private var manualEntryPresented = false

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack {
                Text("Terminvereinbarung")
                    .font(.headline)

                Spacer()

                if commission.acceptedAppointmentFrom == nil {
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
                    
                    if commission.canEditValue {
                        Button {
                            cancellationConfirmationPresented = true
                        } label: {
                            if isCancelling {
                                ProgressView()
                            } else {
                                Label(
                                    "Bestätigten Termin aufheben",
                                    systemImage: "calendar.badge.minus"
                                )
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(isCancelling)
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

            if commission.acceptedAppointmentFrom == nil
                && isLoading
                && requests.isEmpty {
                ProgressView()
            } else if commission.acceptedAppointmentFrom == nil {
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
                && commission.isActionableValue
                && commission.acceptedAppointmentFrom == nil {
                HStack(alignment: .top, spacing: 8) {
                    Button {
                        composerPresented = true
                    } label: {
                        Label(
                            "Terminvorschläge senden",
                            systemImage: "calendar.badge.plus"
                        )
                        .frame(maxWidth: .infinity)
                    }

                    Button {
                        manualEntryPresented = true
                    } label: {
                        Label(
                            "Termin eintragen",
                            systemImage: "calendar.badge.checkmark"
                        )
                        .frame(maxWidth: .infinity)
                    }
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
        .task(id: commission.acceptedAppointmentFrom) {
            if commission.acceptedAppointmentFrom == nil {
                await loadRequests()
            }

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
        .sheet(isPresented: $manualEntryPresented) {
            NavigationStack {
                ManualAppointmentEntryView(
                    commission: commission,
                    onSaved: onCommissionUpdated
                )
            }
            .environmentObject(session)
        }
        .confirmationDialog(
            "Bestätigten Termin aufheben?",
            isPresented: $cancellationConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(
                "Termin aufheben",
                role: .destructive
            ) {
                Task {
                    await cancelAcceptedAppointment()
                }
            }

            Button(
                "Abbrechen",
                role: .cancel
            ) {
            }
        } message: {
            Text(
                "Die bisherige Zusage bleibt im Verlauf gespeichert. Anschließend können neue Terminvorschläge versendet werden."
            )
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
    
    private func cancelAcceptedAppointment() async {
        guard !isCancelling else {
            return
        }

        isCancelling = true

        defer {
            isCancelling = false
        }

        do {
            let updatedCommission = try await session.apiClient
                .cancelAcceptedCommissionAppointment(
                    commissionId: commission.id
                )

            AppointmentReminderService.cancel(
                for: commission
            )

            onCommissionUpdated(
                updatedCommission
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
        Formatters.appointmentRangeText(
            fromValue: from,
            toValue: to
        ) ?? from
    }
}

import SwiftUI

private enum AppointmentProposalMode: String, CaseIterable, Identifiable {
    case window
    case custom

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .window:
            return "Zeitprofile"
        case .custom:
            return "Uhrzeiten"
        }
    }
}

private struct AppointmentProposalDraft: Identifiable {
    let id = UUID()
    var date: Date
    var windowId: Int?
    var startTime: Date
}

struct AppointmentProposalComposerView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    let commission: Commission
    let onSent: (CommissionAppointmentRequest) -> Void

    @State private var contacts: [CommissionContactItem] = []
    @State private var windows: [AppointmentWindow] = []
    @State private var customTimesEnabled = false
    @State private var customTimeDurationMinutes = 60
    @State private var proposalMode = AppointmentProposalMode.window
    @State private var recipientName = ""
    @State private var recipientEmail = ""
    @State private var message = ""
    @State private var proposals: [AppointmentProposalDraft] = []
    @State private var isLoading = false
    @State private var isSending = false
    @State private var errorMessage: String?

    private var contactsWithEmail: [CommissionContactItem] {
        contacts.filter {
            guard let email = $0.email else {
                return false
            }

            return !email.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        }
    }

    private var proposalsAreIncomplete: Bool {
        switch proposalMode {
        case .window:
            return windows.isEmpty
                || proposals.contains {
                    $0.windowId == nil
                }
        case .custom:
            return false
        }
    }

    var body: some View {
        Form {
            Section("Empfänger") {
                if !contactsWithEmail.isEmpty {
                    Picker(
                        "Bewohner",
                        selection: $recipientEmail
                    ) {
                        Text("Bitte auswählen")
                            .tag("")

                        ForEach(
                            contactsWithEmail
                        ) { contact in
                            Text(
                                [
                                    contact.name,
                                    contact.email
                                ]
                                .compactMap { $0 }
                                .joined(
                                    separator: " · "
                                )
                            )
                            .tag(contact.email ?? "")
                        }
                    }
                    .onChange(
                        of: recipientEmail
                    ) { _, email in
                        if let contact = contactsWithEmail.first(
                            where: {
                                $0.email == email
                            }
                        ) {
                            recipientName = contact.name ?? ""
                        }
                    }
                }

                TextField(
                    "Name",
                    text: $recipientName
                )

                TextField(
                    "E-Mail-Adresse",
                    text: $recipientEmail
                )
                .keyboardType(.emailAddress)
                .textInputAutapitalization(.never)
                .autocorrectionDisabled()
            }

            Section("Terminvorschläge") {
                if customTimesEnabled {
                    Picker(
                        "Art der Vorschläge",
                        selection: $proposalMode
                    ) {
                        ForEach(
                            AppointmentProposalMode.allCases
                        ) { mode in
                            Text(mode.title)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if proposalMode == .window
                    && windows.isEmpty {
                    Text(
                        "Es sind keine aktiven Zeitfenster vorhanden."
                    )
                    .foregroundStyle(.secondary)
                }

                if proposalMode == .custom {
                    Text(
                        "Für den Kalendereintrag werden ab dem gewählten Beginn \(customTimeDurationMinutes) Minuten reserviert. Die tatsächliche Arbeitsdauer kann davon abweichen."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                ForEach(
                    $proposals
                ) { $proposal in
                    VStack(
                        alignment: .leading,
                        spacing: 10
                    ) {
                        DatePicker(
                            "Datum",
                            selection: $proposal.date,
                            in: Calendar.current.startOfDay(
                                for: Date()
                            )...,
                            displayedComponents: .date
                        )

                        if proposalMode == .window {
                            Picker(
                                "Zeitraum",
                                selection: $proposal.windowId
                            ) {
                                Text("Bitte auswählen")
                                    .tag(Int?.none)

                                ForEach(windows) { window in
                                    Text(window.displayName)
                                        .tag(
                                            Optional(window.id)
                                        )
                                }
                            }
                        } else {
                            DatePicker(
                                "Beginn",
                                selection: $proposal.startTime,
                                displayedComponents: .hourAndMinute
                            )
                        }

                        if proposals.count > 1 {
                            Button(
                                "Vorschlag entfernen",
                                role: .destructive
                            ) {
                                proposals.removeAll {
                                    $0.id == proposal.id
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Button {
                    addProposal()
                } label: {
                    Label(
                        "Weiteren Vorschlag hinzufügen",
                        systemImage: "plus.circle"
                    )
                }
                .disabled(
                    proposals.count >= 12
                    || (
                        proposalMode == .window
                        && windows.isEmpty
                    )
                )
            }

            Section("Nachricht") {
                TextField(
                    "Optionale Nachricht",
                    text: $message,
                    axis: .vertical
                )
                .lineLimit(3...8)
            }

            Section {
                Button {
                    Task {
                        await sendProposals()
                    }
                } label: {
                    HStack {
                        Spacer()

                        if isSending {
                            ProgressView()
                        } else {
                            Label(
                                "Terminvorschläge senden",
                                systemImage: "paperplane.fill"
                            )
                        }

                        Spacer()
                    }
                }
                .disabled(
                    isSending
                    || recipientEmail.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                    || proposals.isEmpty
                    || proposalsAreIncomplete
                )
            }
        }
        .navigationTitle("Terminvorschläge")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(
                placement: .cancellationAction
            ) {
                Button("Abbrechen") {
                    dismiss()
                }
            }
        }
        .task {
            await loadData()
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

    private func loadData() async {
        isLoading = true

        defer {
            isLoading = false
        }

        do {
            async let loadedContacts =
                session.apiClient.fetchCommissionContacts(
                    commissionId: commission.id
                )

            async let loadedConfiguration =
                session.apiClient.fetchAppointmentWindows()

            let result = try await (
                loadedContacts,
                loadedConfiguration
            )

            let availableContacts = result.0.filter { contact in
                guard let email = contact.email else {
                    return false
                }

                return !email.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            }

            contacts = result.0
            windows = result.1.items
            customTimesEnabled = (
                result.1.customTimesEnabled
            )
            customTimeDurationMinutes = (
                result.1.customTimeDurationMinutes
            )

            if !customTimesEnabled {
                proposalMode = .window
            } else if windows.isEmpty {
                proposalMode = .custom
            }

            if recipientEmail.isEmpty {
                let tenantName = commission.tenantName?
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )

                let selectedContact = availableContacts.first { contact in
                    guard let tenantName,
                          !tenantName.isEmpty,
                          let contactName = contact.name else {
                        return false
                    }

                    return contactName.compare(
                        tenantName,
                        options: [
                            .caseInsensitive,
                            .diacriticInsensitive
                        ]
                    ) == .orderedSame
                } ?? availableContacts.first

                if let selectedContact,
                   let email = selectedContact.email {
                    recipientEmail = email
                    recipientName = (
                        selectedContact.name
                        ?? commission.tenantName
                        ?? ""
                    )
                } else if recipientName.isEmpty {
                    recipientName = commission.tenantName ?? ""
                }
            }

            if proposals.isEmpty {
                addProposal()
            }

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addProposal() {
        let calendar = Calendar.current
        let nextDate = calendar.date(
            byAdding: .day,
            value: proposals.count + 1,
            to: Date()
        ) ?? Date()
        let startTime = calendar.date(
            bySettingHour: 8,
            minute: 0,
            second: 0,
            of: nextDate
        ) ?? nextDate

        proposals.append(
            AppointmentProposalDraft(
                date: nextDate,
                windowId: windows.first?.id,
                startTime: startTime
            )
        )
    }

    private func sendProposals() async {
        let normalizedEmail = recipientEmail
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !normalizedEmail.isEmpty else {
            errorMessage = "Bitte eine E-Mail-Adresse angeben."
            return
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(
            identifier: "en_US_POSIX"
        )
        dateFormatter.calendar = Calendar(
            identifier: .gregorian
        )
        dateFormatter.timeZone = .current
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(
            identifier: "en_US_POSIX"
        )
        timeFormatter.calendar = Calendar(
            identifier: .gregorian
        )
        timeFormatter.timeZone = .current
        timeFormatter.dateFormat = "HH:mm"

        let calendar = Calendar.current
        var seenValues = Set<String>()
        var payloads: [AppointmentProposalCreatePayload] = []

        for proposal in proposals {
            let dateValue = dateFormatter.string(
                from: proposal.date
            )

            switch proposalMode {
            case .window:
                guard let windowId = proposal.windowId else {
                    errorMessage = "Bitte für jeden Vorschlag ein Zeitfenster auswählen."
                    return
                }

                let uniqueValue = (
                    "\(dateValue)-window-\(windowId)"
                )

                if seenValues.insert(
                    uniqueValue
                ).inserted {
                    payloads.append(
                        AppointmentProposalCreatePayload(
                            date: dateValue,
                            windowId: windowId,
                            startTime: nil
                        )
                    )
                }

            case .custom:
                var dateComponents = calendar.dateComponents(
                    [
                        .year,
                        .month,
                        .day
                    ],
                    from: proposal.date
                )
                let timeComponents = calendar.dateComponents(
                    [
                        .hour,
                        .minute
                    ],
                    from: proposal.startTime
                )
                dateComponents.hour = timeComponents.hour
                dateComponents.minute = timeComponents.minute
                dateComponents.second = 0

                guard let startDate = calendar.date(
                    from: dateComponents
                ) else {
                    errorMessage = "Der Beginn eines Vorschlags ist ungültig."
                    return
                }

                guard startDate > Date() else {
                    errorMessage = "Konkrete Termine müssen in der Zukunft liegen."
                    return
                }

                guard let endDate = calendar.date(
                    byAdding: .minute,
                    value: customTimeDurationMinutes,
                    to: startDate
                ),
                      calendar.isDate(
                        startDate,
                        inSameDayAs: endDate
                      ) else {
                    errorMessage = "Die konfigurierte Kalenderdauer darf nicht bis in den Folgetag reichen."
                    return
                }

                let startTimeValue = timeFormatter.string(
                    from: startDate
                )
                let uniqueValue = (
                    "\(dateValue)-custom-\(startTimeValue)"
                )

                if seenValues.insert(
                    uniqueValue
                ).inserted {
                    payloads.append(
                        AppointmentProposalCreatePayload(
                            date: dateValue,
                            windowId: nil,
                            startTime: startTimeValue
                        )
                    )
                }
            }
        }

        guard !payloads.isEmpty else {
            errorMessage = "Bitte mindestens einen Terminvorschlag angeben."
            return
        }

        isSending = true

        defer {
            isSending = false
        }

        do {
            let normalizedName = recipientName
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

            let normalizedMessage = message
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

            let result = try await session.apiClient
                .createCommissionAppointmentRequest(
                    commissionId: commission.id,
                    recipientName: (
                        normalizedName.isEmpty
                        ? nil
                        : normalizedName
                    ),
                    recipientEmail: normalizedEmail,
                    message: (
                        normalizedMessage.isEmpty
                        ? nil
                        : normalizedMessage
                    ),
                    proposals: payloads
                )

            onSent(result)
            dismiss()

        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

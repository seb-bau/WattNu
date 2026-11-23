import SwiftUI

struct OrderSectionView: View {
    @Environment(\.openURL) private var openURL

    let commission: Commission
    let isCheckingCompletionTime: Bool
    let startAction: () -> Void
    let rejectAction: () -> Void
    let completeAction: () -> Void
    let commissionUpdatedAction: (Commission) -> Void
    

    @State private var showContacts = false

    var body: some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: 18
            ) {
                VStack(
                    alignment: .leading,
                    spacing: 6
                ) {
                    if commission.isEconomicUnitOrder {
                        Label("Gesamte Wirtschaftseinheit", systemImage: "building.2.fill")
                            .font(.headline)
                            .foregroundStyle(.blue)
                        if let name = commission.economicUnitDisplayName {
                            Text(name)
                                .font(.subheadline.weight(.medium))
                        }
                    }
                    Text(commission.displayTitle)
                        .font(.title2.bold())
                    if commission.isHighPriorityValue {
                        Label(
                            "Hohe Priorität",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                    }

                    Text(
                        "Auftrag \(commission.displayNumber)"
                    )
                    .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 12) {
                        addressRow

                        DetailRowView(
                            title: "Lage",
                            value: commission.apartmentLocation ?? "-"
                        )

                        DetailRowView(
                            title: "Mieter",
                            value: commission.tenantName ?? "-"
                        )

                        DetailRowView(
                            title: "Status",
                            value: commission.localStatusLabel
                        )

                        if let executionFrom = commission.executionFrom?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                           !executionFrom.isEmpty {
                            DetailRowView(
                                title: "Ausführung von",
                                value: Formatters.dateTimeText(executionFrom)
                            )
                        }

                        if let executionTo = commission.executionTo?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                           !executionTo.isEmpty {
                            DetailRowView(
                                title: "Ausführung bis",
                                value: Formatters.dateTimeText(executionTo)
                            )
                        }

                        DetailRowView(
                            title: "Monteur",
                            value: commission.assigneeName
                        )

                        DetailRowView(
                            title: "Sachbearbeiter",
                            value: commission.creatorDisplayName
                        )
                    }
                    .padding()
                    .background(.thinMaterial)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 18)
                    )

                    CommissionPhotosSectionView(
                        commission: commission
                    )

                    CommissionAttachmentsSectionView(
                        commission: commission
                    )
                }

                if let text = commission.reporterText {
                    contactInformation(title: "Melder", text: text)
                }

                if let text = commission.otherAffectedText {
                    contactInformation(title: "Weitere Betroffene", text: text)
                }

                RelatedCommissionsSectionView(commissionId: commission.id)

                CommissionAppointmentSectionView(
                    commission: commission,
                    onCommissionUpdated: commissionUpdatedAction
                )

                if commission.isActionableValue || commission.objectType == "use_unit" || commission.objectType == "building" {
                    Button {
                        showContacts = true
                    } label: {
                        Label(
                            "Bewohner und Kontaktdaten anzeigen",
                            systemImage: "person.2"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    VStack(
                        alignment: .leading,
                        spacing: 8
                    ) {
                        Label(
                            "Übertragung ausstehend",
                            systemImage: "clock.arrow.circlepath"
                        )
                        .font(.headline)

                        Text(
                            commission.erpSyncMessage
                            ?? "Der Auftrag wird an Wowiport übertragen. Er kann erst nach Vergabe der Wowiport-Auftragsnummer bearbeitet werden."
                        )
                        .foregroundStyle(.secondary)
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
                }

                if !commission.positions.isEmpty {
                    VStack(
                        alignment: .leading,
                        spacing: 12
                    ) {
                        Text("Auftragspositionen")
                            .font(.headline)

                        ForEach(
                            Array(
                                commission.positions.enumerated()
                            ),
                            id: \.element.id
                        ) { index, position in
                            VStack(
                                alignment: .leading,
                                spacing: 6
                            ) {
                                Text(
                                    "\(index + 1). \(position.displayTextValue)"
                                )
                                .font(.subheadline.bold())

                                if let code = position.code, !code.isEmpty {
                                    Text(code)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if index
                                < commission.positions.count - 1 {
                                Divider()
                            }
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
                }

                if let description = commission.description,
                   !description.isEmpty,
                   commission.positions.isEmpty {
                    VStack(
                        alignment: .leading,
                        spacing: 8
                    ) {
                        Text("Beschreibung")
                            .font(.headline)

                        Text(description)
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
                }

                if commission.canEditValue == false {
                    Text(
                        "Dieser Auftrag ist nur zur Ansicht geöffnet."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
                    .background(.thinMaterial)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 18
                        )
                    )
                }

                VStack(spacing: 12) {
                    Button {
                        startAction()
                    } label: {
                        Label(
                            "Auftrag annehmen",
                            systemImage: "play.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        commission.localStatus
                            != "waiting_for_acceptance"
                        || !commission.isActionableValue
                        || !commission.canEditValue
                    )
                    
                    Button(role: .destructive) {
                        rejectAction()
                    } label: {
                        Label(
                            "Auftrag ablehnen",
                            systemImage: "xmark.circle.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        commission.localStatus
                            != "waiting_for_acceptance"
                        || !commission.isActionableValue
                        || !commission.canEditValue
                    )

                    Button {
                        completeAction()
                    } label: {
                        Group {
                            if isCheckingCompletionTime {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Zeiten werden geprüft …")
                                }
                            } else {
                                Label(
                                    "Auftrag abschließen",
                                    systemImage: "checkmark.circle.fill"
                                )
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        isCheckingCompletionTime
                        || commission.localStatus != "in_progress"
                        || !commission.isActionableValue
                        || !commission.canEditValue
                    )
                }
            }
            .padding()
        }
        .sheet(
            isPresented: $showContacts
        ) {
            NavigationStack {
                CommissionContactsView(
                    commission: commission
                )
            }
        }
    }

    private func contactInformation(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(text)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var addressRow: some View {
        if let address = commission.apartmentAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
           !address.isEmpty, address != "-" {
            HStack(spacing: 6) {
                Text(commission.addressLabel)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                Text(address)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)

                Button {
                    openDirections(to: address)
                } label: {
                    Image(systemName: "location.fill")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Route zur Auftragsadresse öffnen")
            }
            .font(.subheadline)
        } else {
            DetailRowView(title: commission.addressLabel, value: "-")
        }
    }

    private func openDirections(to address: String) {
        var components = URLComponents()
        components.scheme = "geo-navigation"
        components.host = ""
        components.path = "/directions"
        components.queryItems = [URLQueryItem(name: "destination", value: address)]
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")

        guard let navigationURL = components.url else { return }

        components.scheme = "https"
        components.host = "maps.apple.com"
        let appleMapsURL = components.url

        openURL(navigationURL) { accepted in
            if !accepted, let appleMapsURL {
                openURL(appleMapsURL)
            }
        }
    }
}


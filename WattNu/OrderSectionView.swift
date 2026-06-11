import SwiftUI

struct OrderSectionView: View {
    let commission: Commission
    let startAction: () -> Void
    let completeAction: () -> Void

    @State private var showContacts = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(commission.displayTitle)
                        .font(.title2.bold())

                    Text("Auftrag \(commission.displayNumber)")
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    DetailRowView(title: "Adresse", value: commission.apartmentAddress ?? "-")
                    DetailRowView(title: "Lage", value: commission.apartmentLocation ?? "-")
                    DetailRowView(title: "Mieter", value: commission.tenantName ?? "-")
                    DetailRowView(title: "Status", value: commission.localStatusLabel)
                    DetailRowView(title: "ERP-Status", value: commission.statusCode ?? commission.statusId.map(String.init) ?? "-")
                    DetailRowView(title: "Ausführung von", value: Formatters.dateTimeText(commission.executionFrom))
                    DetailRowView(title: "Ausführung bis", value: Formatters.dateTimeText(commission.executionTo))
                    DetailRowView(title: "Freigabe", value: Formatters.dateTimeText(commission.releaseDate))
                    DetailRowView(title: "Handwerker-ID", value: commission.craftsmanErpId.map(String.init) ?? "-")
                    DetailRowView(title: "Monteur", value: commission.assigneeName)
                    DetailRowView(title: "Kontakt Auftrag", value: commission.contactPerson ?? "-")
                }
                .padding()
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 18))

                Button {
                    showContacts = true
                } label: {
                    Label("Bewohner und Kontaktdaten anzeigen", systemImage: "person.2")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if let description = commission.description, !description.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Beschreibung")
                            .font(.headline)

                        Text(description)
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }

                if commission.canEditValue == false {
                    Text("Dieser Auftrag ist nur zur Ansicht geöffnet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }

                VStack(spacing: 12) {
                    Button {
                        startAction()
                    } label: {
                        Label("Auftrag starten", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(commission.localStatus == "in_progress" || commission.localStatus == "done" || commission.canEditValue == false)

                    Button(role: .destructive) {
                        completeAction()
                    } label: {
                        Label("Auftrag abschließen", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(commission.localStatus == "done" || commission.canEditValue == false)
                }
            }
            .padding()
        }
        .sheet(isPresented: $showContacts) {
            NavigationStack {
                CommissionContactsView(commission: commission)
            }
        }
    }
}

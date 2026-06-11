import SwiftUI

struct CommissionContactRowView: View {
    let contact: CommissionContactItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(contact.name ?? "Unbekannter Bewohner")
                    .font(.headline)

                if let role = contact.role, !role.isEmpty {
                    Text(role)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let birthDate = contact.birthDate, !birthDate.isEmpty {
                    Text("Geburtsdatum: \(birthDate)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                if let mobile = contact.mobile, !mobile.isEmpty {
                    ContactActionRowView(title: "Mobil", value: mobile, comment: contact.mobileComment, systemImage: "iphone", urlScheme: "tel")
                }

                if let phone = contact.phone, !phone.isEmpty {
                    ContactActionRowView(title: "Telefon", value: phone, comment: contact.phoneComment, systemImage: "phone", urlScheme: "tel")
                }

                if let email = contact.email, !email.isEmpty {
                    ContactActionRowView(title: "E-Mail", value: email, comment: contact.emailComment, systemImage: "envelope", urlScheme: "mailto")
                }

                ForEach(contact.additionalNumbers, id: \.self) { number in
                    ContactActionRowView(title: "Weitere Nummer", value: number, comment: nil, systemImage: "phone", urlScheme: "tel")
                }
            }
        }
        .padding(.vertical, 6)
    }
}

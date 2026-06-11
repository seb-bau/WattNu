import SwiftUI

struct CommissionFilterBarView: View {
    @Binding var scopeFilter: CommissionScopeFilter
    @Binding var statusFilter: CommissionStatusFilter
    @Binding var selectedUserId: Int?

    let users: [AppUser]
    let resultCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Umfang", selection: $scopeFilter) {
                ForEach(CommissionScopeFilter.allCases) { item in
                    Text(item.label).tag(item)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                Picker("Status", selection: $statusFilter) {
                    ForEach(CommissionStatusFilter.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }
                .pickerStyle(.menu)

                if scopeFilter == .all {
                    Picker("Kollege", selection: $selectedUserId) {
                        Text("Alle Kollegen").tag(Optional<Int>.none)

                        ForEach(users) { user in
                            Text(user.displayName).tag(Optional(user.id))
                        }
                    }
                    .pickerStyle(.menu)
                }

                Spacer()

                Text("\(resultCount) Aufträge")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.background)
    }
}

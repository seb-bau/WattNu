import SwiftUI

struct CommissionFilterBarView: View {
    @Binding var ownerFilter: CommissionOwnerFilter
    @Binding var statusFilter: CommissionStatusFilter
    @Binding var sortMode: CommissionSortMode

    let users: [AppUser]
    let currentUserId: Int?
    let resultCount: Int

    private var colleagueUsers: [AppUser] {
        users
            .filter {
                $0.id != currentUserId
            }
            .sorted {
                $0.displayName
                    .localizedCaseInsensitiveCompare(
                        $1.displayName
                    )
                == .orderedAscending
            }
    }

    private var ownerFilterLabel: String {
        switch ownerFilter {
        case .mine:
            return "Meine"
        case .all:
            return "Alle"
        case .user(let userId):
            return users.first {
                $0.id == userId
            }?.displayName ?? "Kollege"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Picker(
                    selection: $ownerFilter
                ) {
                    Text("Meine")
                        .tag(
                            CommissionOwnerFilter.mine
                        )

                    ForEach(colleagueUsers) { user in
                        Text(user.displayName)
                            .tag(
                                CommissionOwnerFilter
                                    .user(user.id)
                            )
                    }

                    Text("Alle")
                        .tag(
                            CommissionOwnerFilter.all
                        )
                } label: {
                    Text(ownerFilterLabel)
                        .lineLimit(1)
                }
                .pickerStyle(.menu)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )

                Picker(
                    selection: $statusFilter
                ) {
                    ForEach(
                        CommissionStatusFilter.allCases
                    ) { item in
                        Text(item.label)
                            .tag(item)
                    }
                } label: {
                    Text(statusFilter.label)
                        .lineLimit(1)
                }
                .pickerStyle(.menu)
                .frame(
                    maxWidth: .infinity,
                    alignment: .center
                )

                Picker(
                    selection: $sortMode
                ) {
                    ForEach(
                        CommissionSortMode.allCases
                    ) { mode in
                        Text(mode.label)
                            .tag(mode)
                    }
                } label: {
                    Text(sortMode.label)
                        .lineLimit(1)
                }
                .pickerStyle(.menu)
                .frame(
                    maxWidth: .infinity,
                    alignment: .trailing
                )
            }

            Text("\(resultCount) Aufträge")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(
                    maxWidth: .infinity,
                    alignment: .trailing
                )
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.background)
    }
}

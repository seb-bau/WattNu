import Combine
import Foundation
import SwiftUI
import UserNotifications

struct ProcessInfoMessage: Decodable, Identifiable {
    let id: String
    let processErpId: Int
    let body: String
    let authorName: String?
    let direction: String
    let date: String?
    let createdAt: String
    let version: Int
    let state: String
    let mailState: String
    var isUnread: Bool

    var isMine: Bool {
        direction == "craftsman"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case processErpId = "process_erp_id"
        case body
        case authorName = "author_name"
        case direction
        case date
        case createdAt = "created_at"
        case version
        case state
        case mailState = "mail_state"
        case isUnread = "is_unread"
    }
}

struct ProcessInfoListResponse: Decodable {
    let items: [ProcessInfoMessage]
    let syncError: String?

    enum CodingKeys: String, CodingKey {
        case items
        case syncError = "sync_error"
    }
}

struct ProcessInfoUnreadSummary: Decodable {
    let total: Int
    let byCommission: [String: Int]

    enum CodingKeys: String, CodingKey {
        case total
        case byCommission = "by_commission"
    }
}

struct ProcessInfoCreateRequest: Encodable {
    let requestId: String
    let body: String

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case body
    }
}

struct ProcessInfoReadRequest: Encodable {
    let infoIds: [String]

    enum CodingKeys: String, CodingKey {
        case infoIds = "info_ids"
    }
}

@MainActor
final class ProcessInfoStore: ObservableObject {
    static let shared = ProcessInfoStore()

    @Published private(set)
    var unreadTotal = 0

    @Published private(set)
    var unreadByCommission: [Int: Int] = [:]

    @Published private(set)
    var requestedCommissionId: Int?

    private init() {
    }

    func refresh(
        apiClient: APIClient
    ) async {
        do {
            apply(
                try await apiClient
                    .fetchProcessInfoUnreadSummary()
            )
        } catch {
            if error is CancellationError {
                return
            }
        }
    }

    func apply(
        _ summary: ProcessInfoUnreadSummary
    ) {
        unreadTotal = summary.total

        unreadByCommission = Dictionary(
            uniqueKeysWithValues:
                summary.byCommission.compactMap {
                    key, value in

                    guard let commissionId = Int(
                        key
                    ) else {
                        return nil
                    }

                    return (
                        commissionId,
                        value
                    )
                }
        )

        UNUserNotificationCenter
            .current()
            .setBadgeCount(
                max(summary.total, 0)
            ) { _ in }
    }

    func unreadCount(
        commissionId: Int
    ) -> Int {
        unreadByCommission[
            commissionId
        ] ?? 0
    }

    func requestInfos(
        commissionId: Int
    ) {
        requestedCommissionId = (
            commissionId
        )
    }

    func consumeInfoRequest(
        commissionId: Int
    ) -> Bool {
        guard (
            requestedCommissionId
            == commissionId
        ) else {
            return false
        }

        requestedCommissionId = nil
        return true
    }

    func reset() {
        unreadTotal = 0
        unreadByCommission = [:]
        requestedCommissionId = nil

        UNUserNotificationCenter
            .current()
            .setBadgeCount(0) { _ in }
    }
}

struct ProcessInfoView: View {
    @EnvironmentObject private var session:
        SessionStore

    @Environment(\.scenePhase)
    private var scenePhase

    let commissionId: Int

    @ObservedObject private var store =
        ProcessInfoStore.shared

    @State private var messages:
        [ProcessInfoMessage] = []

    @State private var draft = ""

    @State private var requestId =
        UUID().uuidString.lowercased()

    @State private var isLoading = false
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if (
                isLoading
                && messages.isEmpty
            ) {
                ProgressView(
                    "Informationen werden geladen …"
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
            } else if messages.isEmpty {
                ContentUnavailableView(
                    "Keine Informationen",
                    systemImage: "text.bubble",
                    description: Text(
                        "Für diesen Vorgang wurden "
                        + "noch keine Zusatzinformationen "
                        + "erfasst."
                    )
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(
                                messages
                            ) { message in
                                ProcessInfoBubble(
                                    message: message
                                )
                                .id(message.id)
                            }
                        }
                        .padding()
                    }
                    .refreshable {
                        await loadMessages()
                    }
                    .onChange(
                        of: messages.count
                    ) { _, _ in
                        if let lastId =
                            messages.last?.id {
                            withAnimation {
                                proxy.scrollTo(
                                    lastId,
                                    anchor: .bottom
                                )
                            }
                        }
                    }
                }
            }

            Divider()

            HStack(
                alignment: .bottom,
                spacing: 10
            ) {
                TextField(
                    "Zusatzinformation",
                    text: $draft,
                    axis: .vertical
                )
                .lineLimit(1...5)
                .textFieldStyle(
                    .roundedBorder
                )

                Button {
                    Task {
                        await sendMessage()
                    }
                } label: {
                    if isSending {
                        ProgressView()
                    } else {
                        Image(
                            systemName:
                                "paperplane.fill"
                        )
                    }
                }
                .buttonStyle(
                    .borderedProminent
                )
                .disabled(
                    isSending
                    || draft
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )
                        .isEmpty
                )
            }
            .padding()
            .background(.bar)
        }
        .task {
            await loadMessages()

            while !Task.isCancelled {
                try? await Task.sleep(
                    for: .seconds(30)
                )

                if scenePhase == .active {
                    await loadMessages(
                        showLoading: false
                    )
                }
            }
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

    private func loadMessages(
        showLoading: Bool = true
    ) async {
        if showLoading {
            isLoading = true
        }

        defer {
            if showLoading {
                isLoading = false
            }
        }

        do {
            let response =
                try await session
                    .apiClient
                    .fetchProcessInfos(
                        commissionId:
                            commissionId
                    )

            messages = response.items

            let unreadIds = messages
                .filter { $0.isUnread }
                .map(\.id)

            if !unreadIds.isEmpty {
                let summary =
                    try await session
                        .apiClient
                        .markProcessInfosRead(
                            commissionId:
                                commissionId,
                            infoIds:
                                unreadIds
                        )

                for index
                in messages.indices
                where unreadIds.contains(
                    messages[index].id
                ) {
                    messages[index]
                        .isUnread = false
                }

                store.apply(summary)
            } else {
                await store.refresh(
                    apiClient:
                        session.apiClient
                )
            }

            if let syncError =
                response.syncError,
               messages.isEmpty {
                errorMessage = syncError
            }
        } catch {
            if error.isRequestCancellation {
                return
            }

            errorMessage = (
                error.localizedDescription
            )
        }
    }

    private func sendMessage() async {
        let body = draft
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !body.isEmpty else {
            return
        }

        isSending = true

        defer {
            isSending = false
        }

        do {
            _ = try await session
                .apiClient
                .createProcessInfo(
                    commissionId:
                        commissionId,
                    requestId:
                        requestId,
                    body:
                        body
                )

            draft = ""
            requestId = UUID()
                .uuidString
                .lowercased()

            await loadMessages(
                showLoading: false
            )
        } catch {
            if error.isRequestCancellation {
                return
            }

            errorMessage = (
                error.localizedDescription
            )

            await loadMessages(
                showLoading: false
            )
        }
    }
}

private struct ProcessInfoBubble: View {
    let message: ProcessInfoMessage

    var body: some View {
        HStack {
            if message.isMine {
                Spacer(minLength: 44)
            }

            VStack(
                alignment:
                    message.isMine
                    ? .trailing
                    : .leading,
                spacing: 5
            ) {
                Text(
                    message.authorName
                    ?? (
                        message.isMine
                        ? "Handwerker"
                        : "Sachbearbeitung"
                    )
                )
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )

                Text(message.body)
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )

                HStack(spacing: 5) {
                    Text(displayDate)

                    if (
                        message.state
                        == "failed"
                    ) {
                        Text(
                            "Nicht übertragen"
                        )
                        .foregroundStyle(.red)
                    } else if (
                        message.state
                        == "uncertain"
                    ) {
                        Text(
                            "Übertragung wird geprüft"
                        )
                        .foregroundStyle(
                            .orange
                        )
                    } else if (
                        message.isMine
                        && message.mailState
                        == "failed"
                    ) {
                        Text(
                            "E-Mail ausstehend"
                        )
                        .foregroundStyle(
                            .orange
                        )
                    }
                }
                .font(.caption2)
                .foregroundStyle(
                    .secondary
                )
            }
            .padding(12)
            .background(
                message.isMine
                ? Color.accentColor
                    .opacity(0.17)
                : Color(
                    .secondarySystemGroupedBackground
                )
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
            )

            if !message.isMine {
                Spacer(minLength: 44)
            }
        }
    }

    private var displayDate: String {
        if let value = message.date,
           let date =
            Self.dayFormatter.date(
                from: value
            ) {
            return Self
                .displayDayFormatter
                .string(from: date)
        }

        if let date =
            ISO8601DateFormatter()
                .date(
                    from: message.createdAt
                ) {
            return Self
                .displayDateFormatter
                .string(from: date)
        }

        return ""
    }

    private static let dayFormatter:
        DateFormatter = {
            let formatter =
                DateFormatter()
            formatter.locale = Locale(
                identifier: "de_DE"
            )
            formatter.dateFormat =
                "yyyy-MM-dd"
            return formatter
        }()

    private static let displayDayFormatter:
        DateFormatter = {
            let formatter =
                DateFormatter()
            formatter.locale = Locale(
                identifier: "de_DE"
            )
            formatter.dateStyle =
                .medium
            formatter.timeStyle =
                .none
            return formatter
        }()

    private static let displayDateFormatter:
        DateFormatter = {
            let formatter =
                DateFormatter()
            formatter.locale = Locale(
                identifier: "de_DE"
            )
            formatter.dateStyle =
                .medium
            formatter.timeStyle =
                .short
            return formatter
        }()
}

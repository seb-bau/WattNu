import CryptoKit
import Foundation

extension SynchronizationItem {
    init(operation: CommissionOfflineOperation) {
        self.init(
            id: operation.id,
            entityID: operation.groupID,
            title: operation.title,
            createdAt: operation.createdAt,
            error: operation.error,
            details: operation.errorDetails.flatMap { String(data: $0, encoding: .utf8) },
            errorCode: operation.errorCode
        )
    }
}

struct SynchronizationReportEntry: Encodable {
    let module: String
    let title: String
    let entityID: Int?
    let createdAt: String?
    let error: String?
    let errorCode: String?

    enum CodingKeys: String, CodingKey {
        case module, title, error
        case entityID = "entity_id"
        case createdAt = "created_at"
        case errorCode = "error_code"
    }

    init?(item: SynchronizationItem, module: String, now: Date) {
        guard item.error != nil || now.timeIntervalSince(item.createdAt) >= 5 * 60 else { return nil }
        self.module = module
        title = item.title
        entityID = item.entityID > 0 ? item.entityID : nil
        createdAt = item.createdAt.ISO8601Format()
        error = item.error.map { Self.errorSummary($0, details: item.details) }
        errorCode = error == nil ? nil : item.errorCode.map { String($0.prefix(64)) }
    }

    init(issue: SynchronizationPreparationIssue) {
        module = "commissions"
        title = issue.title
        entityID = nil
        createdAt = nil
        error = Self.errorSummary(issue.messages.joined(separator: " · "))
        errorCode = nil
    }

    private static func errorSummary(_ message: String, details: String? = nil) -> String {
        var summary = message
        if let details, !details.isEmpty, summary.hasSuffix(details) {
            summary.removeLast(details.count)
            summary = summary.trimmingCharacters(in: CharacterSet(charactersIn: ": ").union(.whitespacesAndNewlines))
        }
        if summary.hasPrefix("Serverfehler "), let separator = summary.firstIndex(of: ":") {
            let body = String(summary[summary.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let first = body.first, "{[<".contains(first) {
                let payload = try? CommissionOfflineJSON.object(Data(body.utf8))
                summary = payload?["message"] as? String ?? String(summary[..<separator])
            }
        }
        let firstLine = summary.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let text = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Die Synchronisierung benötigt Prüfung." : String(text.prefix(500))
    }
}

struct SynchronizationReport: Encodable {
    let deviceID: String
    let appVersion: String
    let appBuild: String
    let entries: [SynchronizationReportEntry]
    let totalEntries: Int

    enum CodingKeys: String, CodingKey {
        case entries
        case deviceID = "device_id"
        case appVersion = "app_version"
        case appBuild = "app_build"
        case totalEntries = "total_entries"
    }

    init(deviceID: String, appVersion: String, appBuild: String, entries: [SynchronizationReportEntry]) {
        self.deviceID = deviceID
        self.appVersion = appVersion
        self.appBuild = appBuild
        totalEntries = entries.count
        self.entries = Array(entries.sorted { first, second in
            if (first.error != nil) != (second.error != nil) { return first.error != nil }
            return (first.createdAt ?? "") < (second.createdAt ?? "")
        }.prefix(100))
    }
}

@MainActor
final class SynchronizationReporter {
    private let defaults: UserDefaults
    private var pendingReports = Set<String>()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func sendIfNeeded(
        _ report: SynchronizationReport,
        baseURL: URL,
        userID: Int,
        now: Date = Date(),
        send: (SynchronizationReport) async throws -> Void
    ) async {
        let account = Data("\(baseURL.absoluteString)|\(userID)|\(report.deviceID)".utf8)
        let key = "synchronizationReport." + SHA256.hash(data: account).map { String(format: "%02x", $0) }.joined()
        let attemptKey = key + ".lastAttempt"
        let unresolvedKey = key + ".unresolved"

        guard !Task.isCancelled, !pendingReports.contains(key),
              !report.entries.isEmpty || defaults.bool(forKey: unresolvedKey) else { return }
        if let lastAttempt = defaults.object(forKey: attemptKey) as? Date,
           (0..<(30 * 60)).contains(now.timeIntervalSince(lastAttempt)) { return }

        pendingReports.insert(key)
        defer { pendingReports.remove(key) }
        defaults.set(now, forKey: attemptKey)
        if !report.entries.isEmpty { defaults.set(true, forKey: unresolvedKey) }

        do {
            try await send(report)
            if report.entries.isEmpty { defaults.removeObject(forKey: unresolvedKey) }
        } catch {
            return
        }
    }
}

import Foundation
import Testing
@testable import WattNu

@MainActor
struct SynchronizationReportTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let baseURL = URL(string: "https://example.invalid")!

    @Test func aFreshCompletionIsOmittedAndAnOlderWaitingEntryHasNoError() throws {
        let fresh = SynchronizationItem(
            id: "fresh", entityID: 10, title: "Auftrag abschließen", createdAt: now,
            error: nil, details: nil
        )
        #expect(SynchronizationReportEntry(item: fresh, module: "commissions", now: now) == nil)

        let waiting = try #require(SynchronizationReportEntry(item: fresh, module: "commissions", now: now.addingTimeInterval(301)))
        #expect(waiting.error == nil)
        #expect(waiting.entityID == 10)

        let failed = SynchronizationItem(
            id: "failed", entityID: 12, title: "Zeitbuchung", createdAt: now,
            error: "Serverfehler 409: {\"local\":\"private payload\"}",
            details: "{\"local\":\"private payload\"}", errorCode: "conflict"
        )
        let entry = try #require(SynchronizationReportEntry(item: failed, module: "commissions", now: now))
        #expect(entry.error == "Serverfehler 409")
        #expect(entry.errorCode == "conflict")
    }

    @Test func transmissionIsThrottledAcrossRestartsAndClearsTheLastReportOnce() async throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let pending = SynchronizationItem(
            id: "pending", entityID: 10, title: "Zeitbuchung", createdAt: now,
            error: "Die Übertragung wurde abgelehnt.", details: nil
        )
        let entry = try #require(SynchronizationReportEntry(item: pending, module: "commissions", now: now))
        let report = SynchronizationReport(deviceID: "device", appVersion: "1.2.3", appBuild: "56", entries: [entry])
        let clear = SynchronizationReport(deviceID: "device", appVersion: "1.2.3", appBuild: "56", entries: [])
        var sentCounts = [Int]()
        let send: (SynchronizationReport) async throws -> Void = { sentCounts.append($0.totalEntries) }

        let reporter = SynchronizationReporter(defaults: defaults)
        await reporter.sendIfNeeded(clear, baseURL: baseURL, userID: 1, now: now, send: send)
        await reporter.sendIfNeeded(report, baseURL: baseURL, userID: 1, now: now, send: send)
        let restarted = SynchronizationReporter(defaults: defaults)
        await restarted.sendIfNeeded(report, baseURL: baseURL, userID: 1, now: now.addingTimeInterval(300), send: send)
        await restarted.sendIfNeeded(clear, baseURL: baseURL, userID: 1, now: now.addingTimeInterval(1800), send: send)
        await restarted.sendIfNeeded(clear, baseURL: baseURL, userID: 1, now: now.addingTimeInterval(3600), send: send)
        #expect(sentCounts == [1, 0])
    }
}

import CryptoKit
import Foundation
import Testing
@testable import WattNu

@MainActor
struct CommissionPreparationTests {
    private let baseURL = URL(string: "https://preparation.example.invalid")!
    private let user = AppUser(id: 1, email: "one@example.invalid", displayName: "One", craftsmanErpId: nil, isAdmin: false, isForeman: false)

    private func fixture(dates: [String], cached: Bool = false, queued: Bool = true, oldErrors: Bool = false) throws -> PreparationFixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var snapshot = CommissionOfflineSnapshot()
        for date in dates {
            let query = [CommissionOfflineQuery(name: "date", value: date)]
            let key = CommissionOfflineResource.key("/api/my-time", query)
            if cached {
                snapshot.resources[key] = CommissionOfflineResource(path: "/api/my-time", query: query, data: PreparationScenario.dayData(date), fetchedAt: .distantPast)
            }
            if queued { snapshot.preparation.append(key) }
            if oldErrors { snapshot.preparationErrors[key] = "Vorheriger Verbindungsfehler" }
        }
        let account = SHA256.hash(data: Data("\(baseURL.absoluteString)|1".utf8)).map { String(format: "%02x", $0) }.joined()
        let root = directory.appendingPathComponent(account)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: root.appendingPathComponent("state.json"))
        let scenario = PreparationScenario()
        let token = PreparationRegistry.shared.register(scenario)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PreparationURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let store = CommissionOfflineStore(storageDirectory: directory, session: session)
        store.setActive(false)
        try store.bind(user: user, baseURL: baseURL, token: token)
        return PreparationFixture(directory: directory, store: store, scenario: scenario, token: token, session: session)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }

    @Test func successfulMonthPreparationClearsOldErrorsAndDoesNotRepeatDays() async throws {
        let dates = (1...30).map { String(format: "2026-11-%02d", $0) }
        let fixture = try fixture(dates: dates, cached: true, oldErrors: true)
        defer { fixture.close() }
        let store = fixture.store
        #expect(store.preparationIssues.count == 1)
        #expect(store.preparationIssues.first?.paths.count == 30)
        store.setActive(true)
        try await waitUntil { store.snapshot.preparation.isEmpty }
        #expect(store.snapshot.preparationErrors.isEmpty)
        #expect(store.preparationIssues.isEmpty)
        #expect(store.message.isEmpty)
        #expect(dates.allSatisfy { fixture.scenario.count("/api/my-time?date=" + $0) == 1 })
        try store.retrySynchronization()
        try await Task.sleep(for: .milliseconds(100))
        #expect(dates.allSatisfy { fixture.scenario.count("/api/my-time?date=" + $0) == 1 })
        store.stop()
        let reopened = CommissionOfflineStore(storageDirectory: fixture.directory)
        reopened.setActive(false)
        try reopened.bind(user: user, baseURL: baseURL, token: "reopened")
        #expect(reopened.snapshot.preparation.isEmpty)
        #expect(reopened.snapshot.preparationErrors.isEmpty)
        reopened.stop()
    }

    @Test func failedDayDoesNotFailOtherDaysAndItsErrorClearsAfterRetry() async throws {
        let first = "2026-11-01"
        let second = "2026-11-02"
        let fixture = try fixture(dates: [first, second])
        defer { fixture.close() }
        let key = "/api/my-time?date=" + first
        fixture.scenario.setReplies([.response(503, Data("{\"message\":\"Zeitdaten vorübergehend nicht erreichbar.\"}".utf8)), .response(200, PreparationScenario.dayData(first))], for: key)
        let store = fixture.store
        store.setActive(true)
        try await waitUntil { store.snapshot.resources["/api/my-time?date=" + second] != nil }
        #expect(store.snapshot.preparation == [key])
        #expect(store.snapshot.preparationErrors == [key: "Zeitdaten vorübergehend nicht erreichbar."])
        #expect(store.message.isEmpty)
        try store.retrySynchronization()
        try await waitUntil { store.snapshot.preparation.isEmpty }
        #expect(store.snapshot.preparationErrors.isEmpty)
        #expect(fixture.scenario.count(key) == 2)
        #expect(fixture.scenario.count("/api/my-time?date=" + second) == 1)
    }

    @Test func offlinePreparationShowsOneConnectionMessageAndRecovers() async throws {
        let first = "2026-11-01"
        let second = "2026-11-02"
        let fixture = try fixture(dates: [first, second])
        defer { fixture.close() }
        fixture.scenario.setReplies([.failure(.notConnectedToInternet), .response(200, PreparationScenario.dayData(first))], for: "/api/my-time?date=" + first)
        let store = fixture.store
        store.setActive(true)
        try await waitUntil { !store.preparationMessage.isEmpty }
        #expect(store.snapshot.preparation.count == 2)
        #expect(store.snapshot.preparationErrors.isEmpty)
        #expect(store.message.isEmpty)
        try store.retrySynchronization()
        try await waitUntil { store.snapshot.preparation.isEmpty }
        #expect(store.preparationMessage.isEmpty)
        #expect(store.snapshot.preparationErrors.isEmpty)
    }

    @Test func cancelledBackgroundReadDoesNotBecomeSynchronizationError() async throws {
        let date = "2026-11-01"
        let fixture = try fixture(dates: [date], cached: true, queued: false)
        defer { fixture.close() }
        let key = "/api/my-time?date=" + date
        fixture.scenario.setReplies([.failure(.cancelled)], for: key)
        let store = fixture.store
        store.setActive(true)
        _ = try await store.execute(path: "/api/my-time", method: "GET", queryItems: [URLQueryItem(name: "date", value: date)], body: nil, contentType: nil, accept: "application/json")
        try await waitUntil { fixture.scenario.count(key) == 1 }
        try await Task.sleep(for: .milliseconds(100))
        #expect(store.message.isEmpty)
        #expect(store.preparationMessage.isEmpty)
        #expect(store.snapshot.preparationErrors.isEmpty)
        #expect(store.snapshot.preparation.isEmpty)
    }

    @Test func cancelledDeliveryIssueReadDoesNotSetAMessage() async throws {
        let fixture = try fixture(dates: [])
        defer { fixture.close() }
        fixture.scenario.setReplies([.failure(.cancelled)], for: "/api/mobile/delivery-issues")
        await fixture.store.loadDeliveryIssues()
        #expect(fixture.store.message.isEmpty)
        #expect(fixture.store.snapshot.preparationErrors.isEmpty)
    }
}

@MainActor
private struct PreparationFixture {
    let directory: URL
    let store: CommissionOfflineStore
    let scenario: PreparationScenario
    let token: String
    let session: URLSession

    func close() {
        store.stop()
        session.invalidateAndCancel()
        PreparationRegistry.shared.remove(token)
        try? FileManager.default.removeItem(at: directory)
    }
}

private enum PreparationReply {
    case response(Int, Data)
    case failure(URLError.Code)
}

private final class PreparationScenario: @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [String: [PreparationReply]] = [:]
    private var requests: [String: Int] = [:]

    static func dayData(_ date: String) -> Data {
        try! JSONSerialization.data(withJSONObject: ["date": date, "recorded_minutes": 0, "status": "missing", "items": []])
    }

    func setReplies(_ values: [PreparationReply], for key: String) {
        lock.lock()
        defer { lock.unlock() }
        replies[key] = values
    }

    func count(_ key: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return requests[key, default: 0]
    }

    func reply(to url: URL) -> PreparationReply {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let key = url.path + (components?.percentEncodedQuery.map { "?" + $0 } ?? "")
        lock.lock()
        defer { lock.unlock() }
        requests[key, default: 0] += 1
        if var values = replies[key], let value = values.first {
            if values.count > 1 { values.removeFirst(); replies[key] = values }
            return value
        }
        if url.path == "/api/my-time", let date = components?.queryItems?.first(where: { $0.name == "date" })?.value {
            return .response(200, Self.dayData(date))
        }
        return .response(200, Data("{\"items\":[]}".utf8))
    }
}

private final class PreparationRegistry: @unchecked Sendable {
    static let shared = PreparationRegistry()
    private let lock = NSLock()
    private var scenarios: [String: PreparationScenario] = [:]

    func register(_ scenario: PreparationScenario) -> String {
        lock.lock()
        defer { lock.unlock() }
        let token = UUID().uuidString
        scenarios[token] = scenario
        return token
    }

    func scenario(for token: String) -> PreparationScenario? {
        lock.lock()
        defer { lock.unlock() }
        return scenarios[token]
    }

    func remove(_ token: String) {
        lock.lock()
        defer { lock.unlock() }
        scenarios[token] = nil
    }
}

private final class PreparationURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let authorization = request.value(forHTTPHeaderField: "Authorization"),
              let scenario = PreparationRegistry.shared.scenario(for: String(authorization.dropFirst("Bearer ".count))) else {
            client?.urlProtocol(self, didFailWithError: URLError(.userAuthenticationRequired))
            return
        }
        switch scenario.reply(to: url) {
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .response(let status, let data):
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

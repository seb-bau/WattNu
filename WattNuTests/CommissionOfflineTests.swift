import CryptoKit
import Foundation
import Testing
@testable import WattNu

@MainActor
struct CommissionOfflineTests {
    private let baseURL = URL(string: "https://example.invalid")!
    private let user = AppUser(id: 1, email: "one@example.invalid", displayName: "One", craftsmanErpId: nil, isAdmin: false, isForeman: false)

    private func fixture(_ directory: URL, otherUserTime: Bool = false) throws -> CommissionOfflineStore {
        var snapshot = CommissionOfflineSnapshot()
        let userData = try CommissionOfflineJSON.object(JSONEncoder().encode(user))
        for id in [10, 11] {
            let path = "/api/commissions/\(id)"
            let item: [String: Any] = ["id": id, "local_status": "in_progress", "positions": [], "assigned_user": userData, "is_own": true, "can_edit": true, "is_actionable": true, "title": "Auftrag"]
            snapshot.resources[path] = CommissionOfflineResource(path: path, query: [], data: try CommissionOfflineJSON.data(["item": item]), fetchedAt: Date())
            for suffix in ["time", "materials", "photos"] {
                let key = path + "/" + suffix
                snapshot.resources[key] = CommissionOfflineResource(path: key, query: [], data: try CommissionOfflineJSON.data(["items": []]), fetchedAt: Date())
            }
        }
        if otherUserTime {
            let path = "/api/commissions/11/time"
            let item: [String: Any] = ["id": 90, "user": ["id": 2], "service_date": "2026-11-10", "minutes": 45]
            snapshot.resources[path] = CommissionOfflineResource(path: path, query: [], data: try CommissionOfflineJSON.data(["items": [item]]), fetchedAt: Date())
        }
        let photosPath = "/api/commissions/10/photos"
        let photosQuery = [CommissionOfflineQuery(name: "context", value: "order")]
        let photo: [String: Any] = ["id": 50, "commission_id": 10, "source": "app", "context": "order", "original_filename": "foto.jpg", "mime_type": "image/jpeg", "size_bytes": 5, "caption": "Alt", "content_path": photosPath + "/50/content", "thumbnail_path": photosPath + "/50/thumbnail"]
        let photoResource = CommissionOfflineResource(path: photosPath, query: photosQuery, data: try CommissionOfflineJSON.data(["items": [photo]]), fetchedAt: Date())
        snapshot.resources[photoResource.key] = photoResource
        let infosPath = "/api/commissions/10/infos"
        let messages: [[String: Any]] = ["first", "second"].map { ["id": $0, "process_erp_id": 1, "body": "Nachricht", "direction": "office", "created_at": "2026-11-10T08:00:00Z", "version": 1, "state": "synced", "mail_state": "not_required", "is_unread": true] }
        snapshot.resources[infosPath] = CommissionOfflineResource(path: infosPath, query: [], data: try CommissionOfflineJSON.data(["items": messages]), fetchedAt: Date())
        let day = CommissionOfflineResource(path: "/api/my-time", query: [CommissionOfflineQuery(name: "date", value: "2026-11-10")], data: try CommissionOfflineJSON.data(["date": "2026-11-10", "recorded_minutes": 0, "status": "missing", "items": []]), fetchedAt: Date())
        snapshot.resources[day.key] = day
        let key = SHA256.hash(data: Data("\(baseURL.absoluteString)|1".utf8)).map { String(format: "%02x", $0) }.joined()
        let root = directory.appendingPathComponent(key)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: root.appendingPathComponent("state.json"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineTestURLProtocol.self]
        let store = CommissionOfflineStore(storageDirectory: directory, session: URLSession(configuration: configuration))
        store.setActive(false)
        try store.bind(user: user, baseURL: baseURL, token: "test")
        return store
    }

    private func book(_ store: CommissionOfflineStore, commissionID: Int = 10, minutes: Int = 60) async throws -> TimeEntry {
        let data = try await store.execute(path: "/api/commissions/\(commissionID)/time", method: "POST", body: CommissionOfflineJSON.data(["minutes": minutes, "service_date": "2026-11-10"]), contentType: "application/json", accept: "application/json")
        return try JSONDecoder().decode(ItemResponse<TimeEntry>.self, from: data).item
    }

    @Test func bookingSurvivesReopeningTheStore() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try fixture(directory)
        let entry = try await book(store)
        #expect(entry.minutes == 60)
        #expect(entry.id < 0)
        let reopened = CommissionOfflineStore(storageDirectory: directory)
        reopened.setActive(false)
        try reopened.bind(user: user, baseURL: baseURL, token: "test")
        #expect(reopened.snapshot.operations.count == 1)
        let data = try await reopened.execute(path: "/api/commissions/10/time", method: "GET", body: nil, contentType: nil, accept: "application/json")
        let items = try JSONDecoder().decode(ListResponse<TimeEntry>.self, from: data).items
        #expect(items.count == 1)
        #expect(items.first?.minutes == 60)
        reopened.stop(); store.stop()
    }

    @Test func accountSwitchKeepsPendingChangesSeparate() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try fixture(directory)
        _ = try await book(store)
        let other = AppUser(id: 2, email: "two@example.invalid", displayName: "Two", craftsmanErpId: nil, isAdmin: false, isForeman: false)
        try store.bind(user: other, baseURL: baseURL, token: "two")
        #expect(store.snapshot.operations.isEmpty)
        try store.bind(user: user, baseURL: baseURL, token: "one")
        #expect(store.snapshot.operations.count == 1)
        store.stop()
    }

    @Test func editingAnUnsentBookingPreservesItsDependency() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try fixture(directory)
        let entry = try await book(store)
        _ = try await store.execute(path: "/api/commissions/10/time/\(entry.id)", method: "PATCH", body: CommissionOfflineJSON.data(["minutes": 120, "service_date": "2026-11-10"]), contentType: "application/json", accept: "application/json")
        #expect(store.snapshot.operations.count == 2)
        #expect(store.snapshot.operations.last?.predecessorID == store.snapshot.operations.first?.id)
        let data = try await store.execute(path: "/api/commissions/10/time", method: "GET", body: nil, contentType: nil, accept: "application/json")
        let items = try JSONDecoder().decode(ListResponse<TimeEntry>.self, from: data).items
        #expect(items.count == 1)
        #expect(items.first?.minutes == 120)
        store.stop()
    }

    @Test func discardingOneCommissionKeepsOtherBookings() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try fixture(directory)
        _ = try await book(store)
        _ = try await book(store, commissionID: 11)
        let id = try #require(store.snapshot.operations.first?.id)
        try await store.resolve(operationID: id, keepLocal: false)
        #expect(store.snapshot.operations.count == 1)
        #expect(store.snapshot.operations.first?.commissionID == 11)
        store.stop()
    }

    @Test func multipartPreservesBinaryPhotoBytes() throws {
        let bytes = Data([0, 255, 128, 13, 10, 1, 2])
        var body = Data("--sample\r\nContent-Disposition: form-data; name=\"photo\"; filename=\"foto.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
        body.append(bytes)
        body.append(Data("\r\n--sample--\r\n".utf8))
        let parts = CommissionOfflineJSON.multipart(body, contentType: "multipart/form-data; boundary=sample")
        #expect(parts.count == 1)
        #expect(parts.first?.0 == "photo")
        #expect(parts.first?.1 == bytes)
    }

    @Test func localEditsUpdateTheGlobalDayTotal() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try fixture(directory)
        let entry = try await book(store)
        _ = try await store.execute(path: "/api/commissions/10/time/\(entry.id)", method: "PATCH", body: CommissionOfflineJSON.data(["minutes": 120, "service_date": "2026-11-10"]), contentType: "application/json", accept: "application/json")
        let data = try await store.execute(path: "/api/my-time", method: "GET", queryItems: [URLQueryItem(name: "date", value: "2026-11-10")], body: nil, contentType: nil, accept: "application/json")
        let day = try JSONDecoder().decode(MyTimeDay.self, from: data)
        #expect(day.recordedMinutes == 120)
        #expect(day.items.count == 1)
        store.stop()
    }

    @Test func editingAPhotoUsesItsQueriedCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try fixture(directory)
        let data = try await store.execute(path: "/api/commissions/10/photos/50", method: "PATCH", body: CommissionOfflineJSON.data(["caption": "Neu"]), contentType: "application/json", accept: "application/json")
        let photo = try JSONDecoder().decode(ItemResponse<CommissionPhoto>.self, from: data).item
        #expect(photo.caption == "Neu")
        #expect(photo.id == 50)
        #expect(store.snapshot.operations.count == 1)
        store.stop()
    }

    @Test func emptyQueryUsesTheSamePersistentResourceKey() {
        #expect(CommissionOfflineResource.key("/api/commissions/10") == "/api/commissions/10")
        #expect(CommissionOfflineResource.key("/api/commissions/10", []) == "/api/commissions/10")
    }

    @Test func readingOneMessagePreservesAllMessages() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try fixture(directory)
        _ = try await store.execute(path: "/api/commissions/10/infos/read", method: "POST", body: CommissionOfflineJSON.data(["items": [["id": "first", "version": 1]]]), contentType: "application/json", accept: "application/json")
        let data = try await store.execute(path: "/api/commissions/10/infos", method: "GET", body: nil, contentType: nil, accept: "application/json")
        let messages = try JSONDecoder().decode(ProcessInfoListResponse.self, from: data).items
        #expect(messages.count == 2)
        #expect(messages.first { $0.id == "first" }?.isUnread == false)
        #expect(messages.first { $0.id == "second" }?.isUnread == true)
        store.stop()
    }

    @Test func deletingAnotherUsersTimePreservesMyDayTotal() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try fixture(directory, otherUserTime: true)
        _ = try await store.execute(path: "/api/commissions/11/time/90", method: "DELETE", body: nil, contentType: nil, accept: "application/json")
        let data = try await store.execute(path: "/api/my-time", method: "GET", queryItems: [URLQueryItem(name: "date", value: "2026-11-10")], body: nil, contentType: nil, accept: "application/json")
        #expect(try JSONDecoder().decode(MyTimeDay.self, from: data).recordedMinutes == 0)
        store.stop()
    }
}

private final class OfflineTestURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let missing = url.path.contains("/offline-operations/")
        let response = HTTPURLResponse(url: url, statusCode: missing ? 404 : 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((missing ? "{\"message\":\"Nicht bestätigt\"}" : "{\"items\":[]}").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

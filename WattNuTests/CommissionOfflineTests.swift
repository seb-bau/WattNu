import CryptoKit
import Foundation
import Testing
@testable import WattNu

@MainActor
struct CommissionOfflineTests {
    private let baseURL = URL(string: "https://example.invalid")!
    private let user = AppUser(id: 1, email: "one@example.invalid", displayName: "One", craftsmanErpId: nil, isAdmin: false, isForeman: false)

    private func fixture(_ directory: URL, otherUserTime: Bool = false, acknowledge: Bool = false, status: String = "in_progress", allowOnCompleted: Bool? = nil, profile: String? = nil) throws -> CommissionOfflineStore {
        var snapshot = CommissionOfflineSnapshot()
        let userData = try CommissionOfflineJSON.object(JSONEncoder().encode(user))
        for id in [10, 11] {
            let path = "/api/commissions/\(id)"
            let item: [String: Any] = ["id": id, "local_status": status, "positions": [], "assigned_user": userData, "is_own": true, "can_edit": true, "is_actionable": true, "title": "Auftrag"]
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
        if let allowOnCompleted {
            let path = "/api/mobile/config"
            snapshot.resources[path] = CommissionOfflineResource(path: path, query: [], data: try CommissionOfflineJSON.data(["password_login_enabled": true, "allow_time_on_completed_commissions": allowOnCompleted]), fetchedAt: Date())
        }
        let photosPath = "/api/commissions/10/photos"
        let photosQuery = [CommissionOfflineQuery(name: "context", value: "order")]
        let photo: [String: Any] = ["id": 50, "commission_id": 10, "source": "app", "context": "order", "original_filename": "foto.jpg", "mime_type": "image/jpeg", "size_bytes": 5, "caption": "Alt", "content_path": photosPath + "/50/content", "thumbnail_path": photosPath + "/50/thumbnail"]
        let photoResource = CommissionOfflineResource(path: photosPath, query: photosQuery, data: try CommissionOfflineJSON.data(["items": [photo]]), fetchedAt: Date())
        snapshot.resources[photoResource.key] = photoResource
        let infosPath = "/api/commissions/10/infos"
        let messages: [[String: Any]] = ["first", "second"].map { ["id": $0, "process_erp_id": 1, "body": "Nachricht", "direction": "office", "created_at": "2026-11-10T08:00:00Z", "version": 1, "state": "synced", "mail_state": "not_required", "is_unread": true] }
        snapshot.resources[infosPath] = CommissionOfflineResource(path: infosPath, query: [], data: try CommissionOfflineJSON.data(["items": messages]), fetchedAt: Date())
        let windowsPath = "/api/appointment-windows"
        snapshot.resources[windowsPath] = CommissionOfflineResource(path: windowsPath, query: [], data: try CommissionOfflineJSON.data(["items": [["id": 1, "name": "Vormittag", "start_time": "08:00", "end_time": "12:00"]], "custom_time_duration_minutes": 60]), fetchedAt: Date())
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
        try store.bind(user: user, baseURL: baseURL, token: profile ?? (acknowledge ? "acknowledge" : "test"))
        return store
    }

    private func book(_ store: CommissionOfflineStore, commissionID: Int = 10, minutes: Int = 60, serviceDate: String = "2026-11-10") async throws -> TimeEntry {
        let data = try await store.execute(path: "/api/commissions/\(commissionID)/time", method: "POST", body: CommissionOfflineJSON.data(["minutes": minutes, "service_date": serviceDate]), contentType: "application/json", accept: "application/json")
        return try JSONDecoder().decode(ItemResponse<TimeEntry>.self, from: data).item
    }

    private func queueStart(_ store: CommissionOfflineStore) async throws {
        _ = try await store.execute(path: "/api/commissions/10/start", method: "POST", body: Data("{}".utf8), contentType: "application/json", accept: "application/json")
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }

    @Test func offlineOrderKeepsItsCreatorAfterRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try fixture(directory)
        defer { store.stop() }
        let data = try await store.execute(
            path: "/api/commissions/simple", method: "POST", body: CommissionOfflineJSON.data(["title": "Reparatur"]),
            contentType: "application/json", accept: "application/json"
        )
        let order = try JSONDecoder().decode(ItemResponse<Commission>.self, from: data).item
        #expect(order.createdByName == user.displayName)
        store.stop()

        let reopened = CommissionOfflineStore(storageDirectory: directory)
        reopened.setActive(false)
        try reopened.bind(user: user, baseURL: baseURL, token: "test")
        defer { reopened.stop() }
        let saved = try await reopened.execute(
            path: "/api/commissions/\(order.id)", method: "GET", body: nil, contentType: nil, accept: "application/json"
        )
        let savedOrder = try JSONDecoder().decode(ItemResponse<Commission>.self, from: saved).item
        #expect(savedOrder.creatorDisplayName == user.displayName)
    }

    @Test func completedCommissionsRejectNewOfflineBookingsAndKeepExistingEntries() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try fixture(directory, otherUserTime: true, status: "done", allowOnCompleted: false)
        defer { store.stop() }
        do {
            _ = try await book(store, commissionID: 11)
            Issue.record("Die deaktivierte nachträgliche Zeiterfassung muss auch offline gelten.")
        } catch {
            #expect(error.localizedDescription.contains("keine neuen Zeiten"))
        }
        #expect(store.snapshot.operations.isEmpty)
        let data = try await store.execute(path: "/api/commissions/11/time", method: "GET", body: nil, contentType: nil, accept: "application/json")
        let items = try CommissionOfflineJSON.object(data)["items"] as? [[String: Any]]
        #expect(items?.count == 1)
        #expect(items?.first?["minutes"] as? Int == 45)
        #expect(store.handles(path: "/api/mobile/config", method: "GET"))
    }

    @Test func completedCommissionsAllowOfflineBookingsWhenEnabled() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try fixture(directory, status: "done", allowOnCompleted: true)
        defer { store.stop() }
        let item = try await book(store)
        #expect(item.minutes == 60)
        #expect(store.snapshot.operations.count == 1)
    }

    @Test func offlineCompletionUsesTheConfiguredTimeRecordingPolicy() async throws {
        for allowed in [false, true] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = try fixture(directory, allowOnCompleted: allowed)
            defer { store.stop() }
            let data = try await store.execute(path: "/api/commissions/10/complete", method: "POST", body: CommissionOfflineJSON.data(["completed": true]), contentType: "application/json", accept: "application/json")
            let item = try JSONDecoder().decode(ItemResponse<Commission>.self, from: data).item
            #expect(item.localStatus == "done")
            #expect(item.canEditValue)
            #expect(item.allowsNewTimeEntries(allowOnCompleted: allowed) == allowed)
            if allowed {
                _ = try await book(store)
                #expect(store.snapshot.operations.count == 2)
            } else {
                do {
                    _ = try await book(store)
                    Issue.record("Nach dem Offline-Abschluss darf keine neue Zeitbuchung angelegt werden.")
                } catch {
                    #expect(error.localizedDescription.contains("keine neuen Zeiten"))
                }
                #expect(store.snapshot.operations.count == 1)
            }
        }
    }

    @Test func disabledLateRecordingRemainsAvailableAfterReopeningTheOfflineStore() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try fixture(directory, status: "done", allowOnCompleted: false)
        first.stop()
        let reopened = CommissionOfflineStore(storageDirectory: directory)
        reopened.setActive(false)
        try reopened.bind(user: user, baseURL: baseURL, token: "test")
        defer { reopened.stop() }
        do {
            _ = try await book(reopened)
            Issue.record("Die gespeicherte Einstellung muss nach einem Neustart weiterhin gelten.")
        } catch {
            #expect(error.localizedDescription.contains("keine neuen Zeiten"))
        }
        #expect(reopened.snapshot.operations.isEmpty)
    }

    @Test func commissionBookingPreservesASelectedPastServiceDateAcrossRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try fixture(directory)
        let entry = try await book(store, serviceDate: "2025-01-15")
        #expect(entry.serviceDate == "2025-01-15")
        let reopened = CommissionOfflineStore(storageDirectory: directory)
        reopened.setActive(false)
        try reopened.bind(user: user, baseURL: baseURL, token: "test")
        let operation = try #require(reopened.snapshot.operations.first)
        let body = try CommissionOfflineJSON.object(operation.body)
        #expect(body["service_date"] as? String == "2025-01-15")
        reopened.stop(); store.stop()
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

    @Test func discardingStatusKeepsAnotherChangeForTheSameOrder() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try fixture(directory, status: "waiting_for_acceptance")
        defer { store.stop() }
        try await queueStart(store)
        _ = try await book(store)
        let statusID = try #require(store.snapshot.operations.first?.id)
        let bookingID = try #require(store.snapshot.operations.last?.id)
        #expect(store.snapshot.operations.last?.predecessorID == nil)
        try await store.resolve(operationID: statusID, keepLocal: false)
        #expect(store.snapshot.operations.map(\.id) == [bookingID])
    }

    @Test func discardingAnUnsentBookingPreservesItsEditForReview() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try fixture(directory)
        defer { store.stop() }
        let booking = try await book(store)
        _ = try await store.execute(path: "/api/commissions/10/time/\(booking.id)", method: "PATCH", body: CommissionOfflineJSON.data(["minutes": 31]), contentType: "application/json", accept: "application/json")
        let originalID = try #require(store.snapshot.operations.first?.id)
        try await store.resolve(operationID: originalID, keepLocal: false)
        let pending = try #require(store.snapshot.operations.first)
        #expect(store.snapshot.operations.count == 1)
        #expect(pending.blocked)
        #expect(pending.errorCode == "local_dependency_discarded")
        #expect(try CommissionOfflineJSON.object(pending.body)["minutes"] as? Int == 31)
    }

    @Test func pausedStatusDoesNotHoldADifferentOrder() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try fixture(directory, status: "waiting_for_acceptance", profile: "parallel")
        defer { store.stop() }
        try await queueStart(store)
        _ = try await book(store, commissionID: 11)
        store.setActive(true)
        try await waitUntil { store.snapshot.operations.count == 1 }
        #expect(store.snapshot.operations.first?.commissionID == 10)
        #expect(store.sendingGroups.contains(10))
    }

    @Test func blockedStatusDoesNotHoldAnIndependentBookingForTheSameOrder() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try fixture(directory, status: "waiting_for_acceptance", profile: "blocked-status")
        defer { store.stop() }
        try await queueStart(store)
        _ = try await book(store)
        store.setActive(true)
        try await waitUntil { store.snapshot.operations.count == 1 && store.snapshot.operations.first?.blocked == true }
        #expect(store.snapshot.operations.first?.path.hasSuffix("/start") == true)
        #expect(store.snapshot.operations.first?.errorCode == "conflict")
    }

    @Test func deletedOrderRetainsItsLocalChangesWhileOtherOrdersSync() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try fixture(directory, status: "waiting_for_acceptance", profile: "deleted-order")
        defer { store.stop() }
        try await queueStart(store)
        _ = try await book(store)
        _ = try await book(store, commissionID: 11)
        store.setActive(true)
        try await waitUntil { store.snapshot.operations.count == 2 && store.snapshot.operations.allSatisfy(\.blocked) }
        #expect(store.snapshot.operations.allSatisfy { $0.commissionID == 10 && $0.errorCode == "commission_unavailable" })
        #expect(store.snapshot.unavailableCommissionIDs == [10])
    }

    @Test func identicalBookingIsOnlyResentAfterConfirmation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try fixture(directory, profile: "duplicate")
        defer { store.stop() }
        _ = try await book(store)
        store.setActive(true)
        try await waitUntil { store.snapshot.operations.first?.errorCode == "duplicate_booking" && store.canResolve(groupID: 10) }
        let pending = try #require(store.snapshot.operations.first)
        try store.retrySynchronization()
        #expect(store.snapshot.operations.first?.blocked == true)
        try await store.resolve(operationID: pending.id, keepLocal: true)
        try await waitUntil { store.snapshot.operations.isEmpty }
    }

    @Test func overlayDoesNotDecodeUnrelatedResources() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try fixture(directory)
        defer { store.stop() }
        _ = try await book(store)
        let unrelated = "/api/commissions/11/history"
        var resources = store.snapshot.resources
        let invalidJSON = Data("abgebrochene Antwort".utf8)
        resources[unrelated] = CommissionOfflineResource(path: unrelated, query: [], data: invalidJSON, fetchedAt: Date())
        let result = try CommissionOfflineJSON.overlay(resources, operations: store.snapshot.operations)
        #expect(result[unrelated]?.data == invalidJSON)
        #expect(result["/api/commissions/10/time"]?.data != resources["/api/commissions/10/time"]?.data)
    }

    @Test func parallelTimeReceiptsAreFollowedByAnAuthoritativeDayRefresh() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try fixture(directory, profile: "shared-time")
        defer { store.stop() }
        _ = try await book(store)
        _ = try await book(store, commissionID: 11)
        store.setActive(true)
        let key = CommissionOfflineResource.key("/api/my-time", [CommissionOfflineQuery(name: "date", value: "2026-11-10")])
        try await waitUntil {
            guard let resource = store.snapshot.resources[key], let day = try? JSONDecoder().decode(MyTimeDay.self, from: resource.data) else { return false }
            return store.snapshot.operations.isEmpty && day.recordedMinutes == 120
        }
        #expect(!store.snapshot.preparation.contains(key))
    }

    @Test func olderQueueRecoversACheckedReceiptBeforeSending() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let initial = try fixture(directory)
        _ = try await book(initial)
        var snapshot = initial.snapshot
        initial.stop()
        snapshot.operations[0].scopedDependencies = nil
        snapshot.queueVersion = nil
        snapshot.deviceID = nil
        let key = SHA256.hash(data: Data("\(baseURL.absoluteString)|1".utf8)).map { String(format: "%02x", $0) }.joined()
        try JSONEncoder().encode(snapshot).write(to: directory.appendingPathComponent(key).appendingPathComponent("state.json"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineTestURLProtocol.self]
        let store = CommissionOfflineStore(storageDirectory: directory, session: URLSession(configuration: configuration))
        defer { store.stop() }
        try store.bind(user: user, baseURL: baseURL, token: "legacy-receipt")
        try await waitUntil { store.snapshot.operations.isEmpty }
        let data = try await store.execute(path: "/api/commissions/10/time", method: "GET", body: nil, contentType: nil, accept: "application/json")
        #expect(try JSONDecoder().decode(ListResponse<TimeEntry>.self, from: data).items.map(\.id) == [200])
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

    @Test func appointmentProposalsRemainVisibleOffline() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try fixture(directory)
        let data = try await store.execute(path: "/api/commissions/10/appointments", method: "POST", body: CommissionOfflineJSON.data(["recipient_email": "tenant@example.invalid", "proposals": [["date": "2026-11-12", "window_id": 1]]]), contentType: "application/json", accept: "application/json")
        let request = try JSONDecoder().decode(ItemResponse<CommissionAppointmentRequest>.self, from: data).item
        #expect(request.proposals.count == 1)
        #expect(request.proposals.first?.proposedDate == "2026-11-12")
        #expect(request.proposals.first?.startTime == "08:00")
        #expect(request.proposals.first?.endTime == "12:00")
        #expect(request.createdBy?.id == user.id)
        store.stop()
    }

    @Test func confirmedBookingReplacesItsLocalIDWithoutDoubleCounting() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try fixture(directory, acknowledge: true)
        let entry = try await book(store)
        #expect(entry.id < 0)
        store.setActive(true)
        for _ in 0..<300 {
            if store.snapshot.operations.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        store.setActive(false)
        #expect(store.snapshot.operations.isEmpty)
        let list = try await store.execute(path: "/api/commissions/10/time", method: "GET", body: nil, contentType: nil, accept: "application/json")
        let items = try JSONDecoder().decode(ListResponse<TimeEntry>.self, from: list).items
        #expect(items.count == 1)
        #expect(items.first?.id == 200)
        let data = try await store.execute(path: "/api/my-time", method: "GET", queryItems: [URLQueryItem(name: "date", value: "2026-11-10")], body: nil, contentType: nil, accept: "application/json")
        let day = try JSONDecoder().decode(MyTimeDay.self, from: data)
        #expect(day.recordedMinutes == 60)
        #expect(day.items.count == 1)
        store.stop()
    }
}

private final class OfflineTestURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let missing = url.path.contains("/offline-operations/")
        var status = missing ? 404 : 200
        var data = Data((missing ? "{\"message\":\"Nicht bestätigt\"}" : "{\"items\":[]}").utf8)
        let profile = request.value(forHTTPHeaderField: "Authorization") ?? ""
        if missing, profile == "Bearer legacy-receipt" {
            status = 200
            data = (try? JSONSerialization.data(withJSONObject: ["id": url.lastPathComponent, "payload": ["item": timeItem(commissionID: 10)]])) ?? data
        }
        if url.path == "/api/my-time" {
            let minutes = profile == "Bearer shared-time" ? 120 : 60
            let commission: [String: Any] = ["id": 10, "number": "10", "title": "Auftrag"]
            let item: [String: Any] = ["id": 200, "minutes": 60, "service_date": "2026-11-10", "is_free_time": false, "commission": commission]
            let day: [String: Any] = ["date": "2026-11-10", "recorded_minutes": minutes, "status": "complete", "items": [item]]
            data = (try? JSONSerialization.data(withJSONObject: day)) ?? data
        }
        if url.path == "/api/mobile/offline-operations", profile != "Bearer test" {
            var body = request.httpBody ?? Data()
            if let stream = request.httpBodyStream, body.isEmpty {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 8192)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    body.append(contentsOf: buffer.prefix(count))
                }
            }
            if let operation = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let id = operation["id"] as? String, let path = operation["path"] as? String {
                if profile == "Bearer parallel", path.hasSuffix("/10/start") { return }
                if profile == "Bearer legacy-receipt" {
                    status = 409
                    data = Data("{\"code\":\"operation_reused\",\"message\":\"Vorgang wurde schon bestätigt.\"}".utf8)
                } else if profile == "Bearer blocked-status", path.hasSuffix("/10/start") {
                    status = 409
                    data = Data("{\"code\":\"conflict\",\"message\":\"Der Serverstand wurde geändert.\"}".utf8)
                } else if profile == "Bearer deleted-order", path.hasSuffix("/10/start") {
                    status = 404
                    data = Data("{\"code\":\"commission_unavailable\",\"message\":\"Der Auftrag ist nicht mehr verfügbar.\"}".utf8)
                } else if profile == "Bearer duplicate", operation["confirm_duplicate"] as? Bool != true {
                    status = 409
                    data = Data("{\"code\":\"duplicate_booking\",\"message\":\"Buchung bereits vorhanden.\"}".utf8)
                } else {
                    let commissionID = path.hasSuffix("/11/time") ? 11 : 10
                    let item = timeItem(commissionID: commissionID)
                    let day: [String: Any] = ["date": "2026-11-10", "recorded_minutes": 60, "status": "complete", "items": [["id": 200, "minutes": 60, "service_date": "2026-11-10", "is_free_time": false, "commission": ["id": commissionID, "number": "\(commissionID)", "title": "Auftrag"]]]]
                    data = (try? JSONSerialization.data(withJSONObject: ["id": id, "payload": ["item": item], "my_time": ["2026-11-10": day], "references": [:]])) ?? data
                }
            }
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    private func timeItem(commissionID: Int) -> [String: Any] {
        ["id": 200, "commission_id": commissionID, "user": ["id": 1, "email": "one@example.invalid", "display_name": "One", "is_admin": false, "is_foreman": false], "minutes": 60, "service_date": "2026-11-10", "deviation_minutes": 0, "deviation_percent": 0, "review_status": "ok"]
    }

    override func stopLoading() {}
}

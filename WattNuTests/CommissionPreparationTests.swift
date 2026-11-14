import CryptoKit
import Foundation
import Testing
@testable import WattNu

@MainActor
struct CommissionPreparationTests {
    private let baseURL = URL(string: "https://preparation.example.invalid")!
    private let user = AppUser(id: 1, email: "one@example.invalid", displayName: "One", craftsmanErpId: nil, isAdmin: false, isForeman: false)

    private func fixture(dates: [String], cached: Bool = false, queued: Bool = true, oldErrors: Bool = false, infos: [[String: Any]]? = nil, resources: [CommissionOfflineResource] = []) throws -> PreparationFixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var snapshot = CommissionOfflineSnapshot()
        let userData = try CommissionOfflineJSON.object(JSONEncoder().encode(user))
        let parent = "/api/commissions/10"
        snapshot.resources[parent] = CommissionOfflineResource(path: parent, query: [], data: try CommissionOfflineJSON.data(["item": ["id": 10, "local_status": "in_progress", "assigned_user": userData, "can_edit": true, "is_actionable": true, "positions": []]]), fetchedAt: Date())
        if let infos {
            let path = parent + "/infos"
            snapshot.resources[path] = CommissionOfflineResource(path: path, query: [], data: try CommissionOfflineJSON.data(["items": infos]), fetchedAt: Date())
        }
        for resource in resources { snapshot.resources[resource.key] = resource }
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

    private func apiClient(_ fixture: PreparationFixture) -> APIClient {
        let client = APIClient(baseURL: baseURL, session: fixture.session)
        client.accessToken = fixture.token
        client.commissionStore = fixture.store
        return client
    }

    private func processInfo(_ id: String, body: String, isUnread: Bool) -> [String: Any] {
        ["id": id, "process_erp_id": 1, "body": body, "author_name": "One", "direction": "office", "created_at": "2026-11-12T08:00:00Z", "version": 1, "state": "synced", "mail_state": "not_required", "is_unread": isUnread]
    }

    private func processInfoResponse(_ items: [[String: Any]]) throws -> Data {
        try CommissionOfflineJSON.data(["items": [["path": "/api/commissions/10/infos", "query": [], "status": 200, "payload": ["items": items]]]])
    }

    private func resourceResponse(path: String, query: [CommissionOfflineQuery] = [], payload: [String: Any]) throws -> Data {
        try CommissionOfflineJSON.data(["items": [["path": path, "query": query.map { ["name": $0.name, "value": $0.value] }, "status": 200, "payload": payload]]])
    }

    private func photo(_ id: Int, context: String) -> [String: Any] {
        ["id": id, "commission_id": 10, "source": "erp", "context": context, "external_entity_name": "Building", "original_filename": "foto.jpg", "mime_type": "image/jpeg", "size_bytes": 5, "content_path": "/api/commissions/10/photos/\(id)/content", "thumbnail_path": "/api/commissions/10/photos/\(id)/thumbnail"]
    }

    @Test(arguments: ["object", "order"])
    func photoRefreshLoadsNewPhotosEvenWhenCacheIsFresh(context: String) async throws {
        let path = "/api/commissions/10/photos"
        let query = [CommissionOfflineQuery(name: "context", value: context)]
        let resource = CommissionOfflineResource(path: path, query: query, data: try CommissionOfflineJSON.data(["items": []]), fetchedAt: Date())
        let fixture = try fixture(dates: [], resources: [resource])
        defer { fixture.close() }
        let client = apiClient(fixture)
        let cached = try await client.fetchCommissionPhotos(commissionId: 10, context: context)
        #expect(cached.isEmpty)
        fixture.scenario.setReplies([.response(200, try resourceResponse(path: path, query: query, payload: ["items": [photo(50, context: context)]]))], for: "/api/mobile/offline-data")

        let refreshed = try await client.fetchCommissionPhotos(commissionId: 10, context: context, refresh: true)

        #expect(refreshed.map(\.id) == [50])
        #expect(refreshed.first?.context == context)
        let stored = try await client.fetchCommissionPhotos(commissionId: 10, context: context)
        #expect(stored.map(\.id) == [50])
        #expect(fixture.scenario.count("/api/mobile/offline-data") == 1)

        fixture.scenario.setReplies([.response(200, try resourceResponse(path: path, query: query, payload: ["items": []]))], for: "/api/mobile/offline-data")
        let removed = try await client.fetchCommissionPhotos(commissionId: 10, context: context, refresh: true)
        #expect(removed.isEmpty)
        #expect(fixture.scenario.count("/api/mobile/offline-data") == 2)
    }

    @Test(arguments: ["object", "order"])
    func photoRefreshUsesFilteredOfflineFallbackFromSharedCache(context: String) async throws {
        let path = "/api/commissions/10/photos"
        let items = [photo(50, context: "object"), photo(51, context: "order")]
        let resource = CommissionOfflineResource(path: path, query: [], data: try CommissionOfflineJSON.data(["items": items]), fetchedAt: Date())
        let fixture = try fixture(dates: [], resources: [resource])
        defer { fixture.close() }
        let client = apiClient(fixture)
        fixture.scenario.setReplies([.failure(.notConnectedToInternet)], for: "/api/mobile/offline-data")

        let refreshed = try await client.fetchCommissionPhotos(commissionId: 10, context: context, entity: "building", refresh: true)

        #expect(refreshed.map(\.id) == [context == "object" ? 50 : 51])
        #expect(refreshed.first?.context == context)
        #expect(fixture.scenario.count("/api/mobile/offline-data") == 1)
    }

    @Test func photoRefreshPreservesPendingUploads() async throws {
        let path = "/api/commissions/10/photos"
        let query = [CommissionOfflineQuery(name: "context", value: "order")]
        let resource = CommissionOfflineResource(path: path, query: query, data: try CommissionOfflineJSON.data(["items": []]), fetchedAt: Date())
        let fixture = try fixture(dates: [], resources: [resource])
        defer { fixture.close() }
        let client = apiClient(fixture)
        let pending = try await client.uploadCommissionPhoto(commissionId: 10, imageData: Data("image".utf8), caption: "Offline erfasst")
        fixture.scenario.setReplies([.response(200, try resourceResponse(path: path, query: query, payload: ["items": [photo(50, context: "order")]]))], for: "/api/mobile/offline-data")

        let refreshed = try await client.fetchCommissionPhotos(commissionId: 10, context: "order", refresh: true)

        #expect(Set(refreshed.map(\.id)) == Set([50, pending.item.id]))
        #expect(fixture.store.snapshot.operations.count == 1)
    }

    @Test func commissionRefreshUpdatesFreshlyCachedDetails() async throws {
        let fixture = try fixture(dates: [])
        defer { fixture.close() }
        let client = apiClient(fixture)
        let path = "/api/commissions/10"
        let cached = try await client.fetchCommission(id: 10)
        let resource = try #require(fixture.store.snapshot.resources[path])
        var payload = try CommissionOfflineJSON.object(resource.data)
        var item = try #require(payload["item"] as? [String: Any])
        item["title"] = "Aktueller Auftrag"
        payload["item"] = item
        fixture.scenario.setReplies([.response(200, try resourceResponse(path: path, payload: payload))], for: "/api/mobile/offline-data")

        let refreshed = try await client.fetchCommission(id: 10, refresh: true)

        #expect(cached.title != refreshed.title)
        #expect(refreshed.title == "Aktueller Auftrag")
    }

    private func sectionIDs(client: APIClient, section: String, refresh: Bool) async throws -> [Int] {
        switch section {
        case "materials": return try await client.fetchMaterials(commissionId: 10, refresh: refresh).map(\.id)
        case "time": return try await client.fetchTimeEntries(commissionId: 10, refresh: refresh).map(\.id)
        case "history": return try await client.fetchCommissionHistory(commissionId: 10, refresh: refresh).map(\.id)
        case "contacts": return try await client.fetchCommissionContacts(commissionId: 10, refresh: refresh).compactMap(\.personId)
        case "appointments": return try await client.fetchCommissionAppointments(commissionId: 10, refresh: refresh).map(\.id)
        default: return try await client.fetchCommissionAttachments(commissionId: 10, refresh: refresh).map(\.id)
        }
    }

    @Test(arguments: ["materials", "time", "history", "contacts", "appointments", "attachments"])
    func sectionRefreshLoadsNewEntriesFromFreshCache(section: String) async throws {
        let path = "/api/commissions/10/" + section
        let field = section == "contacts" ? "contact_items" : "items"
        let resource = CommissionOfflineResource(path: path, query: [], data: try CommissionOfflineJSON.data([field: []]), fetchedAt: Date())
        let fixture = try fixture(dates: [], resources: [resource])
        defer { fixture.close() }
        let client = apiClient(fixture)
        let cached = try await sectionIDs(client: client, section: section, refresh: false)
        #expect(cached.isEmpty)
        var item: [String: Any] = ["id": 50, "commission_id": 10]
        switch section {
        case "materials":
            item["item"] = ["id": 1, "item_number": "1", "name": "Material", "unit": "Stück", "qr_code_payload": "1", "stock_quantity": 10, "reorder_level": 0]
            item["movement_type"] = "withdrawal"
            item["quantity"] = 2
        case "time":
            item["user"] = try CommissionOfflineJSON.object(JSONEncoder().encode(user))
            item["minutes"] = 60
            item["deviation_minutes"] = 0
            item["deviation_percent"] = 0
            item["review_status"] = "ok"
        case "history":
            item["action"] = "commission.update"
            item["title"] = "Auftrag aktualisiert"
            item["actor_name"] = "One"
        case "contacts":
            item["person_id"] = 50
            item["name"] = "Bewohner"
            item["additional_numbers"] = [String]()
        case "appointments":
            item["recipient_email"] = "tenant@example.invalid"
            item["status"] = "pending"
            item["proposals"] = [[String: Any]]()
        default:
            item["source_entity_name"] = "Commission"
            item["original_filename"] = "dokument.pdf"
            item["mime_type"] = "application/pdf"
            item["size_bytes"] = 5
            item["is_image"] = false
            item["content_path"] = path + "/50/content"
        }
        fixture.scenario.setReplies([.response(200, try resourceResponse(path: path, payload: [field: [item]]))], for: "/api/mobile/offline-data")

        let refreshed = try await sectionIDs(client: client, section: section, refresh: true)

        #expect(refreshed == [50])
        let stored = try await sectionIDs(client: client, section: section, refresh: false)
        #expect(stored == [50])
        #expect(fixture.scenario.count("/api/mobile/offline-data") == 1)
    }

    @Test func emptyCommissionCacheCanBeReadRepeatedlyWithoutNetworkOrRevisionChanges() throws {
        let path = "/api/commissions"
        let query = [CommissionOfflineQuery(name: "scope", value: "mine"), CommissionOfflineQuery(name: "status", value: "active")]
        let resource = CommissionOfflineResource(path: path, query: query, data: try CommissionOfflineJSON.data(["items": []]), fetchedAt: .distantPast)
        let fixture = try fixture(dates: [], resources: [resource])
        defer { fixture.close() }
        let revision = fixture.store.revision

        for _ in 0..<30 {
            let cached = try fixture.store.cachedCommissions(scope: .mine, status: .active, userId: nil)
            #expect(cached != nil)
            #expect(cached?.isEmpty == true)
        }

        #expect(fixture.store.revision == revision)
        #expect(fixture.scenario.count("/api/mobile/offline-data") == 0)
    }

    @Test func cachedCommissionListIncludesQueuedOrdersWithTheirCreationDate() async throws {
        let resource = CommissionOfflineResource(path: "/api/commissions", query: [CommissionOfflineQuery(name: "scope", value: "mine")], data: try CommissionOfflineJSON.data(["items": []]), fetchedAt: Date())
        let fixture = try fixture(dates: [], resources: [resource])
        defer { fixture.close() }
        let data = try await fixture.store.execute(path: "/api/commissions/simple", method: "POST", body: CommissionOfflineJSON.data(["title": "Neuer Auftrag", "commission_text": "Beschreibung"]), contentType: "application/json", accept: "application/json")
        let created = try JSONDecoder().decode(ItemResponse<Commission>.self, from: data).item
        let cached = try fixture.store.cachedCommissions(scope: .mine, status: .all, userId: nil)
        #expect(cached?.map(\.id) == [created.id])
        #expect(cached?.first?.recordingDate != nil)
        #expect(fixture.store.snapshot.operations.count == 1)
    }

    @Test func processInfoRefreshFindsOwnBackendMessageInFreshEmptyCache() async throws {
        let fixture = try fixture(dates: [], infos: [])
        defer { fixture.close() }
        let client = apiClient(fixture)
        let cached = try await client.fetchProcessInfos(commissionId: 10)
        #expect(cached.items.isEmpty)
        #expect(fixture.scenario.count("/api/mobile/offline-data") == 0)
        let message = processInfo("backend", body: "Im Backend ergänzt", isUnread: false)
        fixture.scenario.setReplies([.response(200, try processInfoResponse([message]))], for: "/api/mobile/offline-data")

        let refreshed = try await client.fetchProcessInfos(commissionId: 10, refresh: true)

        #expect(refreshed.items.map(\.id) == ["backend"])
        #expect(refreshed.items.first?.body == "Im Backend ergänzt")
        #expect(refreshed.items.first?.isUnread == false)
        let stored = try await client.fetchProcessInfos(commissionId: 10)
        #expect(stored.items.map(\.id) == ["backend"])
        #expect(fixture.scenario.count("/api/mobile/offline-data") == 1)

        var edited = message
        edited["body"] = "Im Backend geändert"
        edited["version"] = 2
        fixture.scenario.setReplies([.response(200, try processInfoResponse([edited]))], for: "/api/mobile/offline-data")
        let updated = try await client.fetchProcessInfos(commissionId: 10, refresh: true)
        #expect(updated.items.first?.body == "Im Backend geändert")
        #expect(updated.items.first?.version == 2)
        #expect(fixture.scenario.count("/api/mobile/offline-data") == 2)
    }

    @Test func processInfoRefreshPreservesPendingMessagesAndReadReceipts() async throws {
        let message = processInfo("office", body: "Vorhandene Information", isUnread: true)
        let fixture = try fixture(dates: [], infos: [message])
        defer { fixture.close() }
        let client = apiClient(fixture)
        let pending = try await client.createProcessInfo(commissionId: 10, requestId: UUID().uuidString, body: "Noch nicht übertragen")
        _ = try await client.markProcessInfosRead(commissionId: 10, items: [ProcessInfoVisibleItem(id: "office", version: 1)])
        let added = processInfo("backend", body: "Neue Information", isUnread: false)
        fixture.scenario.setReplies([.response(200, try processInfoResponse([message, added]))], for: "/api/mobile/offline-data")

        let refreshed = try await client.fetchProcessInfos(commissionId: 10, refresh: true)

        #expect(Set(refreshed.items.map(\.id)) == Set(["office", "backend", pending.id]))
        #expect(refreshed.items.first(where: { $0.id == "office" })?.isUnread == false)
        #expect(refreshed.items.first(where: { $0.id == pending.id })?.body == "Noch nicht übertragen")
        #expect(fixture.store.snapshot.operations.count == 2)
    }

    @Test func processInfoRefreshFallsBackToCacheAndPendingMessagesOffline() async throws {
        let message = processInfo("office", body: "Offline verfügbar", isUnread: false)
        let fixture = try fixture(dates: [], infos: [message])
        defer { fixture.close() }
        let client = apiClient(fixture)
        let pending = try await client.createProcessInfo(commissionId: 10, requestId: UUID().uuidString, body: "Offline erfasst")
        fixture.scenario.setReplies([.failure(.notConnectedToInternet)], for: "/api/mobile/offline-data")

        let refreshed = try await client.fetchProcessInfos(commissionId: 10, refresh: true)

        #expect(Set(refreshed.items.map(\.id)) == Set(["office", pending.id]))
        #expect(refreshed.items.first(where: { $0.id == "office" })?.body == "Offline verfügbar")
        #expect(refreshed.items.first(where: { $0.id == pending.id })?.body == "Offline erfasst")
        #expect(fixture.store.snapshot.operations.count == 1)
        #expect(fixture.scenario.count("/api/mobile/offline-data") == 1)
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

    private func scopedCommission(_ fields: [String: Any] = [:]) throws -> Commission {
        var payload: [String: Any] = ["id": 10, "local_status": "in_progress", "positions": []]
        payload.merge(fields) { _, value in value }
        return try JSONDecoder().decode(Commission.self, from: JSONSerialization.data(withJSONObject: payload))
    }

    @Test func economicUnitOrdersShowTheWholeScopeAboveTheirReferenceAddress() throws {
        let commission = try scopedCommission([
            "object_type": "economic_unit", "economic_unit_idnum": "123", "economic_unit_name": "Parkstraße",
            "apartment_address": "Parkstraße 1",
        ])
        #expect(commission.isEconomicUnitOrder)
        #expect(commission.objectDisplayTitle == "Gesamte Wirtschaftseinheit")
        #expect(commission.economicUnitDisplayName == "123 · Parkstraße")
        #expect(commission.addressLabel == "Orientierungsadresse")
        #expect(commission.apartmentAddress == "Parkstraße 1")
    }

    @Test func economicUnitScopeSurvivesTheCodableOfflineRoundTrip() throws {
        let commission = try scopedCommission([
            "object_type": "economic_unit", "economic_unit_idnum": "123", "economic_unit_name": "Parkstraße",
            "apartment_address": "Parkstraße 1",
        ])
        let restored = try JSONDecoder().decode(Commission.self, from: JSONEncoder().encode(commission))
        #expect(restored.isEconomicUnitOrder)
        #expect(restored.economicUnitDisplayName == commission.economicUnitDisplayName)
        #expect(restored.apartmentAddress == commission.apartmentAddress)
    }

    @Test func buildingOrdersWithEconomicUnitMetadataKeepTheirAddressHeading() throws {
        let commission = try scopedCommission([
            "object_type": "building", "economic_unit_idnum": "123", "economic_unit_name": "Parkstraße",
            "apartment_address": "Parkstraße 1",
        ])
        #expect(!commission.isEconomicUnitOrder)
        #expect(commission.objectDisplayTitle == "Parkstraße 1")
        #expect(commission.addressLabel == "Adresse")
    }

    @Test func responsesWithoutScopeMetadataRemainReadable() throws {
        let commission = try scopedCommission(["apartment_address": "Parkstraße 1"])
        #expect(!commission.isEconomicUnitOrder)
        #expect(commission.objectDisplayTitle == "Parkstraße 1")
        #expect(commission.economicUnitDisplayName == nil)
        #expect(commission.addressLabel == "Adresse")
    }

    @Test func economicUnitOrdersRemainIdentifiableWithoutANameOrNumber() throws {
        let commission = try scopedCommission(["object_type": "economic_unit", "apartment_address": "Parkstraße 1"])
        #expect(commission.isEconomicUnitOrder)
        #expect(commission.objectDisplayTitle == "Gesamte Wirtschaftseinheit")
        #expect(commission.economicUnitDisplayName == nil)
    }

    @Test func olderDayResponseAfterBookingDoesNotOverwriteConfirmationOrReportCancellation() async throws {
        let date = "2026-11-01"
        let key = "/api/my-time?date=" + date
        let fixture = try fixture(dates: [date], cached: true, queued: false)
        defer { fixture.close() }
        fixture.scenario.hold(key)
        let store = fixture.store
        store.setActive(true)
        _ = try await store.execute(path: "/api/my-time", method: "GET", queryItems: [URLQueryItem(name: "date", value: date)], body: nil, contentType: nil, accept: "application/json")
        try await waitUntil { fixture.scenario.hasHeldResponse(key) }
        store.setActive(false)
        _ = try await store.execute(path: "/api/commissions/10/time", method: "POST", body: CommissionOfflineJSON.data(["minutes": 60, "service_date": date]), contentType: "application/json", accept: "application/json")
        let operation = try #require(store.snapshot.operations.first)
        let userData = try CommissionOfflineJSON.object(JSONEncoder().encode(user))
        let item: [String: Any] = ["id": 200, "commission_id": 10, "user": userData, "minutes": 60, "service_date": date, "deviation_minutes": 0, "deviation_percent": 0, "review_status": "ok"]
        let day: [String: Any] = ["date": date, "recorded_minutes": 60, "status": "complete", "items": [["id": 200, "minutes": 60, "service_date": date, "is_free_time": false]]]
        let receipt = try CommissionOfflineJSON.data(["id": operation.id, "payload": ["item": item], "my_time": [date: day], "references": [:]])
        fixture.scenario.setReplies([.response(200, receipt)], for: "/api/mobile/offline-operations")
        store.setActive(true)
        try await waitUntil { store.snapshot.operations.isEmpty }
        fixture.scenario.release(key)
        try await Task.sleep(for: .milliseconds(100))
        let data = try await store.execute(path: "/api/my-time", method: "GET", queryItems: [URLQueryItem(name: "date", value: date)], body: nil, contentType: nil, accept: "application/json")
        #expect(try JSONDecoder().decode(MyTimeDay.self, from: data).recordedMinutes == 60)
        #expect(store.message.isEmpty)
        #expect(store.preparationMessage.isEmpty)
        #expect(store.snapshot.preparationErrors.isEmpty)
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
    private var heldKeys: Set<String> = []
    private var heldResponses: [String: [(PreparationURLProtocol, PreparationReply)]] = [:]

    static func key(for url: URL) -> String {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return url.path + (components?.percentEncodedQuery.map { "?" + $0 } ?? "")
    }

    func hold(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        heldKeys.insert(key)
    }

    func hasHeldResponse(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !(heldResponses[key] ?? []).isEmpty
    }

    func deferIfHeld(_ reply: PreparationReply, for url: URL, connection: PreparationURLProtocol) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let key = Self.key(for: url)
        guard heldKeys.contains(key) else { return false }
        heldResponses[key, default: []].append((connection, reply))
        return true
    }

    func release(_ key: String) {
        lock.lock()
        let responses = heldResponses.removeValue(forKey: key) ?? []
        heldKeys.remove(key)
        lock.unlock()
        for (connection, reply) in responses { connection.deliver(reply) }
    }

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
        let key = Self.key(for: url)
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
        let reply = scenario.reply(to: url)
        if !scenario.deferIfHeld(reply, for: url, connection: self) { deliver(reply) }
    }

    func deliver(_ reply: PreparationReply) {
        guard let url = request.url else { return }
        switch reply {
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

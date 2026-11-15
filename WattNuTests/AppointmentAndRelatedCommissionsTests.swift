import Foundation
import Testing
@testable import WattNu

@MainActor
struct AppointmentAndRelatedCommissionsTests {
    private func client() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AppointmentFeatureURLProtocol.self]
        let client = APIClient(baseURL: URL(string: "https://example.invalid")!, session: URLSession(configuration: configuration))
        client.accessToken = "test-user"
        return client
    }

    @Test func appointmentPreferenceUsesTheServerAndEncodesTheBoolean() async throws {
        let client = client()
        let initial = try await client.fetchAppointmentPreferences()
        #expect(initial.calendarEmailEnabled)
        let disabled = try await client.updateAppointmentPreferences(enabled: false)
        #expect(!disabled.calendarEmailEnabled)
        let enabled = try await client.updateAppointmentPreferences(enabled: true)
        #expect(enabled.calendarEmailEnabled)
    }

    @Test func relatedOrdersDecodeTheirRelationshipAndReadOnlyAccess() async throws {
        let response = try await client().fetchRelatedCommissions(commissionId: 10)
        #expect(response.total == 3)
        #expect(response.items.map(\.relationshipLabel) == ["Derselbe Vertrag", "Dieselbe Wohnung", "Dasselbe Gebäude"])
        #expect(response.items.map(\.id) == [20, 21, 22])
        #expect(response.items.first?.directAccess == false)
        #expect(response.items.first?.commission.canEditValue == false)
    }

    @Test func relatedOrderDetailUsesTheAuthorizedSourceCommission() async throws {
        let commission = try await client().fetchRelatedCommission(commissionId: 10, relatedId: 20)
        #expect(commission.id == 20)
        #expect(commission.canEditValue == false)
    }

    @Test func relatedPaginationSendsTheRequestedPage() async throws {
        let response = try await client().fetchRelatedCommissions(commissionId: 10, page: 2)
        #expect(response.page == 2)
    }

    @Test func appointmentPreferenceRequiresAuthentication() async throws {
        let client = client()
        client.accessToken = nil
        do {
            _ = try await client.fetchAppointmentPreferences()
            Issue.record("Eine Anmeldung muss erforderlich sein.")
        } catch APIError.missingToken {
        }
    }
}

private final class AppointmentFeatureURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        do {
            let payload: [String: Any]
            if url.path == "/api/me/appointment-preferences" {
                if request.httpMethod == "PATCH" {
                    var data = request.httpBody ?? Data()
                    if let stream = request.httpBodyStream {
                        stream.open()
                        defer { stream.close() }
                        var buffer = [UInt8](repeating: 0, count: 1024)
                        while stream.hasBytesAvailable {
                            let count = stream.read(&buffer, maxLength: buffer.count)
                            if count <= 0 { break }
                            data.append(contentsOf: buffer.prefix(count))
                        }
                    }
                    let body = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    guard let enabled = body?["calendar_email_enabled"] as? Bool else { throw URLError(.badServerResponse) }
                    payload = ["preferences": ["calendar_email_enabled": enabled]]
                } else {
                    payload = ["preferences": ["calendar_email_enabled": true]]
                }
            } else if url.path == "/api/commissions/10/related/20" {
                payload = ["item": commission(20)]
            } else if url.path == "/api/commissions/10/related" {
                let page = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "page" }?.value ?? "1"
                let relationships = ["license_agreement", "use_unit", "building"]
                let items: [[String: Any]] = relationships.enumerated().map { index, relationship in
                    ["commission": commission(20 + index), "relationship": relationship, "direct_access": false]
                }
                payload = ["items": items, "total": 3, "page": Int(page) ?? 1, "pages": 2, "counts": ["license_agreement": 1, "use_unit": 1, "building": 1]]
            } else {
                throw URLError(.badURL)
            }
            let data = try JSONSerialization.data(withJSONObject: payload)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    private func commission(_ id: Int) -> [String: Any] {
        ["id": id, "local_status": "in_progress", "title": "Reparatur", "positions": [], "can_edit": false]
    }

    override func stopLoading() {}
}

import Foundation
import Testing
@testable import WattNu

@MainActor
struct PublicMobileConfigTests {
    @Test func configLoadsBeforeSignInWithAnUnboundOfflineStore() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PublicMobileConfigURLProtocol.self]
        let networkSession = URLSession(configuration: configuration)
        let baseURL = try #require(URL(string: "https://backend.example.invalid"))
        let store = CommissionOfflineStore()
        let client = APIClient(baseURL: baseURL, session: networkSession)
        client.commissionStore = store
        defer {
            store.stop()
            networkSession.invalidateAndCancel()
        }

        let config = try await client.fetchMobileConfig()
        #expect(config.passwordLoginEnabled == false)
        #expect(config.microsoft?.clientId == "mobile-client")
        #expect(config.microsoft?.scopes == ["User.Read"])
    }
}

private final class PublicMobileConfigURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "backend.example.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              url.path == "/api/mobile/config",
              request.httpMethod == "GET",
              request.value(forHTTPHeaderField: "Authorization") == nil,
              let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let payload = """
        {
            "password_login_enabled": false,
            "microsoft": {
                "tenant_id": "tenant",
                "client_id": "mobile-client",
                "redirect_uri": "msauth.example.invalid://auth",
                "scopes": ["User.Read"]
            }
        }
        """
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

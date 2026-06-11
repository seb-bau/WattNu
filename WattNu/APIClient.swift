//
//  APIClient.swift
//  WattNu
//
//  Created by Sebastian Bauhaus on 09.06.26.
//

import Foundation

enum APIError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case unauthorized
    case serverStatus(Int, String)
    case missingToken

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Die Backend-URL ist ungültig."
        case .invalidResponse:
            return "Die Antwort des Servers ist ungültig."
        case .unauthorized:
            return "Die Anmeldung ist abgelaufen oder ungültig."
        case .serverStatus(let status, let message):
            return "Serverfehler \(status): \(message)"
        case .missingToken:
            return "Es ist kein Zugriffstoken vorhanden."
        }
    }
}

final class APIClient {
    var baseURL: URL
    var accessToken: String?

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    func updateBaseURL(_ value: URL) {
        baseURL = value
    }
    
    func fetchMobileConfig() async throws -> MobileConfig {
        try await request(path: "/api/mobile/config")
    }

    func loginPassword(email: String, password: String) async throws -> AuthResponse {
        let body = PasswordLoginRequest(email: email, password: password)
        return try await send(path: "/api/auth/password", method: "POST", body: body)
    }

    func loginMicrosoft(idToken: String) async throws -> AuthResponse {
        let body = MicrosoftLoginRequest(idToken: idToken)
        return try await send(path: "/api/auth/microsoft", method: "POST", body: body)
    }

    func getMe() async throws -> CurrentUserResponse {
        try requireToken()
        return try await request(path: "/api/me")
    }

    func fetchCommissions(scope: CommissionScopeFilter = .mine, status: CommissionStatusFilter = .active, userId: Int? = nil) async throws -> [Commission] {
        try requireToken()

        var queryItems = [
            URLQueryItem(name: "scope", value: scope.rawValue)
        ]

        if status != .all {
            queryItems.append(URLQueryItem(name: "status", value: status.rawValue))
        }

        if let userId {
            queryItems.append(URLQueryItem(name: "user_id", value: "\(userId)"))
        }

        let response: ListResponse<Commission> = try await request(path: "/api/commissions", queryItems: queryItems)
        return response.items
    }
    
    func fetchCommissionUsers() async throws -> [AppUser] {
        try requireToken()
        let response: ListResponse<AppUser> = try await request(path: "/api/commissions/users")
        return response.items
    }

    func fetchCommission(id: Int) async throws -> Commission {
        try requireToken()
        let response: ItemResponse<Commission> = try await request(path: "/api/commissions/\(id)")
        return response.item
    }
    
    func fetchCommissionContacts(commissionId: Int) async throws -> [CommissionContactItem] {
        try requireToken()
        let response: CommissionContactsResponse = try await request(path: "/api/commissions/\(commissionId)/contacts")
        return response.contactItems
    }

    func startCommission(id: Int) async throws -> Commission {
        try requireToken()
        let response: ItemResponse<Commission> = try await send(path: "/api/commissions/\(id)/start", method: "POST", body: EmptyRequest())
        return response.item
    }

    func completeCommission(id: Int) async throws -> Commission {
        try requireToken()
        let response: ItemResponse<Commission> = try await send(path: "/api/commissions/\(id)/complete", method: "POST", body: EmptyRequest())
        return response.item
    }

    func lookupInventory(code: String) async throws -> InventoryItem {
        try requireToken()
        let response: ItemResponse<InventoryItem> = try await request(path: "/api/inventory/lookup", queryItems: [
            URLQueryItem(name: "code", value: code)
        ])
        return response.item
    }
    
    func searchInventory(query: String, limit: Int = 12) async throws -> [InventoryItem] {
        try requireToken()
        let response: ListResponse<InventoryItem> = try await request(path: "/api/inventory/search", queryItems: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "\(limit)")
        ])
        return response.items
    }

    func fetchMaterials(commissionId: Int) async throws -> [InventoryMovement] {
        try requireToken()
        let response: ListResponse<InventoryMovement> = try await request(path: "/api/commissions/\(commissionId)/materials")
        return response.items
    }

    func addMaterial(commissionId: Int, code: String, quantity: Double, note: String?) async throws -> MaterialResponse {
        try requireToken()
        let body = MaterialRequest(code: code, quantity: quantity, note: note)
        return try await send(path: "/api/commissions/\(commissionId)/materials", method: "POST", body: body)
    }

    func fetchTimeTasks() async throws -> [TimeTask] {
        try requireToken()
        let response: ListResponse<TimeTask> = try await request(path: "/api/time-tasks")
        return response.items
    }
    
    func searchTimeTasks(query: String, limit: Int = 12) async throws -> [TimeTask] {
        try requireToken()
        let response: ListResponse<TimeTask> = try await request(path: "/api/time-tasks/search", queryItems: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "\(limit)")
        ])
        return response.items
    }

    func fetchTimeEntries(commissionId: Int) async throws -> [TimeEntry] {
        try requireToken()
        let response: ListResponse<TimeEntry> = try await request(path: "/api/commissions/\(commissionId)/time")
        return response.items
    }

    func addTimeEntry(commissionId: Int, taskTemplateId: Int?, minutes: Int, note: String?) async throws -> TimeEntry {
        try requireToken()
        let body = TimeEntryRequest(taskTemplateId: taskTemplateId, minutes: minutes, note: note)
        let response: ItemResponse<TimeEntry> = try await send(path: "/api/commissions/\(commissionId)/time", method: "POST", body: body)
        return response.item
    }

    private func request<Response: Decodable>(path: String, queryItems: [URLQueryItem] = []) async throws -> Response {
        try await perform(path: path, method: "GET", queryItems: queryItems, bodyData: nil)
    }

    private func send<Response: Decodable, Body: Encodable>(path: String, method: String, body: Body) async throws -> Response {
        let bodyData = try encoder.encode(body)
        return try await perform(path: path, method: method, queryItems: [], bodyData: bodyData)
    }

    private func perform<Response: Decodable>(path: String, method: String, queryItems: [URLQueryItem], bodyData: Data?) async throws -> Response {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidBaseURL
        }

        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw APIError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        if let bodyData {
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw APIError.serverStatus(httpResponse.statusCode, message)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.serverStatus(httpResponse.statusCode, String(data: data, encoding: .utf8) ?? error.localizedDescription)
        }
    }

    private func requireToken() throws {
        if accessToken == nil {
            throw APIError.missingToken
        }
    }
}

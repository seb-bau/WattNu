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
    
    func fetchPushPreferences() async throws -> PushPreferences {
        try requireToken()
        let response: PushPreferencesResponse = try await request(
            path: "/api/push/preferences"
        )
        return response.preferences
    }

    func updatePushPreferences(
        newCommissionEnabled: Bool,
        changedCommissionEnabled: Bool
    ) async throws -> PushPreferences {
        try requireToken()
        let body = PushPreferencesUpdateRequest(
            newCommissionEnabled: newCommissionEnabled,
            changedCommissionEnabled: changedCommissionEnabled
        )
        let response: PushPreferencesResponse = try await send(
            path: "/api/push/preferences",
            method: "PATCH",
            body: body
        )
        return response.preferences
    }

    func registerPushDevice(
        installationId: String,
        deviceToken: String,
        appVersion: String?,
        deviceName: String?
    ) async throws -> PushDeviceInfo {
        try requireToken()
        let body = PushDeviceRegistrationRequest(
            installationId: installationId,
            deviceToken: deviceToken,
            platform: "ios",
            appVersion: appVersion,
            deviceName: deviceName
        )
        let response: PushDeviceRegistrationResponse = try await send(
            path: "/api/push/device",
            method: "PUT",
            body: body
        )
        return response.device
    }

    func unregisterPushDevice(
        installationId: String
    ) async throws -> Bool {
        try requireToken()
        let body = PushDeviceUnregistrationRequest(
            installationId: installationId
        )
        let response: PushDeviceUnregistrationResponse = try await send(
            path: "/api/push/device",
            method: "DELETE",
            body: body
        )
        return response.unregistered
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
    
    func fetchCommissionHistory(
        commissionId: Int
    ) async throws -> [CommissionHistoryEntry] {
        try requireToken()

        let response: ListResponse<CommissionHistoryEntry> = try await request(
            path: "/api/commissions/\(commissionId)/history"
        )

        return response.items
    }
    
    func fetchCommissionCreateOptions() async throws -> CommissionCreateOptions {
        try requireToken()

        return try await request(
            path: "/api/commissions/create-options"
        )
    }
    
    func fetchCommissionCreateTasks() async throws -> [TimeTask] {
        try requireToken()

        let response: ListResponse<TimeTask> = try await request(
            path: "/api/commissions/create-tasks",
            queryItems: [
                URLQueryItem(name: "limit", value: "250")
            ]
        )

        return response.items
    }

    func searchCommissionObjects(
        query: String,
        limit: Int = 30
    ) async throws -> [CommissionObjectChoice] {
        try requireToken()

        let response: ListResponse<CommissionObjectChoice> = try await request(
            path: "/api/commission-objects/search",
            queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "limit", value: "\(limit)")
            ]
        )

        return response.items
    }

    func createCommission(
        body: CommissionCreateRequest
    ) async throws -> Commission {
        try requireToken()

        let response: ItemResponse<Commission> = try await send(
            path: "/api/commissions",
            method: "POST",
            body: body
        )

        return response.item
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
    
    func fetchProcessInfos(
        commissionId: Int
    ) async throws -> ProcessInfoListResponse {
        try requireToken()

        return try await request(
            path:
                "/api/commissions/"
                + "\(commissionId)/infos"
        )
    }

    func createProcessInfo(
        commissionId: Int,
        requestId: String,
        body: String
    ) async throws -> ProcessInfoMessage {
        try requireToken()

        let response:
            ItemResponse<ProcessInfoMessage> =
                try await send(
                    path:
                        "/api/commissions/"
                        + "\(commissionId)/infos",
                    method: "POST",
                    body:
                        ProcessInfoCreateRequest(
                            requestId: requestId,
                            body: body
                        )
                )

        return response.item
    }

    func markProcessInfosRead(
        commissionId: Int,
        infoIds: [String]
    ) async throws -> ProcessInfoUnreadSummary {
        try requireToken()

        return try await send(
            path:
                "/api/commissions/"
                + "\(commissionId)/infos/read",
            method: "POST",
            body:
                ProcessInfoReadRequest(
                    infoIds: infoIds
                )
        )
    }

    func fetchProcessInfoUnreadSummary()
    async throws -> ProcessInfoUnreadSummary {
        try requireToken()

        return try await request(
            path: "/api/process-infos/unread"
        )
    }
    
    func fetchCommissionContacts(commissionId: Int) async throws -> [CommissionContactItem] {
        try requireToken()
        let response: CommissionContactsResponse = try await request(path: "/api/commissions/\(commissionId)/contacts")
        return response.contactItems
    }
    
    func fetchAppointmentWindows() async throws -> [AppointmentWindow] {
        try requireToken()

        let response: ListResponse<AppointmentWindow> = try await request(
            path: "/api/appointment-windows"
        )

        return response.items
    }

    func fetchCommissionAppointments(
        commissionId: Int
    ) async throws -> [CommissionAppointmentRequest] {
        try requireToken()

        let response: ListResponse<CommissionAppointmentRequest> = try await request(
            path: "/api/commissions/\(commissionId)/appointments"
        )

        return response.items
    }

    func createCommissionAppointmentRequest(
        commissionId: Int,
        recipientName: String?,
        recipientEmail: String,
        message: String?,
        proposals: [AppointmentProposalCreatePayload]
    ) async throws -> CommissionAppointmentRequest {
        try requireToken()

        let body = AppointmentRequestCreatePayload(
            recipientName: recipientName,
            recipientEmail: recipientEmail,
            message: message,
            proposals: proposals
        )

        let response: ItemResponse<CommissionAppointmentRequest> = try await send(
            path: "/api/commissions/\(commissionId)/appointments",
            method: "POST",
            body: body
        )

        return response.item
    }
    
    func cancelAcceptedCommissionAppointment(
        commissionId: Int
    ) async throws -> Commission {
        try requireToken()

        let response: ItemResponse<Commission> = try await send(
            path: "/api/commissions/\(commissionId)/appointments/accepted",
            method: "DELETE",
            body: EmptyRequest()
        )

        return response.item
    }

    func startCommission(id: Int) async throws -> Commission {
        try requireToken()
        let response: ItemResponse<Commission> = try await send(path: "/api/commissions/\(id)/start", method: "POST", body: EmptyRequest())
        return response.item
    }
    
    func rejectCommission(
        id: Int,
        reason: String
    ) async throws -> Commission {
        try requireToken()

        let response: ItemResponse<Commission> =
            try await send(
                path: "/api/commissions/\(id)/reject",
                method: "POST",
                body: CommissionRejectionRequest(
                    reason: reason
                )
            )

        return response.item
    }
    
    func fetchCommissionCompletionCheck(
        id: Int
    ) async throws -> CommissionCompletionCheck {
        try requireToken()

        return try await request(
            path: "/api/commissions/\(id)/completion-check"
        )
    }

    func completeCommission(
        id: Int,
        completed: Bool,
        tenantCharge: Bool,
        reason: String?,
        confirmMissingMaterial: Bool
    ) async throws -> Commission {
        try requireToken()

        let body = CommissionCompletionRequest(
            completed: completed,
            tenantCharge: tenantCharge,
            reason: reason,
            confirmMissingMaterial:
                confirmMissingMaterial
        )

        let response: ItemResponse<Commission> =
            try await send(
                path: "/api/commissions/\(id)/complete",
                method: "POST",
                body: body
            )

        return response.item
    }
    
    func fetchCommissionAttachments(
        commissionId: Int
    ) async throws -> [CommissionAttachment] {
        try requireToken()

        let response: ListResponse<CommissionAttachment> = try await request(
            path: "/api/commissions/\(commissionId)/attachments"
        )

        return response.items
    }

    func downloadCommissionAttachment(
        path: String
    ) async throws -> Data {
        try requireToken()

        return try await performRaw(
            path: path,
            method: "GET",
            contentType: nil,
            accept: "*/*",
            bodyData: nil
        )
    }
    
    func fetchCommissionPhotos(
        commissionId: Int,
        context: String? = nil,
        entity: String? = nil
    ) async throws -> [CommissionPhoto] {
        try requireToken()

        var queryItems: [URLQueryItem] = []

        if let context,
           !context.isEmpty {
            queryItems.append(
                URLQueryItem(
                    name: "context",
                    value: context
                )
            )
        }

        if let entity,
           !entity.isEmpty {
            queryItems.append(
                URLQueryItem(
                    name: "entity",
                    value: entity
                )
            )
        }

        let response: ListResponse<CommissionPhoto> = try await request(
            path: "/api/commissions/\(commissionId)/photos",
            queryItems: queryItems
        )

        return response.items
    }

    func uploadCommissionPhoto(
        commissionId: Int,
        imageData: Data,
        caption: String?
    ) async throws -> CommissionPhotoUploadResponse {
        try requireToken()

        let boundary = "WattNu-\(UUID().uuidString)"
        var body = Data()

        if let caption,
           !caption.isEmpty {
            body.appendUTF8(
                "--\(boundary)\r\n"
            )
            body.appendUTF8(
                "Content-Disposition: form-data; name=\"caption\"\r\n\r\n"
            )
            body.appendUTF8(caption)
            body.appendUTF8("\r\n")
        }

        body.appendUTF8(
            "--\(boundary)\r\n"
        )
        body.appendUTF8(
            "Content-Disposition: form-data; name=\"photo\"; filename=\"foto.jpg\"\r\n"
        )
        body.appendUTF8(
            "Content-Type: image/jpeg\r\n\r\n"
        )
        body.append(imageData)
        body.appendUTF8("\r\n")
        body.appendUTF8(
            "--\(boundary)--\r\n"
        )

        let data = try await performRaw(
            path: "/api/commissions/\(commissionId)/photos",
            method: "POST",
            contentType: "multipart/form-data; boundary=\(boundary)",
            accept: "application/json",
            bodyData: body
        )

        return try decoder.decode(
            CommissionPhotoUploadResponse.self,
            from: data
        )
    }

    func updateCommissionPhoto(
        commissionId: Int,
        photoId: Int,
        caption: String?
    ) async throws -> CommissionPhoto {
        try requireToken()

        let body = CommissionPhotoUpdateRequest(
            caption: caption
        )

        let response: ItemResponse<CommissionPhoto> = try await send(
            path: "/api/commissions/\(commissionId)/photos/\(photoId)",
            method: "PATCH",
            body: body
        )

        return response.item
    }

    func deleteCommissionPhoto(
        commissionId: Int,
        photoId: Int
    ) async throws {
        try requireToken()

        _ = try await performRaw(
            path: "/api/commissions/\(commissionId)/photos/\(photoId)",
            method: "DELETE",
            contentType: nil,
            accept: "application/json",
            bodyData: nil
        )
    }

    func downloadCommissionPhoto(
        path: String
    ) async throws -> Data {
        try requireToken()

        return try await performRaw(
            path: path,
            method: "GET",
            contentType: nil,
            accept: "image/jpeg",
            bodyData: nil
        )
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
    
    func fetchInventoryLocations() async throws -> [InventoryLocation] {
        try requireToken()

        let response: ListResponse<InventoryLocation> = try await request(
            path: "/api/inventory/locations"
        )

        return response.items
    }

    func fetchInventoryMovements(
        limit: Int = 30
    ) async throws -> [InventoryMovement] {
        try requireToken()

        let response: ListResponse<InventoryMovement> = try await request(
            path: "/api/inventory/movements",
            queryItems: [
                URLQueryItem(
                    name: "limit",
                    value: "\(limit)"
                )
            ]
        )

        return response.items
    }

    func transferInventory(
        code: String,
        quantity: Double,
        sourceLocationId: Int,
        targetLocationId: Int,
        note: String?
    ) async throws -> MaterialResponse {
        try requireToken()

        let body = InventoryTransferRequest(
            code: code,
            quantity: quantity,
            sourceLocationId: sourceLocationId,
            targetLocationId: targetLocationId,
            note: note
        )

        return try await send(
            path: "/api/inventory/transfer",
            method: "POST",
            body: body
        )
    }

    func receiveInventory(
        code: String,
        quantity: Double,
        targetLocationId: Int,
        note: String?
    ) async throws -> MaterialResponse {
        try requireToken()

        let body = InventoryReceiptRequest(
            code: code,
            quantity: quantity,
            targetLocationId: targetLocationId,
            note: note
        )

        return try await send(
            path: "/api/inventory/receipt",
            method: "POST",
            body: body
        )
    }

    func fetchMaterials(commissionId: Int) async throws -> [InventoryMovement] {
        try requireToken()
        let response: ListResponse<InventoryMovement> = try await request(path: "/api/commissions/\(commissionId)/materials")
        return response.items
    }

    func addMaterial(
        commissionId: Int,
        code: String,
        quantity: Double,
        taskTemplateId: Int?,
        usageStatus: String?,
        source: String?,
        locationId: Int?,
        deviationReason: String?,
        note: String?
    ) async throws -> MaterialResponse {
        try requireToken()

        let body = MaterialRequest(
            code: code,
            quantity: quantity,
            taskTemplateId: taskTemplateId,
            usageStatus: usageStatus,
            source: source,
            locationId: locationId,
            deviationReason: deviationReason,
            note: note
        )

        return try await send(
            path: "/api/commissions/\(commissionId)/materials",
            method: "POST",
            body: body
        )
    }
    
    func cancelMaterial(commissionId: Int, movementId: Int) async throws -> MaterialResponse {
        try requireToken()
        return try await send(
            path: "/api/commissions/\(commissionId)/materials/\(movementId)/cancel",
            method: "POST",
            body: EmptyRequest()
        )
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

    func addTimeEntry(
        commissionId: Int,
        taskTemplateId: Int?,
        serviceDate: String,
        minutes: Int?,
        workMinutes: Int?,
        waitingMinutes: Int?,
        materialMinutes: Int?,
        travelMinutes: Int?,
        documentationMinutes: Int?,
        extraMinutes: Int?,
        deviationReason: String?,
        note: String?
    ) async throws -> TimeEntry {
        try requireToken()

        let body = TimeEntryRequest(
            taskTemplateId: taskTemplateId,
            serviceDate: serviceDate,
            minutes: minutes,
            workMinutes: workMinutes,
            waitingMinutes: waitingMinutes,
            materialMinutes: materialMinutes,
            travelMinutes: travelMinutes,
            documentationMinutes: documentationMinutes,
            extraMinutes: extraMinutes,
            deviationReason: deviationReason,
            note: note
        )

        let response: ItemResponse<TimeEntry> = try await send(
            path: "/api/commissions/\(commissionId)/time",
            method: "POST",
            body: body
        )

        return response.item
    }

    func updateTimeEntry(
        commissionId: Int,
        entryId: Int,
        taskTemplateId: Int?,
        serviceDate: String,
        minutes: Int?,
        workMinutes: Int?,
        waitingMinutes: Int?,
        materialMinutes: Int?,
        travelMinutes: Int?,
        documentationMinutes: Int?,
        extraMinutes: Int?,
        deviationReason: String?,
        note: String?
    ) async throws -> TimeEntry {
        try requireToken()

        let body = TimeEntryRequest(
            taskTemplateId: taskTemplateId,
            serviceDate: serviceDate,
            minutes: minutes,
            workMinutes: workMinutes,
            waitingMinutes: waitingMinutes,
            materialMinutes: materialMinutes,
            travelMinutes: travelMinutes,
            documentationMinutes: documentationMinutes,
            extraMinutes: extraMinutes,
            deviationReason: deviationReason,
            note: note
        )

        let response: ItemResponse<TimeEntry> = try await send(
            path: "/api/commissions/\(commissionId)/time/\(entryId)",
            method: "PATCH",
            body: body
        )

        return response.item
    }

    func deleteTimeEntry(commissionId: Int, entryId: Int) async throws {
        try requireToken()
        let _: EmptyResponse = try await send(path: "/api/commissions/\(commissionId)/time/\(entryId)", method: "DELETE", body: EmptyRequest())
    }
    
    func fetchSafetyInspections(
        status: String = "active",
        scope: String = "mine",
        overdueOnly: Bool = false
    ) async throws -> [SafetyInspectionJob] {
        try requireToken()

        var queryItems = [
            URLQueryItem(
                name: "status",
                value: status
            ),
            URLQueryItem(
                name: "scope",
                value: scope
            )
        ]

        if overdueOnly {
            queryItems.append(
                URLQueryItem(
                    name: "overdue",
                    value: "1"
                )
            )
        }

        let response: ListResponse<SafetyInspectionJob> =
            try await request(
                path: "/api/safety-inspections",
                queryItems: queryItems
            )

        return response.items
    }

    func fetchSafetyInspection(
        id: Int
    ) async throws -> SafetyInspectionJob {
        try requireToken()

        let response: ItemResponse<SafetyInspectionJob> =
            try await request(
                path: "/api/safety-inspections/\(id)"
            )

        return response.item
    }

    func updateSafetyInspectionResult(
        jobId: Int,
        resultId: Int,
        state: String,
        note: String?,
        immediateAction: String?,
        version: Int
    ) async throws -> SafetyInspectionResult {
        try requireToken()

        let body = SafetyInspectionResultUpdateRequest(
            state: state,
            note: note,
            immediateAction: immediateAction,
            version: version
        )

        let response: ItemResponse<SafetyInspectionResult> =
            try await send(
                path: (
                    "/api/safety-inspections/"
                    + "\(jobId)/results/\(resultId)"
                ),
                method: "PATCH",
                body: body
            )

        return response.item
    }

    func completeSafetyInspection(
        jobId: Int,
        overallNote: String?
    ) async throws -> SafetyInspectionJob {
        try requireToken()

        let body = SafetyInspectionCompletionRequest(
            overallNote: overallNote
        )

        let response: ItemResponse<SafetyInspectionJob> =
            try await send(
                path: (
                    "/api/safety-inspections/"
                    + "\(jobId)/complete"
                ),
                method: "POST",
                body: body
            )

        return response.item
    }

    func uploadSafetyInspectionPhoto(
        jobId: Int,
        resultId: Int,
        imageData: Data,
        source: String,
        caption: String? = nil,
        capturedAt: Date = Date()
    ) async throws -> SafetyInspectionPhotoUploadResponse {
        try requireToken()

        let boundary = "WattNu-\(UUID().uuidString)"
        let dateFormatter = ISO8601DateFormatter()

        dateFormatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]

        var body = Data()

        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8(
            "Content-Disposition: form-data; "
            + "name=\"source\"\r\n\r\n"
        )
        body.appendUTF8(source)
        body.appendUTF8("\r\n")

        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8(
            "Content-Disposition: form-data; "
            + "name=\"captured_at\"\r\n\r\n"
        )
        body.appendUTF8(
            dateFormatter.string(from: capturedAt)
        )
        body.appendUTF8("\r\n")

        if let caption,
           !caption.isEmpty {
            body.appendUTF8("--\(boundary)\r\n")
            body.appendUTF8(
                "Content-Disposition: form-data; "
                + "name=\"caption\"\r\n\r\n"
            )
            body.appendUTF8(caption)
            body.appendUTF8("\r\n")
        }

        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8(
            "Content-Disposition: form-data; "
            + "name=\"photo\"; "
            + "filename=\"prueffoto.jpg\"\r\n"
        )
        body.appendUTF8(
            "Content-Type: image/jpeg\r\n\r\n"
        )
        body.append(imageData)
        body.appendUTF8("\r\n")
        body.appendUTF8("--\(boundary)--\r\n")

        let data = try await performRaw(
            path: (
                "/api/safety-inspections/"
                + "\(jobId)/results/\(resultId)/photos"
            ),
            method: "POST",
            contentType: (
                "multipart/form-data; "
                + "boundary=\(boundary)"
            ),
            accept: "application/json",
            bodyData: body
        )

        return try decoder.decode(
            SafetyInspectionPhotoUploadResponse.self,
            from: data
        )
    }

    func deleteSafetyInspectionPhoto(
        jobId: Int,
        resultId: Int,
        photoId: Int
    ) async throws {
        try requireToken()

        _ = try await performRaw(
            path: (
                "/api/safety-inspections/"
                + "\(jobId)/results/\(resultId)"
                + "/photos/\(photoId)"
            ),
            method: "DELETE",
            contentType: nil,
            accept: "application/json",
            bodyData: nil
        )
    }

    func downloadSafetyInspectionPhoto(
        path: String
    ) async throws -> Data {
        try requireToken()

        return try await performRaw(
            path: path,
            method: "GET",
            contentType: nil,
            accept: "image/jpeg",
            bodyData: nil
        )
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
            let errorResponse = try? decoder.decode(
                ErrorResponse.self,
                from: data
            )

            let fallbackMessage = String(
                data: data,
                encoding: .utf8
            ) ?? ""

            throw APIError.serverStatus(
                httpResponse.statusCode,
                errorResponse?.message ?? fallbackMessage
            )
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.serverStatus(httpResponse.statusCode, String(data: data, encoding: .utf8) ?? error.localizedDescription)
        }
    }
    
    private func performRaw(
        path: String,
        method: String,
        contentType: String?,
        accept: String,
        bodyData: Data?
    ) async throws -> Data {
        guard let components = URLComponents(
            url: baseURL.appendingPathComponent(
                path.trimmingCharacters(
                    in: CharacterSet(
                        charactersIn: "/"
                    )
                )
            ),
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError.invalidBaseURL
        }

        guard let url = components.url else {
            throw APIError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(
            accept,
            forHTTPHeaderField: "Accept"
        )

        if let accessToken {
            request.setValue(
                "Bearer \(accessToken)",
                forHTTPHeaderField: "Authorization"
            )
        }

        if let contentType {
            request.setValue(
                contentType,
                forHTTPHeaderField: "Content-Type"
            )
        }

        request.httpBody = bodyData

        let result = try await session.data(
            for: request
        )
        let data = result.0

        guard let response = result.1 as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if response.statusCode == 401 {
            throw APIError.unauthorized
        }

        guard 200..<300 ~= response.statusCode else {
            let errorResponse = try? decoder.decode(
                ErrorResponse.self,
                from: data
            )

            let fallbackMessage = String(
                data: data,
                encoding: .utf8
            ) ?? ""

            throw APIError.serverStatus(
                response.statusCode,
                errorResponse?.message
                ?? fallbackMessage
            )
        }

        return data
    }

    private func requireToken() throws {
        if accessToken == nil {
            throw APIError.missingToken
        }
    }
}

private extension Data {
    mutating func appendUTF8(
        _ value: String
    ) {
        if let data = value.data(
            using: .utf8
        ) {
            append(data)
        }
    }
}

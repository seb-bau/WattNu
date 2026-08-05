//
//  Models.swift
//  WattNu
//
//  Created by Sebastian Bauhaus on 09.06.26.
//

import Foundation
import CoreLocation

struct MobileConfig: Codable, Equatable {
    let passwordLoginEnabled: Bool
    let microsoft: MobileMicrosoftConfig?

    enum CodingKeys: String, CodingKey {
        case passwordLoginEnabled = "password_login_enabled"
        case microsoft
    }
}

struct MobileMicrosoftConfig: Codable, Equatable {
    let tenantId: String
    let clientId: String
    let redirectUri: String
    let scopes: [String]

    enum CodingKeys: String, CodingKey {
        case tenantId = "tenant_id"
        case clientId = "client_id"
        case redirectUri = "redirect_uri"
        case scopes
    }
}

struct AppUser: Codable, Identifiable, Equatable, Hashable {
    let id: Int
    let email: String
    let displayName: String
    let craftsmanErpId: Int?
    let isAdmin: Bool
    let isForeman: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
        case craftsmanErpId = "craftsman_erp_id"
        case isAdmin = "is_admin"
        case isForeman = "is_foreman"
    }
}

struct AuthResponse: Decodable {
    let accessToken: String
    let user: AppUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case user
    }
}

struct CurrentUserResponse: Decodable {
    let user: AppUser
}

struct ListResponse<Item: Decodable>: Decodable {
    let items: [Item]
}

struct ItemResponse<Item: Decodable>: Decodable {
    let item: Item
}

struct Commission: Codable, Identifiable, Hashable {
    let id: Int
    let erpId: Int?
    let erpIdNum: String?
    let code: String?
    let title: String?
    let description: String?
    let damageLocation: String?
    let contactPerson: String?
    let statusId: Int?
    let statusCode: String?
    let localStatus: String
    let craftsmanErpId: Int?
    let useUnitId: Int?
    let licenseAgreementId: Int?
    let apartmentAddress: String?
    let apartmentLocation: String?
    let tenantName: String?
    let assignedUser: AppUser?
    let isOwn: Bool?
    let canEdit: Bool?
    let recordingDate: String?
    let releaseDate: String?
    let executionFrom: String?
    let executionTo: String?
    let completedAt: String?
    let latitude: Double?
    let longitude: Double?
    let hasCoordinates: Bool?
    let publicId: String?
    let source: String?
    let erpSyncState: String?
    let erpSyncMessage: String?
    let commissionTypeId: Int?
    let isActionable: Bool?
    let displayTitleFromAPI: String?
    let completionSuccessful: Bool?
    let tenantChargeRequested: Bool?
    let completionReason: String?
    let positions: [CommissionPosition]
    let acceptedAppointmentFrom: String?
    let acceptedAppointmentTo: String?
    let acceptedAppointmentComment: String?

    enum CodingKeys: String, CodingKey {
        case id
        case erpId = "erp_id"
        case erpIdNum = "erp_idnum"
        case code
        case title
        case description
        case damageLocation = "damage_location"
        case contactPerson = "contact_person"
        case statusId = "status_id"
        case statusCode = "status_code"
        case localStatus = "local_status"
        case craftsmanErpId = "craftsman_erp_id"
        case useUnitId = "use_unit_id"
        case licenseAgreementId = "license_agreement_id"
        case apartmentAddress = "apartment_address"
        case apartmentLocation = "apartment_location"
        case tenantName = "tenant_name"
        case assignedUser = "assigned_user"
        case isOwn = "is_own"
        case canEdit = "can_edit"
        case recordingDate = "recording_date"
        case releaseDate = "release_date"
        case executionFrom = "execution_from"
        case executionTo = "execution_to"
        case completedAt = "completed_at"
        case latitude
        case longitude
        case hasCoordinates = "has_coordinates"
        case publicId = "public_id"
        case source
        case erpSyncState = "erp_sync_state"
        case erpSyncMessage = "erp_sync_message"
        case commissionTypeId = "commission_type_id"
        case isActionable = "is_actionable"
        case displayTitleFromAPI = "display_title"
        case completionSuccessful = "completion_successful"
        case tenantChargeRequested = "tenant_charge_requested"
        case completionReason = "completion_reason"
        case positions
        case acceptedAppointmentFrom = "accepted_appointment_from"
        case acceptedAppointmentTo = "accepted_appointment_to"
        case acceptedAppointmentComment = "accepted_appointment_comment"
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else {
            return nil
        }

        return CLLocationCoordinate2D(
            latitude: latitude,
            longitude: longitude
        )
    }

    var displayTitle: String {
        if let displayTitleFromAPI,
           !displayTitleFromAPI.isEmpty {
            return displayTitleFromAPI
        }

        if let title, !title.isEmpty {
            return title
        }

        if let erpId {
            return "Auftrag \(erpId)"
        }

        return "Ausstehender Auftrag"
    }

    var displayNumber: String {
        if let erpIdNum, !erpIdNum.isEmpty {
            return erpIdNum
        }

        if let code, !code.isEmpty {
            return code
        }

        if let erpId {
            return String(erpId)
        }

        return "Ausstehend"
    }

    var assigneeName: String {
        if let assignedUser {
            return assignedUser.displayName
        }

        if let craftsmanErpId {
            return "Handwerker \(craftsmanErpId)"
        }

        return "Nicht zugeordnet"
    }

    var canEditValue: Bool {
        canEdit ?? true
    }

    var isActionableValue: Bool {
        isActionable ?? (erpId != nil)
    }

    var localStatusLabel: String {
        switch localStatus {
        case "recorded":
            return "Ausstehend"
        case "waiting_for_acceptance":
            return "Warte auf Annahme"
        case "open":
            return "Offen"
        case "in_progress":
            return "In Bearbeitung"
        case "completion_review":
            return "Abschlussprüfung"
        case "tenant_charge_review":
            return "Mieterbelastung prüfen"
        case "done":
            return "Abgeschlossen"
        case "deleted":
            return "Gelöscht"
        default:
            return localStatus
        }
    }
}

struct CommissionPosition: Codable, Identifiable, Hashable {
    let id: Int
    let erpId: Int?
    let positionIndex: Int
    let positionNumber: Double?
    let code: String?
    let commissionText: String?
    let internalDescription: String?
    let description: String?
    let displayText: String?
    let units: Double
    let serviceCatalogId: Int?
    let craftActivityId: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case erpId = "erp_id"
        case positionIndex = "position_index"
        case positionNumber = "position_number"
        case code
        case commissionText = "commission_text"
        case internalDescription = "internal_description"
        case description
        case displayText = "display_text"
        case units
        case serviceCatalogId = "service_catalog_id"
        case craftActivityId = "craft_activity_id"
    }

    var displayTextValue: String {
        displayText
        ?? internalDescription
        ?? commissionText
        ?? description
        ?? code
        ?? "Position \(positionIndex + 1)"
    }
}

struct CommissionContactsResponse: Codable {
    let contactItems: [CommissionContactItem]

    enum CodingKeys: String, CodingKey {
        case contactItems = "contact_items"
    }
}

struct CommissionContactItem: Codable, Identifiable, Hashable {
    let personId: Int?
    let role: String?
    let name: String?
    let gender: String?
    let email: String?
    let emailId: Int?
    let emailComment: String?
    let phone: String?
    let phoneId: Int?
    let phoneComment: String?
    let mobile: String?
    let mobileId: Int?
    let mobileComment: String?
    let birthDate: String?
    let additionalNumbers: [String]

    var id: String {
        if let personId {
            return "\(personId)"
        }
        return name ?? UUID().uuidString
    }

    enum CodingKeys: String, CodingKey {
        case personId = "person_id"
        case role
        case name
        case gender
        case email
        case emailId = "email_id"
        case emailComment = "email_comment"
        case phone
        case phoneId = "phone_id"
        case phoneComment = "phone_comment"
        case mobile
        case mobileId = "mobile_id"
        case mobileComment = "mobile_comment"
        case birthDate = "birth_date"
        case additionalNumbers = "additional_numbers"
    }
}

struct InventoryLocation: Codable, Identifiable, Equatable, Hashable {
    let id: Int
    let code: String
    let name: String
    let locationType: String
    let isDefault: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case name
        case locationType = "location_type"
        case isDefault = "is_default"
    }

    var displayName: String {
        isDefault ? "\(name) · Standard" : name
    }
}

struct InventoryStock: Codable, Identifiable, Equatable, Hashable {
    let id: Int
    let quantity: Double
    let location: InventoryLocation
}

struct InventoryItem: Codable, Identifiable, Equatable, Hashable {
    let id: Int
    let itemNumber: String
    let name: String
    let unit: String
    let ean: String?
    let qrCodePayload: String
    let stockQuantity: Double
    let reorderLevel: Double
    let barcodes: [String]?
    let stocks: [InventoryStock]?

    enum CodingKeys: String, CodingKey {
        case id
        case itemNumber = "item_number"
        case name
        case unit
        case ean
        case qrCodePayload = "qr_code_payload"
        case stockQuantity = "stock_quantity"
        case reorderLevel = "reorder_level"
        case barcodes
        case stocks
    }

    var stocksValue: [InventoryStock] {
        stocks ?? []
    }

    func stockQuantity(
        at locationId: Int?
    ) -> Double {
        guard let locationId else {
            return 0
        }

        return stocksValue.first {
            $0.location.id == locationId
        }?.quantity ?? 0
    }
}

struct InventoryMovement: Codable, Identifiable, Equatable {
    let id: Int
    let item: InventoryItem
    let user: AppUser?
    let commissionId: Int?
    let taskTemplate: TimeTask?
    let movementType: String
    let quantity: Double
    let source: String?
    let sourceLocation: InventoryLocation?
    let targetLocation: InventoryLocation?
    let usageStatus: String?
    let deviationReason: String?
    let note: String?
    let reviewStatus: String?
    let reviewLevel: String?
    let occurredAt: String?
    let isCancelled: Bool?
    let canCancel: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case item
        case user
        case commissionId = "commission_id"
        case taskTemplate = "task_template"
        case movementType = "movement_type"
        case quantity
        case source
        case sourceLocation = "source_location"
        case targetLocation = "target_location"
        case usageStatus = "usage_status"
        case deviationReason = "deviation_reason"
        case note
        case reviewStatus = "review_status"
        case reviewLevel = "review_level"
        case occurredAt = "occurred_at"
        case isCancelled = "is_cancelled"
        case canCancel = "can_cancel"
    }

    var movementTypeLabel: String {
        switch movementType {
        case "withdrawal":
            return "Entnahme"
        case "ordered":
            return "Bestellt"
        case "stored":
            return "Eingelagert"
        case "correction":
            return "Korrektur"
        case "cancellation":
            return "Storno"
        case "transfer":
            return "Umbuchung"
        default:
            return movementType
        }
    }

    var sourceLabel: String {
        switch source {
        case "warehouse":
            return "Lager"
        case "vehicle":
            return "Fahrzeug"
        case "direct_purchase":
            return "Direktkauf"
        case "on_site":
            return "Vor Ort vorhanden"
        default:
            return source ?? ""
        }
    }

    var usageStatusLabel: String {
        switch usageStatus {
        case "installed":
            return "Verbaut"
        case "not_installed":
            return "Nicht verbaut"
        case "returned":
            return "Zurückgegeben"
        case "defective":
            return "Defekt"
        case "in_vehicle":
            return "Im Fahrzeug"
        default:
            return usageStatus ?? ""
        }
    }

    var reviewLabel: String {
        switch reviewStatus {
        case "ok":
            return "OK"
        case "needs_review":
            return "Prüfung nötig"
        case "approved":
            return "Freigegeben"
        case "rejected":
            return "Abgelehnt"
        default:
            return reviewStatus ?? ""
        }
    }

    var isCancelledValue: Bool {
        isCancelled ?? false
    }

    var canCancelValue: Bool {
        canCancel ?? false
    }
}

struct TimeTask: Codable, Identifiable, Hashable {
    let id: Int
    let code: String
    let title: String
    let suggestedMinutes: Int?
    let serviceCatalogId: Int?
    let erpIdNum: String?
    let craftActivity: CraftActivity?
    let expectedMaterials: [ExpectedMaterial]?

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case title
        case suggestedMinutes = "suggested_minutes"
        case serviceCatalogId = "service_catalog_id"
        case erpIdNum = "erp_idnum"
        case craftActivity = "craft_activity"
        case expectedMaterials = "expected_materials"
    }

    var expectedMaterialsValue: [ExpectedMaterial] {
        expectedMaterials ?? []
    }
}

struct CraftActivity: Codable, Identifiable, Hashable {
    let id: Int
    let erpId: Int?
    let code: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case id
        case erpId = "erp_id"
        case code
        case name
    }
}

struct ExpectedMaterial: Codable, Identifiable, Hashable {
    let id: Int
    let taskTemplateId: Int
    let item: InventoryItem
    let quantity: Double
    let required: Bool
    let note: String?

    enum CodingKeys: String, CodingKey {
        case id
        case taskTemplateId = "task_template_id"
        case item
        case quantity
        case required
        case note
    }
}

struct TimeEntry: Codable, Identifiable, Equatable {
    let id: Int
    let commissionId: Int
    let user: AppUser
    let taskTemplate: TimeTask?
    let minutes: Int
    let workMinutes: Int?
    let waitingMinutes: Int?
    let materialMinutes: Int?
    let travelMinutes: Int?
    let documentationMinutes: Int?
    let extraMinutes: Int?
    let deviationReason: String?
    let note: String?
    let deviationMinutes: Int
    let deviationPercent: Double
    let reviewStatus: String
    let reviewLevel: String?
    let createdAt: String?
    let canEdit: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case commissionId = "commission_id"
        case user
        case taskTemplate = "task_template"
        case minutes
        case workMinutes = "work_minutes"
        case waitingMinutes = "waiting_minutes"
        case materialMinutes = "material_minutes"
        case travelMinutes = "travel_minutes"
        case documentationMinutes = "documentation_minutes"
        case extraMinutes = "extra_minutes"
        case deviationReason = "deviation_reason"
        case note
        case deviationMinutes = "deviation_minutes"
        case deviationPercent = "deviation_percent"
        case reviewStatus = "review_status"
        case reviewLevel = "review_level"
        case createdAt = "created_at"
        case canEdit = "can_edit"
    }
    
    var canEditValue: Bool {
        canEdit ?? true
    }

    var reviewStatusLabel: String {
        switch reviewStatus {
        case "ok":
            return "OK"
        case "needs_review":
            return "Prüfung nötig"
        case "approved":
            return "Freigegeben"
        case "rejected":
            return "Abgelehnt"
        default:
            return reviewStatus
        }
    }
}

struct CommissionCreateOptions: Decodable {
    let canCreate: Bool
    let companyCodes: [CompanyCodeOption]
    let commissionTypes: [CommissionTypeOption]

    enum CodingKeys: String, CodingKey {
        case canCreate = "can_create"
        case companyCodes = "company_codes"
        case commissionTypes = "commission_types"
    }
}

struct CompanyCodeOption: Codable, Identifiable, Hashable {
    let id: Int
    let code: String
    let name: String

    var displayName: String {
        "\(code) · \(name)"
    }
}

struct CommissionTypeOption: Codable, Identifiable, Hashable {
    let id: Int
    let code: String?

    var displayName: String {
        if let code, !code.isEmpty {
            return code
        }

        return String(id)
    }
}

struct CommissionCreateRequest: Encodable {
    let companyCodeCode: String
    let commissionTypeId: Int
    let useUnitIdNum: String?
    let buildingIdNum: String?
    let licenseAgreementIdNum: String?
    let title: String?
    let damageLocation: String?
    let contactPerson: String?
    let executionFrom: String?
    let executionTo: String?
    let positions: [CommissionPositionRequest]

    enum CodingKeys: String, CodingKey {
        case companyCodeCode = "company_code_code"
        case commissionTypeId = "commission_type_id"
        case useUnitIdNum = "use_unit_idnum"
        case buildingIdNum = "building_idnum"
        case licenseAgreementIdNum = "license_agreement_idnum"
        case title
        case damageLocation = "damage_location"
        case contactPerson = "contact_person"
        case executionFrom = "execution_from"
        case executionTo = "execution_to"
        case positions
    }
}

struct CommissionPositionRequest: Encodable {
    let code: String?
    let commissionText: String
    let internalDescription: String?
    let units: Double
    let serviceCatalogId: Int

    enum CodingKeys: String, CodingKey {
        case code
        case commissionText = "commission_text"
        case internalDescription = "internal_description"
        case units
        case serviceCatalogId = "service_catalog_id"
    }
}

struct ErrorResponse: Decodable {
    let message: String?
}

struct PasswordLoginRequest: Encodable {
    let email: String
    let password: String
}

struct MicrosoftLoginRequest: Encodable {
    let idToken: String

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
    }
}

struct MaterialRequest: Encodable {
    let code: String
    let quantity: Double
    let taskTemplateId: Int?
    let usageStatus: String?
    let source: String?
    let locationId: Int?
    let deviationReason: String?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case code
        case quantity
        case taskTemplateId = "task_template_id"
        case usageStatus = "usage_status"
        case source
        case locationId = "location_id"
        case deviationReason = "deviation_reason"
        case note
    }
}

struct MaterialResponse: Decodable {
    let item: InventoryMovement
    let inventoryItem: InventoryItem

    enum CodingKeys: String, CodingKey {
        case item
        case inventoryItem = "inventory_item"
    }
}

struct TimeEntryRequest: Encodable {
    let taskTemplateId: Int?
    let minutes: Int?
    let workMinutes: Int?
    let waitingMinutes: Int?
    let materialMinutes: Int?
    let travelMinutes: Int?
    let documentationMinutes: Int?
    let extraMinutes: Int?
    let deviationReason: String?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case taskTemplateId = "task_template_id"
        case minutes
        case workMinutes = "work_minutes"
        case waitingMinutes = "waiting_minutes"
        case materialMinutes = "material_minutes"
        case travelMinutes = "travel_minutes"
        case documentationMinutes = "documentation_minutes"
        case extraMinutes = "extra_minutes"
        case deviationReason = "deviation_reason"
        case note
    }
}

struct EmptyRequest: Encodable {
}

struct EmptyResponse: Decodable {
}

struct CommissionAttachment: Codable, Identifiable {
    let id: Int
    let commissionId: Int
    let sourceEntityName: String
    let sourceEntityId: Int?
    let externalDocumentId: String?
    let originalFilename: String
    let mimeType: String
    let sizeBytes: Int
    let isImage: Bool
    let createdAt: String?
    let contentPath: String
    let thumbnailPath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case commissionId = "commission_id"
        case sourceEntityName = "source_entity_name"
        case sourceEntityId = "source_entity_id"
        case externalDocumentId = "external_document_id"
        case originalFilename = "original_filename"
        case mimeType = "mime_type"
        case sizeBytes = "size_bytes"
        case isImage = "is_image"
        case createdAt = "created_at"
        case contentPath = "content_path"
        case thumbnailPath = "thumbnail_path"
    }

    var sourceLabel: String {
        switch sourceEntityName.lowercased() {
        case "commission":
            return "Auftrag"
        case "craftsprocess":
            return "Vorgang"
        case "ticket":
            return "Ticket"
        default:
            return sourceEntityName
        }
    }

    var sizeLabel: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(sizeBytes),
            countStyle: .file
        )
    }

    var iconName: String {
        if isImage {
            return "photo"
        }

        if mimeType == "application/pdf" {
            return "doc.richtext"
        }

        return "doc"
    }
}

struct CommissionPhoto: Codable, Identifiable {
    let id: Int
    let commissionId: Int
    let source: String
    let externalId: String?
    let originalFilename: String
    let mimeType: String
    let sizeBytes: Int
    let caption: String?
    let uploadedBy: AppUser?
    let createdAt: String?
    let updatedAt: String?
    let contentPath: String
    let thumbnailPath: String

    enum CodingKeys: String, CodingKey {
        case id
        case commissionId = "commission_id"
        case source
        case externalId = "external_id"
        case originalFilename = "original_filename"
        case mimeType = "mime_type"
        case sizeBytes = "size_bytes"
        case caption
        case uploadedBy = "uploaded_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case contentPath = "content_path"
        case thumbnailPath = "thumbnail_path"
    }

    var sourceLabel: String {
        switch source {
        case "app":
            return "App"
        case "wowiport":
            return "Wowiport"
        default:
            return source
        }
    }
}

struct CommissionPhotoUploadResponse: Decodable {
    let item: CommissionPhoto
    let duplicate: Bool?
}

struct CommissionPhotoUpdateRequest: Encodable {
    let caption: String?
}

struct AppointmentWindow: Codable, Identifiable, Hashable {
    let id: Int
    let code: String
    let name: String
    let startTime: String
    let endTime: String
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case name
        case startTime = "start_time"
        case endTime = "end_time"
        case sortOrder = "sort_order"
    }

    var displayName: String {
        "\(name) · \(startTime)–\(endTime) Uhr"
    }
}

struct CommissionAppointmentProposal: Codable, Identifiable, Hashable {
    let id: Int
    let windowId: Int?
    let proposedDate: String
    let startTime: String
    let endTime: String
    let windowName: String
    let accepted: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case windowId = "window_id"
        case proposedDate = "proposed_date"
        case startTime = "start_time"
        case endTime = "end_time"
        case windowName = "window_name"
        case accepted
    }

    var displayText: String {
        let inputFormatter = DateFormatter()
        inputFormatter.locale = Locale(
            identifier: "en_US_POSIX"
        )
        inputFormatter.dateFormat = "yyyy-MM-dd"

        let outputFormatter = DateFormatter()
        outputFormatter.locale = Locale(
            identifier: "de_DE"
        )
        outputFormatter.dateStyle = .medium

        let dateText: String

        if let date = inputFormatter.date(
            from: proposedDate
        ) {
            dateText = outputFormatter.string(
                from: date
            )
        } else {
            dateText = proposedDate
        }

        return "\(dateText) · \(startTime)–\(endTime) Uhr"
    }
}

struct CommissionAppointmentRequest: Codable, Identifiable {
    let id: Int
    let commissionId: Int
    let recipientName: String?
    let recipientEmail: String
    let message: String?
    let status: String
    let tenantComment: String?
    let sentAt: String?
    let respondedAt: String?
    let expiresAt: String?
    let createdAt: String?
    let createdBy: AppUser?
    let acceptedProposalId: Int?
    let proposals: [CommissionAppointmentProposal]

    enum CodingKeys: String, CodingKey {
        case id
        case commissionId = "commission_id"
        case recipientName = "recipient_name"
        case recipientEmail = "recipient_email"
        case message
        case status
        case tenantComment = "tenant_comment"
        case sentAt = "sent_at"
        case respondedAt = "responded_at"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
        case createdBy = "created_by"
        case acceptedProposalId = "accepted_proposal_id"
        case proposals
    }

    var statusLabel: String {
        switch status {
        case "pending":
            return "Rückmeldung ausstehend"
        case "accepted":
            return "Angenommen"
        case "rejected":
            return "Abgelehnt"
        case "superseded":
            return "Nicht mehr aktuell"
        case "expired":
            return "Abgelaufen"
        case "cancelled":
            return "Termin aufgehoben"
        default:
            return status
        }
    }

    var statusColorName: String {
        switch status {
        case "accepted":
            return "green"
        case "rejected":
            return "red"
        case "pending":
            return "orange"
        default:
            return "secondary"
        }
    }
}

struct AppointmentProposalCreatePayload: Encodable {
    let date: String
    let windowId: Int

    enum CodingKeys: String, CodingKey {
        case date
        case windowId = "window_id"
    }
}

struct AppointmentRequestCreatePayload: Encodable {
    let recipientName: String?
    let recipientEmail: String
    let message: String?
    let proposals: [AppointmentProposalCreatePayload]

    enum CodingKeys: String, CodingKey {
        case recipientName = "recipient_name"
        case recipientEmail = "recipient_email"
        case message
        case proposals
    }
}

struct CommissionHistoryEntry: Codable, Identifiable, Hashable {
    let id: Int
    let action: String
    let title: String
    let detail: String?
    let actor: AppUser?
    let actorName: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case action
        case title
        case detail
        case actor
        case actorName = "actor_name"
        case createdAt = "created_at"
    }
}

struct CommissionCompletionRequest: Encodable {
    let completed: Bool
    let tenantCharge: Bool
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case completed
        case tenantCharge = "tenant_charge"
        case reason
    }
}

struct InventoryTransferRequest: Encodable {
    let code: String
    let quantity: Double
    let sourceLocationId: Int
    let targetLocationId: Int
    let note: String?

    enum CodingKeys: String, CodingKey {
        case code
        case quantity
        case sourceLocationId = "source_location_id"
        case targetLocationId = "target_location_id"
        case note
    }
}

struct InventoryReceiptRequest: Encodable {
    let code: String
    let quantity: Double
    let targetLocationId: Int
    let note: String?

    enum CodingKeys: String, CodingKey {
        case code
        case quantity
        case targetLocationId = "target_location_id"
        case note
    }
}

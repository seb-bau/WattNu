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
    let erpId: Int
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
    }
    
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else {
            return nil
        }

        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var displayTitle: String {
        title?.isEmpty == false ? title! : "Auftrag \(erpId)"
    }

    var displayNumber: String {
        erpIdNum ?? code ?? "\(erpId)"
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

    var localStatusLabel: String {
        switch localStatus {
        case "open":
            return "Offen"
        case "in_progress":
            return "In Arbeit"
        case "done":
            return "Abgeschlossen"
        case "deleted":
            return "Gelöscht"
        default:
            return localStatus
        }
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

struct InventoryItem: Codable, Identifiable, Equatable, Hashable {
    let id: Int
    let itemNumber: String
    let name: String
    let unit: String
    let ean: String?
    let qrCodePayload: String
    let stockQuantity: Double
    let reorderLevel: Double

    enum CodingKeys: String, CodingKey {
        case id
        case itemNumber = "item_number"
        case name
        case unit
        case ean
        case qrCodePayload = "qr_code_payload"
        case stockQuantity = "stock_quantity"
        case reorderLevel = "reorder_level"
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
    let expectedMaterials: [ExpectedMaterial]?

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case title
        case suggestedMinutes = "suggested_minutes"
        case expectedMaterials = "expected_materials"
    }

    var expectedMaterialsValue: [ExpectedMaterial] {
        expectedMaterials ?? []
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
    let deviationReason: String?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case code
        case quantity
        case taskTemplateId = "task_template_id"
        case usageStatus = "usage_status"
        case source
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

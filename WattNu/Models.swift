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
    let timeComponentsEnabled: Bool?
    let showServiceTargetTimes: Bool?
    let showWorkTimeTargetTimes: Bool?

    enum CodingKeys: String, CodingKey {
        case passwordLoginEnabled = "password_login_enabled"
        case microsoft
        case timeComponentsEnabled = "time_components_enabled"
        case showServiceTargetTimes = "show_service_target_times"
        case showWorkTimeTargetTimes = "show_work_time_target_times"
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

enum AppPushEvent: String, CaseIterable, Identifiable {
    case newCommission = "new_commission"
    case appointmentAccepted = "appointment_accepted"
    case appointmentRejected = "appointment_rejected"
    case commissionPriorityRaised = "commission_priority_raised"
    case newProcessInfo = "new_process_info"
    case newSafetyInspection = "new_safety_inspection"
    case changedSafetyInspection = "changed_safety_inspection"
    case urgentSafetyDefect = "urgent_safety_defect"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newCommission:
            return "Neue Aufträge"
        case .appointmentAccepted:
            return "Termin angenommen"
        case .appointmentRejected:
            return "Termin abgelehnt"
        case .commissionPriorityRaised:
            return "Auftragspriorität erhöht"
        case .newProcessInfo:
            return "Neue Zusatzinformationen"
        case .newSafetyInspection:
            return "Neue Prüfaufträge"
        case .changedSafetyInspection:
            return "Geänderte Prüfaufträge"
        case .urgentSafetyDefect:
            return "Dringende Mängel"
        }
    }
}

struct PushPreferences: Codable, Equatable {
    let newCommissionEnabled: Bool
    let changedCommissionEnabled: Bool
    let events: [String: Bool]?

    enum CodingKeys: String, CodingKey {
        case newCommissionEnabled = "new_commission_enabled"
        case changedCommissionEnabled = "changed_commission_enabled"
        case events
    }

    func isEnabled(_ event: AppPushEvent) -> Bool {
        if let enabled = events?[event.rawValue] {
            return enabled
        }

        switch event {
        case .newCommission:
            return newCommissionEnabled
        case .appointmentAccepted, .appointmentRejected, .commissionPriorityRaised:
            return changedCommissionEnabled
        default:
            return true
        }
    }

    func updating(_ event: AppPushEvent, enabled: Bool) -> PushPreferences {
        var updatedEvents = events ?? [:]
        updatedEvents[event.rawValue] = enabled

        return PushPreferences(
            newCommissionEnabled: newCommissionEnabled,
            changedCommissionEnabled: changedCommissionEnabled,
            events: updatedEvents
        )
    }
}

struct PushPreferencesResponse: Decodable {
    let preferences: PushPreferences
}

struct AppointmentPreferences: Codable, Equatable {
    let calendarEmailEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case calendarEmailEnabled = "calendar_email_enabled"
    }
}

struct AppointmentPreferencesResponse: Decodable {
    let preferences: AppointmentPreferences
}

struct RelatedCommission: Codable, Identifiable, Equatable {
    let commission: Commission
    let relationship: String
    let directAccess: Bool

    var id: Int { commission.id }

    enum CodingKeys: String, CodingKey {
        case commission, relationship
        case directAccess = "direct_access"
    }

    var relationshipLabel: String {
        switch relationship {
        case "license_agreement": return "Derselbe Vertrag"
        case "use_unit": return "Dieselbe Wohnung"
        default: return "Dasselbe Gebäude"
        }
    }

    var relationshipIcon: String {
        switch relationship {
        case "license_agreement": return "doc.text"
        case "use_unit": return "door.left.hand.closed"
        default: return "building.2"
        }
    }
}

struct RelatedCommissionsResponse: Codable, Equatable {
    let items: [RelatedCommission]
    let total: Int
    let page: Int
    let pages: Int
    let counts: [String: Int]
}

struct PushPreferencesUpdateRequest: Encodable {
    let events: [String: Bool]
}

struct PushDeviceRegistrationRequest: Encodable {
    let installationId: String
    let deviceToken: String
    let platform: String
    let appVersion: String?
    let deviceName: String?

    enum CodingKeys: String, CodingKey {
        case installationId = "installation_id"
        case deviceToken = "device_token"
        case platform
        case appVersion = "app_version"
        case deviceName = "device_name"
    }
}

struct PushDeviceRegistrationResponse: Decodable {
    let device: PushDeviceInfo
}

struct PushDeviceInfo: Decodable {
    let id: Int
    let installationId: String
    let active: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case installationId = "installation_id"
        case active
    }
}

struct PushDeviceUnregistrationRequest: Encodable {
    let installationId: String

    enum CodingKeys: String, CodingKey {
        case installationId = "installation_id"
    }
}

struct PushDeviceUnregistrationResponse: Decodable {
    let unregistered: Bool
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
    let isHighPriority: Bool?
    let craftsmanErpId: Int?
    let useUnitId: Int?
    let licenseAgreementId: Int?
    let objectType: String?
    let economicUnitIdNum: String?
    let economicUnitName: String?
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
    let acceptedAppointmentHasTime: Bool?
    let acceptedAppointmentIsManual: Bool?

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
        case isHighPriority = "is_high_priority"
        case craftsmanErpId = "craftsman_erp_id"
        case useUnitId = "use_unit_id"
        case licenseAgreementId = "license_agreement_id"
        case objectType = "object_type"
        case economicUnitIdNum = "economic_unit_idnum"
        case economicUnitName = "economic_unit_name"
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
        case acceptedAppointmentHasTime = "accepted_appointment_has_time"
        case acceptedAppointmentIsManual = "accepted_appointment_is_manual"
    }
    
    var isHighPriorityValue: Bool {
        isHighPriority ?? false
    }

    var isEconomicUnitOrder: Bool {
        objectType == "economic_unit"
    }

    var economicUnitDisplayName: String? {
        let parts = [economicUnitIdNum, economicUnitName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var objectDisplayTitle: String {
        if isEconomicUnitOrder {
            return "Gesamte Wirtschaftseinheit"
        }
        for value in [apartmentAddress, apartmentLocation] {
            if let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                return text
            }
        }
        return displayTitle
    }

    var addressLabel: String {
        isEconomicUnitOrder ? "Orientierungsadresse" : "Adresse"
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
    
    func matchingTimeTasks(
        in tasks: [TimeTask]
    ) -> [TimeTask] {
        let serviceCatalogIds = Set(
            positions.compactMap {
                $0.serviceCatalogId
            }
        )
        let positionCodes = Set(
            positions.compactMap {
                $0.code?
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .lowercased()
            }
        )

        return tasks.filter { task in
            if let serviceCatalogId =
                task.serviceCatalogId,
               serviceCatalogIds.contains(
                serviceCatalogId
               ) {
                return true
            }

            let values = [
                task.code,
                task.erpIdNum ?? ""
            ].map {
                $0.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .lowercased()
            }

            return values.contains {
                positionCodes.contains($0)
            }
        }
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
    let contactId: String?
    let useUnitId: Int?
    let useUnitNumber: String?
    let useUnitLocation: String?
    let useUnitAddress: String?
    let licenseAgreementId: Int?
    let contractStart: String?
    let contractEnd: String?
    let isFutureContract: Bool?
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
        if let contactId, !contactId.isEmpty {
            return contactId
        }
        if useUnitId != nil || licenseAgreementId != nil {
            let identity = personId.map(String.init) ?? name ?? email ?? phone ?? "unknown"
            return "\(useUnitId.map(String.init) ?? ""):\(licenseAgreementId.map(String.init) ?? ""):\(identity)"
        }
        if let personId {
            return "\(personId)"
        }
        return name ?? UUID().uuidString
    }

    enum CodingKeys: String, CodingKey {
        case contactId = "contact_id"
        case useUnitId = "use_unit_id"
        case useUnitNumber = "use_unit_number"
        case useUnitLocation = "use_unit_location"
        case useUnitAddress = "use_unit_address"
        case licenseAgreementId = "license_agreement_id"
        case contractStart = "contract_start"
        case contractEnd = "contract_end"
        case isFutureContract = "is_future_contract"
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

struct InventoryItemGroup: Codable, Identifiable, Equatable, Hashable {
    let id: Int
    let code: String
    let name: String
    let serialNumberRequired: Bool
    let active: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case name
        case serialNumberRequired = "serial_number_required"
        case active
    }
}

struct InventoryItemType: Codable, Identifiable, Equatable, Hashable {
    let id: Int
    let code: String
    let name: String
    let unit: String
    let active: Bool
    let group: InventoryItemGroup
}

struct InventoryStock: Codable, Identifiable, Equatable, Hashable {
    let id: Int
    let quantity: Double
    let location: InventoryLocation
}

struct InventoryItem: Codable, Identifiable, Equatable, Hashable {
    let id: Int
    let itemType: InventoryItemType?
    let itemNumber: String
    let name: String
    let unit: String
    let ean: String?
    let qrCodePayload: String
    let stockQuantity: Double
    let reorderLevel: Double
    let barcodes: [String]?
    let stocks: [InventoryStock]?
    let serialNumberRequired: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case itemType = "item_type"
        case itemNumber = "item_number"
        case name
        case unit
        case ean
        case qrCodePayload = "qr_code_payload"
        case stockQuantity = "stock_quantity"
        case reorderLevel = "reorder_level"
        case barcodes
        case stocks
        case serialNumberRequired = "serial_number_required"
    }

    var stocksValue: [InventoryStock] {
        stocks ?? []
    }

    var serialNumberRequiredValue: Bool {
        serialNumberRequired ?? false
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
    let serialNumber: String?

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
        case serialNumber = "serial_number"
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

extension TimeTask {
    var craftTitle: String {
        for candidate in [craftActivity?.name, craftActivity?.code] {
            if let value = candidate?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ), !value.isEmpty {
                return value
            }
        }

        return "Ohne Gewerk"
    }

    var displayTitle: String {
        "\(craftTitle) · \(title)"
    }

    static func sortedForFreeTime(_ tasks: [TimeTask]) -> [TimeTask] {
        tasks.sorted { left, right in
            for (leftValue, rightValue) in [
                (left.craftTitle, right.craftTitle),
                (left.title, right.title),
                (left.code, right.code)
            ] {
                let comparison = leftValue.compare(
                    rightValue,
                    options: [.caseInsensitive, .diacriticInsensitive, .numeric],
                    locale: Locale(identifier: "de_DE")
                )

                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
            }

            return left.id < right.id
        }
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
    let item: InventoryItem?
    let itemType: InventoryItemType?
    let quantity: Double
    let required: Bool
    let note: String?

    enum CodingKeys: String, CodingKey {
        case id
        case taskTemplateId = "task_template_id"
        case item
        case itemType = "item_type"
        case quantity
        case required
        case note
    }

    var displayName: String {
        itemType?.name
        ?? item?.name
        ?? "Unbekanntes Material"
    }

    var unit: String {
        itemType?.unit
        ?? item?.unit
        ?? ""
    }

    var detailText: String {
        if let item {
            return item.itemNumber
        }

        if let itemType {
            return "\(itemType.group.name) · beliebiges Modell"
        }

        return ""
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
    let serviceDate: String?
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
        case serviceDate = "service_date"
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

struct SimpleCommissionCreateOptions: Decodable {
    let canCreate: Bool
    let notifyTenantsDefault: Bool?
    let defaultCraftsmanUserId: Int?
    let commissionTypes: [CommissionTypeOption]
    let craftActivities: [SimpleCommissionCraftOption]
    let craftsmen: [SimpleCommissionCraftsmanOption]

    enum CodingKeys: String, CodingKey {
        case canCreate = "can_create"
        case notifyTenantsDefault = "notify_tenants_default"
        case defaultCraftsmanUserId = "default_craftsman_user_id"
        case commissionTypes = "commission_types"
        case craftActivities = "craft_activities"
        case craftsmen
    }
}

struct SimpleCommissionCraftOption: Decodable, Identifiable {
    let id: Int
    let name: String
    let fallbackAvailable: Bool
    let commissionTypeIds: [Int]

    enum CodingKeys: String, CodingKey {
        case id, name
        case fallbackAvailable = "fallback_available"
        case commissionTypeIds = "commission_type_ids"
    }
}

struct SimpleCommissionCraftsmanOption: Decodable, Identifiable {
    let id: Int
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

struct SimpleCommissionCreateRequest: Encodable {
    let clientRequestId: String
    let objectType: String
    let objectId: Int
    let commissionTypeId: Int
    let craftActivityId: Int
    let craftsmanUserId: Int
    let title: String
    let commissionText: String
    let contactPerson: String?
    let executionDate: String?
    let notifyTenants: Bool

    enum CodingKeys: String, CodingKey {
        case clientRequestId = "client_request_id"
        case objectType = "object_type"
        case objectId = "object_id"
        case commissionTypeId = "commission_type_id"
        case craftActivityId = "craft_activity_id"
        case craftsmanUserId = "craftsman_user_id"
        case title
        case commissionText = "commission_text"
        case contactPerson = "contact_person"
        case executionDate = "execution_date"
        case notifyTenants = "notify_tenants"
    }
}

struct CommissionCreateOptions: Decodable {
    let canCreate: Bool
    let notifyTenantsDefault: Bool?
    let companyCodes: [CompanyCodeOption]
    let commissionTypes: [CommissionTypeOption]

    enum CodingKeys: String, CodingKey {
        case canCreate = "can_create"
        case notifyTenantsDefault = "notify_tenants_default"
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

struct CommissionObjectChoice: Decodable, Identifiable, Hashable {
    let objectType: String
    let objectId: Int
    let label: String
    let tenantName: String?
    let isVacancy: Bool
    let companyCode: CommissionObjectCompanyCode
    let economicUnit: CommissionObjectEconomicUnit
    let building: CommissionObjectBuilding?
    let useUnit: CommissionObjectUseUnit?
    let licenseAgreement: CommissionObjectLicenseAgreement?

    var id: String {
        "\(objectType):\(objectId)"
    }

    enum CodingKeys: String, CodingKey {
        case objectType = "object_type"
        case objectId = "object_id"
        case label
        case tenantName = "tenant_name"
        case isVacancy = "is_vacancy"
        case companyCode = "company_code"
        case economicUnit = "economic_unit"
        case building
        case useUnit = "use_unit"
        case licenseAgreement = "license_agreement"
    }
}

struct CommissionObjectCompanyCode: Decodable, Hashable {
    let erpId: Int?
    let code: String?

    enum CodingKeys: String, CodingKey {
        case erpId = "erp_id"
        case code
    }
}

struct CommissionObjectEconomicUnit: Decodable, Hashable {
    let erpId: Int
    let idNum: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case erpId = "erp_id"
        case idNum = "id_num"
        case name
    }
}

struct CommissionObjectBuilding: Decodable, Hashable {
    let erpId: Int
    let idNum: String?
    let address: String?

    enum CodingKeys: String, CodingKey {
        case erpId = "erp_id"
        case idNum = "id_num"
        case address
    }
}

struct CommissionObjectUseUnit: Decodable, Hashable {
    let erpId: Int
    let idNum: String?
    let floor: String?
    let position: String?
    let description: String?
    let address: String?

    enum CodingKeys: String, CodingKey {
        case erpId = "erp_id"
        case idNum = "id_num"
        case floor
        case position
        case description
        case address
    }
}

struct CommissionObjectLicenseAgreement: Decodable, Hashable {
    let erpId: Int
    let idNum: String?

    enum CodingKeys: String, CodingKey {
        case erpId = "erp_id"
        case idNum = "id_num"
    }
}

struct CommissionCreateRequest: Encodable {
    let objectType: String
    let objectId: Int
    let commissionTypeId: Int
    let title: String?
    let damageLocation: String?
    let contactPerson: String?
    let executionFrom: String?
    let executionTo: String?
    let positions: [CommissionPositionRequest]
    let notifyTenants: Bool

    enum CodingKeys: String, CodingKey {
        case objectType = "object_type"
        case objectId = "object_id"
        case commissionTypeId = "commission_type_id"
        case title
        case damageLocation = "damage_location"
        case contactPerson = "contact_person"
        case executionFrom = "execution_from"
        case executionTo = "execution_to"
        case positions
        case notifyTenants = "notify_tenants"
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
    let serialNumber: String?
    let deviationReason: String?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case code
        case quantity
        case taskTemplateId = "task_template_id"
        case usageStatus = "usage_status"
        case source
        case locationId = "location_id"
        case serialNumber = "serial_number"
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
    let serviceDate: String
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
        case serviceDate = "service_date"
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

struct MyTimeDay: Decodable {
    let date: String
    let expectedMinutes: Int?
    let recordedMinutes: Int
    let differenceMinutes: Int?
    let status: String
    let profile: WorkTimeProfileSummary?
    let targetOverride: WorkTimeTargetOverrideSummary?
    let items: [MyTimeEntry]

    enum CodingKeys: String, CodingKey {
        case date
        case expectedMinutes = "expected_minutes"
        case recordedMinutes = "recorded_minutes"
        case differenceMinutes = "difference_minutes"
        case status
        case profile
        case targetOverride = "target_override"
        case items
    }
}

struct WorkTimeProfileSummary: Decodable, Hashable {
    let id: Int
    let name: String
}

struct WorkTimeTargetOverrideSummary: Decodable {
    let targetMinutes: Int
    let reason: String

    enum CodingKeys: String, CodingKey {
        case targetMinutes = "target_minutes"
        case reason
    }
}

struct MyTimeEntry: Decodable, Identifiable {
    let id: Int
    let taskTemplate: TimeTask?
    let minutes: Int
    let note: String?
    let serviceDate: String
    let commission: MyTimeCommission?
    let isFreeTime: Bool
    let canEdit: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case taskTemplate = "task_template"
        case minutes
        case note
        case serviceDate = "service_date"
        case commission
        case isFreeTime = "is_free_time"
        case canEdit = "can_edit"
    }
}

struct MyTimeCommission: Decodable, Hashable {
    let id: Int
    let number: String
    let title: String
}

struct FreeTimeEntryRequest: Encodable {
    let taskTemplateId: Int
    let serviceDate: String
    let minutes: Int
    let note: String?

    enum CodingKeys: String, CodingKey {
        case taskTemplateId = "task_template_id"
        case serviceDate = "service_date"
        case minutes
        case note
    }
}

struct EmptyRequest: Encodable {
}

struct EmptyResponse: Decodable {
}

struct CommissionAttachment: Codable, Identifiable, Equatable {
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

struct CommissionPhoto: Codable, Identifiable, Equatable {
    let id: Int
    let commissionId: Int
    let source: String
    let context: String?
    let externalId: String?
    let externalDocumentId: String?
    let externalEntityName: String?
    let externalEntityId: Int?
    let pictureTypeId: Int?
    let pictureTypeName: String?
    let erpSyncState: String?
    let erpSyncMessage: String?
    let erpSyncedAt: String?
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
        case context
        case externalId = "external_id"
        case externalDocumentId = "external_document_id"
        case externalEntityName = "external_entity_name"
        case externalEntityId = "external_entity_id"
        case pictureTypeId = "picture_type_id"
        case pictureTypeName = "picture_type_name"
        case erpSyncState = "erp_sync_state"
        case erpSyncMessage = "erp_sync_message"
        case erpSyncedAt = "erp_synced_at"
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

    var entityLabel: String {
        switch externalEntityName?
            .lowercased() {
        case "building":
            return "Gebäude"
        case "useunit":
            return "Wohnung"
        default:
            return "Bestandsobjekt"
        }
    }

    var displayCaption: String {
        if let caption,
           !caption.isEmpty {
            return caption
        }

        if let pictureTypeName,
           !pictureTypeName.isEmpty {
            return pictureTypeName
        }

        return entityLabel
    }
    
    var canDeleteValue: Bool {
        erpSyncState != "synced"
            || externalId == nil
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

struct AppointmentWindowConfiguration: Decodable {
    let items: [AppointmentWindow]
    let customTimesEnabled: Bool
    let customTimeDurationMinutes: Int

    enum CodingKeys: String, CodingKey {
        case items
        case customTimesEnabled = "custom_times_enabled"
        case customTimeDurationMinutes = "custom_time_duration_minutes"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        items = try container.decode(
            [AppointmentWindow].self,
            forKey: .items
        )
        customTimesEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .customTimesEnabled
        ) ?? false

        let durationMinutes = try container.decodeIfPresent(
            Int.self,
            forKey: .customTimeDurationMinutes
        ) ?? 60

        customTimeDurationMinutes = max(
            durationMinutes,
            1
        )
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

        if windowId == nil {
            return "\(dateText) · Beginn \(startTime) Uhr"
        }

        return "\(dateText) · \(startTime)–\(endTime) Uhr"
    }
}

struct CommissionAppointmentRequest: Codable, Identifiable, Equatable {
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
    let windowId: Int?
    let startTime: String?

    enum CodingKeys: String, CodingKey {
        case date
        case windowId = "window_id"
        case startTime = "start_time"
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

struct ManualAppointmentCreatePayload: Encodable {
    let date: String
    let time: String?
    let comment: String?
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

struct CommissionCompletionCheck: Decodable {
    let requiresConfirmation: Bool
    let message: String?

    enum CodingKeys: String, CodingKey {
        case requiresConfirmation =
            "requires_confirmation"
        case message
    }
}

struct CommissionCompletionRequest: Encodable {
    let completed: Bool
    let tenantCharge: Bool
    let reason: String?
    let confirmMissingMaterial: Bool

    enum CodingKeys: String, CodingKey {
        case completed
        case tenantCharge = "tenant_charge"
        case reason
        case confirmMissingMaterial =
            "confirm_missing_material"
    }
}

struct CommissionRejectionRequest: Encodable {
    let reason: String
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

struct SafetyInspectionJob: Codable, Identifiable, Hashable {
    let id: Int
    let publicId: String
    var status: String
    let periodKey: String
    let periodStart: String
    let periodEnd: String
    let dueFrom: String
    let dueTo: String
    let warningOn: String
    let missedOn: String
    let isDue: Bool
    let isOverdue: Bool
    var isTerminal: Bool
    var canEdit: Bool
    let group: SafetyInspectionGroupSummary
    let template: SafetyInspectionTemplateSummary
    let department: SafetyInspectionDepartmentSummary?
    let assignedUser: AppUser?
    let object: SafetyInspectionObjectSummary
    var progress: SafetyInspectionProgress
    var overallNote: String?
    let startedAt: String?
    let completedAt: String?
    let completedBy: AppUser?
    let createdAt: String?
    let updatedAt: String?
    var results: [SafetyInspectionResult]?
    var visit: SafetyInspectionVisit? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case publicId = "public_id"
        case status
        case periodKey = "period_key"
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case dueFrom = "due_from"
        case dueTo = "due_to"
        case warningOn = "warning_on"
        case missedOn = "missed_on"
        case isDue = "is_due"
        case isOverdue = "is_overdue"
        case isTerminal = "is_terminal"
        case canEdit = "can_edit"
        case group
        case template
        case department
        case assignedUser = "assigned_user"
        case object
        case progress
        case overallNote = "overall_note"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case completedBy = "completed_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case results
        case visit
    }

    var statusLabel: String {
        switch status {
        case "planned":
            return "Geplant"
        case "in_progress":
            return "In Bearbeitung"
        case "completed":
            return "Abgeschlossen"
        case "completed_with_defects":
            return "Abgeschlossen mit Mängeln"
        case "missed":
            return "Abgelaufen"
        case "canceled":
            return "Abgebrochen"
        default:
            return status
        }
    }

    var objectTitle: String {
        if let address = object.address,
           !address.isEmpty {
            return address
        }

        if let location = object.location,
           !location.isEmpty {
            return location
        }

        return group.name
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude = object.latitude,
              let longitude = object.longitude else {
            return nil
        }

        return CLLocationCoordinate2D(
            latitude: latitude,
            longitude: longitude
        )
    }
}

struct SafetyInspectionGroupSummary: Codable, Hashable {
    let id: Int
    let name: String
}

struct SafetyInspectionTemplateSummary: Codable, Hashable {
    let id: Int
    let name: String
    let version: Int
}

struct SafetyInspectionDepartmentSummary: Codable, Hashable {
    let id: Int
    let erpId: Int
    let name: String

    enum CodingKeys: String, CodingKey {
        case id
        case erpId = "erp_id"
        case name
    }
}

struct SafetyInspectionObjectSummary: Codable, Hashable {
    let level: String
    let erpId: Int
    let address: String?
    let location: String?
    let companyCodeErpId: Int?
    let companyCodeCode: String?
    let economicUnitErpId: Int
    let economicUnitIdnum: String?
    let economicUnitName: String?
    let buildingErpId: Int?
    let buildingIdnum: String?
    let useUnitErpId: Int?
    let useUnitIdnum: String?
    let latitude: Double?
    let longitude: Double?
    let hasCoordinates: Bool

    enum CodingKeys: String, CodingKey {
        case level
        case erpId = "erp_id"
        case address
        case location
        case companyCodeErpId = "company_code_erp_id"
        case companyCodeCode = "company_code_code"
        case economicUnitErpId = "economic_unit_erp_id"
        case economicUnitIdnum = "economic_unit_idnum"
        case economicUnitName = "economic_unit_name"
        case buildingErpId = "building_erp_id"
        case buildingIdnum = "building_idnum"
        case useUnitErpId = "use_unit_erp_id"
        case useUnitIdnum = "use_unit_idnum"
        case latitude
        case longitude
        case hasCoordinates = "has_coordinates"
    }

    var levelLabel: String {
        switch level {
        case "economic_unit":
            return "Wirtschaftseinheit"
        case "building":
            return "Gebäude"
        case "use_unit":
            return "Nutzungseinheit"
        default:
            return level
        }
    }
}

struct SafetyInspectionProgress: Codable, Hashable {
    let resultCount: Int
    var checkedCount: Int
    let defectCount: Int
    var photoCount: Int

    enum CodingKeys: String, CodingKey {
        case resultCount = "result_count"
        case checkedCount = "checked_count"
        case defectCount = "defect_count"
        case photoCount = "photo_count"
    }
}

struct SafetyInspectionResult: Codable, Identifiable, Hashable {
    let id: Int
    let publicId: String
    let positionIndex: Int
    let title: String
    let catalogPosition: String?
    let sectionKey: String?
    let sectionTitle: String?
    let description: String?
    let helpText: String?
    let required: Bool
    let allowNotPresent: Bool
    let photoRequirements: SafetyInspectionPhotoRequirements
    var state: String
    var note: String?
    var immediateAction: String?
    var version: Int
    let checkedAt: String?
    let checkedBy: AppUser?
    var photos: [SafetyInspectionPhoto]
    let defect: SafetyInspectionDefect?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case publicId = "public_id"
        case positionIndex = "position_index"
        case title
        case catalogPosition = "catalog_position"
        case sectionKey = "section_key"
        case sectionTitle = "section_title"
        case description
        case helpText = "help_text"
        case required
        case allowNotPresent = "allow_not_present"
        case photoRequirements = "photo_requirements"
        case state
        case note
        case immediateAction = "immediate_action"
        case version
        case checkedAt = "checked_at"
        case checkedBy = "checked_by"
        case photos
        case defect
        case updatedAt = "updated_at"
    }

    var stateLabel: String {
        switch state {
        case "not_checked":
            return "Nicht geprüft"
        case "no_defect":
            return "Kein Mangel"
        case "not_present":
            return "Nicht vorhanden"
        case "defect_info", "defect_urgent":
            return "Mangel"
        default:
            return state
        }
    }
}

struct SafetyInspectionPhotoRequirements: Codable, Hashable {
    let noDefect: Bool
    let notPresent: Bool
    let defectInfo: Bool
    let defectUrgent: Bool

    enum CodingKeys: String, CodingKey {
        case noDefect = "no_defect"
        case notPresent = "not_present"
        case defectInfo = "defect_info"
        case defectUrgent = "defect_urgent"
    }
}

struct SafetyInspectionPhoto: Codable, Identifiable, Hashable {
    let id: Int
    let publicId: String
    let source: String
    let originalFilename: String
    let mimeType: String
    let sizeBytes: Int
    let caption: String?
    let capturedAt: String?
    let createdAt: String?
    let updatedAt: String?
    let uploadedBy: AppUser
    let contentPath: String
    let thumbnailPath: String

    enum CodingKeys: String, CodingKey {
        case id
        case publicId = "public_id"
        case source
        case originalFilename = "original_filename"
        case mimeType = "mime_type"
        case sizeBytes = "size_bytes"
        case caption
        case capturedAt = "captured_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case uploadedBy = "uploaded_by"
        case contentPath = "content_path"
        case thumbnailPath = "thumbnail_path"
    }

    var sourceLabel: String {
        switch source {
        case "camera":
            return "Kamera"
        case "gallery":
            return "Fotomediathek"
        case "web":
            return "Web"
        default:
            return source
        }
    }
}

struct SafetyInspectionDefect: Codable, Identifiable, Hashable {
    let id: Int
    let publicId: String
    let severity: String
    let status: String
    let description: String
    let immediateAction: String?
    let reviewNote: String?
    let createdAt: String?
    let commissionIds: [Int]

    enum CodingKeys: String, CodingKey {
        case id
        case publicId = "public_id"
        case severity
        case status
        case description
        case immediateAction = "immediate_action"
        case reviewNote = "review_note"
        case createdAt = "created_at"
        case commissionIds = "commission_ids"
    }
}

struct SafetyInspectionResultUpdateRequest: Encodable {
    let state: String
    let note: String?
    let immediateAction: String?
    let version: Int

    enum CodingKeys: String, CodingKey {
        case state
        case note
        case immediateAction = "immediate_action"
        case version
    }
}

struct SafetyInspectionCompletionRequest: Encodable {
    let overallNote: String?

    enum CodingKeys: String, CodingKey {
        case overallNote = "overall_note"
    }
}

struct SafetyInspectionPhotoUploadResponse: Decodable {
    let item: SafetyInspectionPhoto
    let duplicate: Bool
}

extension SafetyInspectionResult {
    func requiresNote(for state: String) -> Bool {
        ["not_present", "defect_info", "defect_urgent"].contains(state)
    }

    func requiresPhoto(for state: String) -> Bool {
        switch state {
        case "no_defect":
            return photoRequirements.noDefect
        case "not_present":
            return photoRequirements.notPresent
        case "defect_info", "defect_urgent":
            return photoRequirements.defectInfo || photoRequirements.defectUrgent
        default:
            return false
        }
    }

    func missingRequirements(
        for state: String,
        note: String?
    ) -> [String] {
        switch state {
        case "not_checked":
            return required ? ["Bewertung fehlt."] : []
        case "no_defect", "not_present", "defect_info", "defect_urgent":
            break
        default:
            return ["Bewertung ist ungültig."]
        }

        var issues: [String] = []

        if requiresNote(for: state),
           (note ?? "").trimmingCharacters(
                in: .whitespacesAndNewlines
           ).isEmpty {
            issues.append(
                state == "not_present"
                    ? "Begründung fehlt."
                    : "Mangelbeschreibung fehlt."
            )
        }

        if requiresPhoto(for: state) && photos.isEmpty {
            issues.append("Pflichtfoto fehlt.")
        }

        return issues
    }

    var completionIssues: [String] {
        missingRequirements(for: state, note: note)
    }
}

struct SafetyInspectionVisit: Codable, Hashable {
    let blocked: Bool
    let note: String?
    let followUpOn: String?
    let occurredAt: String
    let operationId: String
    let groupId: String

    enum CodingKeys: String, CodingKey {
        case blocked, note
        case followUpOn = "follow_up_on"
        case occurredAt = "occurred_at"
        case operationId = "operation_id"
        case groupId = "group_id"
    }
}

extension SafetyInspectionJob {
    var hasVisitTask: Bool {
        isOpenInspection
            && (visit?.blocked == true || visit?.followUpOn != nil)
    }

    var visitLabel: String? {
        guard hasVisitTask, let visit else { return nil }

        var parts: [String] = []

        if visit.blocked {
            parts.append("Kein Zugang")
        }

        if let date = visit.followUpOn {
            parts.append(
                "Wiedervorlage \(Formatters.dateText(date))"
            )
        }

        return parts.joined(separator: " · ")
    }
}

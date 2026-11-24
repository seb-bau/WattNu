import Foundation
import Testing
@testable import WattNu

@MainActor
struct CommissionObjectSearchTests {
    static let tenant: [String: Any] = [
        "object_type": "license_agreement", "object_id": 4, "label": "Erika Muster",
        "tenant_name": "Erika Muster", "is_vacancy": false, "company_code": ["erp_id": 77, "code": "BW"],
        "economic_unit": ["erp_id": 1001, "object_id": 1, "id_num": "WE-1", "name": "Wohnanlage"],
        "building": ["erp_id": 2002, "object_id": 2, "id_num": "GE-2", "address": "Musterstraße 12"],
        "use_unit": ["erp_id": 3003, "id_num": "NE-3", "description": "2. OG links"],
        "license_agreement": ["erp_id": 4004, "id_num": "MV-4"],
    ]

    @Test func tenantSearchShowsOnlyItsParentsAndItsOwnNumber() throws {
        let data = try CommissionOfflineJSON.data(Self.tenant)
        let contract = try JSONDecoder().decode(CommissionObjectChoice.self, from: data)
        let rows = CommissionObjectSearchRow.grouped([contract])
        #expect(rows.map(\.level) == [.economicUnit, .building, .agreement])
        #expect(rows.map { $0.selection?.objectId } == [1, 2, 4])
        #expect(rows.map { $0.level.indentation } == [0, 8, 16])
        #expect(rows.map(\.details) == ["Wirtschaftseinheit", "Gebäude", "Mietvertrag · MV-4 · 2. OG links"])
        #expect(rows[1].selection?.tenantName == nil)
        #expect(rows[0].selection?.building == nil)
    }

    @Test func directBuildingUsesItsOwnNumberAndKeepsOneParentRow() throws {
        let data = try CommissionOfflineJSON.data(Self.tenant)
        let contract = try JSONDecoder().decode(CommissionObjectChoice.self, from: data)
        let building = try #require(contract.parentChoice(at: .building))
        let rows = CommissionObjectSearchRow.grouped([contract, building, contract])
        #expect(rows.map(\.level) == [.economicUnit, .building, .agreement])
        #expect(rows[1].details == "Gebäude · GE-2")
        #expect(rows[0].details == "Wirtschaftseinheit")
    }
}

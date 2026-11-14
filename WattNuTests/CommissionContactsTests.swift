import Foundation
import Testing
@testable import WattNu

@MainActor
struct CommissionContactsTests {
    private func contact(_ fields: [String: Any] = [:]) throws -> CommissionContactItem {
        let payload: [String: Any] = ["person_id": 50, "name": "Mieter", "additional_numbers": [String]()]
            .merging(fields) { _, value in value }
        return try JSONDecoder().decode(CommissionContactItem.self, from: JSONSerialization.data(withJSONObject: payload))
    }

    @Test func legacyContactPayloadsRemainReadableWithoutApartmentMetadata() throws {
        let item = try contact()
        #expect(item.id == "50")
        #expect(item.useUnitId == nil)
        #expect(item.isFutureContract == nil)
        let groups = CommissionContactGroup.groups(from: [item])
        #expect(groups.count == 1)
        #expect(groups.first?.title == nil)
        #expect(groups.first?.contacts.first?.id == item.id)
    }

    @Test func buildingContactsAreGroupedByApartmentAndSortedByApartmentNumber() throws {
        let upper = try contact(["use_unit_id": 10, "use_unit_number": "10", "use_unit_location": "2. OG · rechts", "license_agreement_id": 100])
        let lower = try contact(["use_unit_id": 2, "use_unit_number": "2", "use_unit_location": "EG · links", "license_agreement_id": 200])
        let coTenant = try contact(["person_id": 51, "use_unit_id": 2, "use_unit_number": "2", "use_unit_location": "EG · links", "license_agreement_id": 200])

        let groups = CommissionContactGroup.groups(from: [upper, lower, coTenant])

        #expect(groups.map(\.title) == ["Wohnung 2", "Wohnung 10"])
        #expect(groups.map(\.location) == ["EG · links", "2. OG · rechts"])
        #expect(groups.map { $0.contacts.count } == [2, 1])
    }

    @Test func currentAndFutureContractsForTheSamePersonHaveDistinctStableIdentities() throws {
        let current = try contact(["use_unit_id": 2, "license_agreement_id": 200, "contract_start": "2020-01-01", "is_future_contract": false])
        let future = try contact(["use_unit_id": 2, "license_agreement_id": 201, "contract_start": "2030-01-01", "is_future_contract": true])
        let otherUnit = try contact(["use_unit_id": 3, "license_agreement_id": 200])

        #expect(Set([current.id, future.id, otherUnit.id]).count == 3)
        #expect(future.contractStart == "2030-01-01")
        #expect(future.isFutureContract == true)
        let groups = CommissionContactGroup.groups(from: [future, current])
        #expect(groups.first?.contacts.map(\.id) == [current.id, future.id])
    }

    @Test func backendContactIdentityIsUsedWhenProvided() throws {
        let item = try contact(["contact_id": "2:200:50", "use_unit_id": 2, "license_agreement_id": 200])
        #expect(item.id == "2:200:50")
        let encoded = try JSONEncoder().encode(item)
        let restored = try JSONDecoder().decode(CommissionContactItem.self, from: encoded)
        #expect(restored == item)
    }
}

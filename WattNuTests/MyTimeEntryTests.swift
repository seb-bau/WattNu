import Foundation
import Testing
@testable import WattNu

@MainActor
struct MyTimeEntryTests {
    @Test func decodesInspectionDestinationAndTitle() throws {
        let payload = """
        {
            "id": 1,
            "minutes": 35,
            "service_date": "2026-11-23",
            "is_free_time": false,
            "safety_inspection": {
                "id": 24,
                "title": "Spielplatzkontrolle",
                "object_address": "Beispielstraße 1",
                "protocol_id": 17
            }
        }
        """

        let entry = try JSONDecoder().decode(MyTimeEntry.self, from: Data(payload.utf8))
        let inspection = try #require(entry.safetyInspection)
        #expect(inspection.id == 24)
        #expect(inspection.title == "Spielplatzkontrolle")
        #expect(inspection.objectAddress == "Beispielstraße 1")
        #expect(entry.minutes == 35)
    }

    @Test func existingCommissionBookingDecodesWithoutInspectionFields() throws {
        let payload = """
        {
            "id": 2,
            "minutes": 10,
            "service_date": "2026-11-23",
            "is_free_time": false,
            "commission": { "id": 42, "number": "A-42", "title": "Auftrag" }
        }
        """

        let entry = try JSONDecoder().decode(MyTimeEntry.self, from: Data(payload.utf8))
        #expect(entry.safetyInspection == nil)
        #expect(entry.commission?.id == 42)
    }
}

import Foundation
import Testing
@testable import WattNu

struct CommissionContactInformationTests {
    private func commission(_ fields: [String: Any] = [:]) throws -> Commission {
        let payload: [String: Any] = ["id": 1, "local_status": "in_progress", "positions": []]
            .merging(fields) { _, value in value }
        return try JSONDecoder().decode(Commission.self, from: JSONSerialization.data(withJSONObject: payload))
    }

    @Test func legacyOrdersHaveNoContactInformationSections() throws {
        let item = try commission()
        #expect(item.reporterText == nil)
        #expect(item.otherAffectedText == nil)
    }

    @Test func emptyAndWhitespaceOnlyInformationDoesNotCreateASection() throws {
        let item = try commission(["reporter": " \n\t", "other_affected": ""])
        #expect(item.reporterText == nil)
        #expect(item.otherAffectedText == nil)
    }

    @Test func informationSurvivesOfflineEncodingAndKeepsEditedLineBreaks() throws {
        let item = try commission([
            "reporter": "Erika Beispiel\nTelefon: 02306 12345",
            "other_affected": "Mietvertrag: MV-2\nMax Beispiel\n-----\nEigener Hinweis",
        ])
        let restored = try JSONDecoder().decode(Commission.self, from: JSONEncoder().encode(item))
        #expect(restored.reporterText == item.reporter)
        #expect(restored.otherAffectedText == item.otherAffected)
        #expect(restored == item)
    }

    @Test func eitherSectionCanAppearIndependently() throws {
        let reporter = try commission(["reporter": "  Erika Beispiel  "])
        let affected = try commission(["other_affected": "  Mietvertrag: MV-2\n  "])
        #expect(reporter.reporterText == "Erika Beispiel")
        #expect(reporter.otherAffectedText == nil)
        #expect(affected.reporterText == nil)
        #expect(affected.otherAffectedText == "Mietvertrag: MV-2")
    }
}

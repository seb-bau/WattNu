import Foundation
import Testing
@testable import WattNu

@MainActor
struct TimeEntryPolicyTests {
    private func commission(status: String) throws -> Commission {
        let data = try CommissionOfflineJSON.data(["id": 1, "local_status": status, "positions": []])
        return try JSONDecoder().decode(Commission.self, from: data)
    }

    @Test func disabledLateRecordingBlocksAllCompletedStates() throws {
        for status in ["done", "awaiting_invoice", "tenant_charge_review"] {
            let item = try commission(status: status)
            #expect(!item.allowsNewTimeEntries(allowOnCompleted: false))
            #expect(item.allowsNewTimeEntries(allowOnCompleted: true))
        }
    }

    @Test func openAndReopenedCommissionsStillAllowTimeRecording() throws {
        for status in ["waiting_for_acceptance", "open", "in_progress", "completion_review"] {
            let item = try commission(status: status)
            #expect(item.allowsNewTimeEntries(allowOnCompleted: false))
        }
    }

    @Test func mobileConfigurationSupportsOlderBackendsAndTheDisabledPolicy() throws {
        let old = try JSONDecoder().decode(MobileConfig.self, from: Data("{\"password_login_enabled\":true}".utf8))
        #expect(old.allowTimeOnCompletedCommissions == nil)
        let updated = try JSONDecoder().decode(MobileConfig.self, from: Data("{\"password_login_enabled\":true,\"allow_time_on_completed_commissions\":false}".utf8))
        #expect(updated.allowTimeOnCompletedCommissions == false)
    }
}

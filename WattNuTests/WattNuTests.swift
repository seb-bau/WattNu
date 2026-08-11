//
//  WattNuTests.swift
//  WattNuTests
//
//  Created by Sebastian Bauhaus on 09.06.26.
//

import Testing
@testable import WattNu

struct WattNuTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }
    
    @Test func activeCommissionStatuses() {
        #expect(
            CommissionStatusFilter.activeLocalStatuses
            == Set([
                "waiting_for_acceptance",
                "open",
                "in_progress"
            ])
        )
    }

}

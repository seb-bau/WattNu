import Combine
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WattNu

@Suite(.serialized)
@MainActor
struct CommissionActivationRefreshTests {
    private func host(_ probe: RefreshProbe) -> UIWindow {
        let frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
            window.frame = frame
        } else {
            window = UIWindow(frame: frame)
        }
        window.rootViewController = UIHostingController(rootView: RefreshHarness(probe: probe))
        window.makeKeyAndVisible()
        window.rootViewController?.view.layoutIfNeeded()
        return window
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() {
                try await Task.sleep(for: .milliseconds(10))
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition())
    }

    private func select(_ section: CommissionDetailSection, in probe: RefreshProbe) async throws {
        guard probe.section != section else { return }
        let orderRequests = probe.orderRequests + 1
        let pageRequests = probe.initialRequests[section, default: 0] + 1
        probe.section = section
        try await waitUntil {
            probe.orderRequests == orderRequests && probe.initialRequests[section, default: 0] == pageRequests
        }
    }

    @Test func everyDirectedTabChangeReloadsTheOrderAndTheDestinationPage() async throws {
        let probe = RefreshProbe()
        let window = host(probe)
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitUntil { probe.orderRequests == 1 && probe.initialRequests[.order] == 1 }

        for source in CommissionDetailSection.allCases {
            for target in CommissionDetailSection.allCases where source != target {
                try await select(source, in: probe)
                let before = probe.initialRequests
                try await select(target, in: probe)
                for section in CommissionDetailSection.allCases where section != target {
                    #expect(probe.initialRequests[section, default: 0] == before[section, default: 0])
                }
            }
        }
    }

    @Test func manualRefreshReloadsOnlyTheVisiblePageAndKeepsItsDraft() async throws {
        let probe = RefreshProbe()
        let window = host(probe)
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitUntil { probe.orderRequests == 1 && probe.initialRequests[.order] == 1 }

        for section in CommissionDetailSection.allCases {
            try await select(section, in: probe)
            let draft = "Ungespeicherte Eingabe im Reiter \(section.rawValue)"
            probe.typedText = draft
            try await waitUntil { probe.visibleDraft == draft }
            let initialRequests = probe.initialRequests
            let refreshRequests = probe.refreshRequests
            let resourceRequests = probe.resourceRequests
            let orderRequests = probe.orderRequests + 1
            probe.revision += 1
            try await waitUntil {
                probe.orderRequests == orderRequests
                    && probe.refreshRequests[section, default: 0] == refreshRequests[section, default: 0] + 1
                    && ["photos", "attachments", "appointments", "related"].allSatisfy { resource in
                        probe.resourceRequests[resource, default: 0] == resourceRequests[resource, default: 0] + (section == .order ? 1 : 0)
                    }
            }
            #expect(probe.initialRequests == initialRequests)
            #expect(probe.refreshedDraft == draft)
            for resource in ["photos", "attachments", "appointments", "related"] {
                let expected = resourceRequests[resource, default: 0] + (section == .order ? 1 : 0)
                #expect(probe.resourceRequests[resource, default: 0] == expected)
            }
            for other in CommissionDetailSection.allCases where other != section {
                #expect(probe.refreshRequests[other, default: 0] == refreshRequests[other, default: 0])
            }
        }
    }

    @Test func anActivePageDoesNotReloadAfterThirtySeconds() async throws {
        let probe = RefreshProbe()
        let window = host(probe)
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitUntil { probe.orderRequests == 1 && probe.initialRequests[.order] == 1 }
        let initialRequests = probe.initialRequests
        try await Task.sleep(for: .seconds(31))
        #expect(probe.orderRequests == 1)
        #expect(probe.initialRequests == initialRequests)
        #expect(probe.refreshRequests.isEmpty)
    }

    @Test func returningToTheAppRefreshesWithoutReinitializingThePage() async throws {
        let probe = RefreshProbe()
        let window = host(probe)
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitUntil { probe.orderRequests == 1 && probe.initialRequests[.order] == 1 }
        probe.typedText = "Eingabe vor dem App-Wechsel"
        try await waitUntil { probe.visibleDraft == probe.typedText }
        probe.phase = .background
        try await waitUntil { probe.observedPhase == .background }
        probe.revision += 1
        try await Task.sleep(for: .milliseconds(50))
        #expect(probe.orderRequests == 1)
        #expect(probe.refreshRequests.isEmpty)

        probe.phase = .active
        try await waitUntil { probe.orderRequests == 2 && probe.refreshRequests[.order] == 1 }
        #expect(probe.initialRequests[.order] == 1)
        #expect(probe.refreshedDraft == probe.typedText)
    }
}

@MainActor
private final class RefreshProbe: ObservableObject {
    @Published var section: CommissionDetailSection = .order
    @Published var revision = 0
    @Published var phase: ScenePhase = .active
    @Published var typedText = ""
    var observedPhase: ScenePhase = .active
    var orderRequests = 0
    var initialRequests: [CommissionDetailSection: Int] = [:]
    var refreshRequests: [CommissionDetailSection: Int] = [:]
    var resourceRequests: [String: Int] = [:]
    var visibleDraft = ""
    var refreshedDraft = ""
}

private struct RefreshHarness: View {
    @ObservedObject var probe: RefreshProbe

    var body: some View {
        Group {
            switch probe.section {
            case .order:
                VStack {
                    RefreshPage(probe: probe, section: .order)
                    ForEach(["photos", "attachments", "appointments", "related"], id: \.self) { resource in
                        Text("Auftragsbereich")
                            .refreshOnActivation(id: resource) {
                                probe.resourceRequests[resource, default: 0] += 1
                            }
                    }
                }
            case .photos:
                RefreshPage(probe: probe, section: .photos)
            case .materials:
                RefreshPage(probe: probe, section: .materials)
            case .infos:
                RefreshPage(probe: probe, section: .infos)
            case .time:
                RefreshPage(probe: probe, section: .time)
            case .history:
                RefreshPage(probe: probe, section: .history)
            }
        }
        .refreshOnActivation(id: CommissionDetailRefreshID(commissionId: 10, section: probe.section)) {
            probe.orderRequests += 1
        }
        .environment(\.commissionRefreshRevision, probe.revision)
        .environment(\.scenePhase, probe.phase)
        .onChange(of: probe.phase) { _, phase in probe.observedPhase = phase }
    }
}

private struct RefreshPage: View {
    @ObservedObject var probe: RefreshProbe
    let section: CommissionDetailSection
    @State private var draft = ""

    var body: some View {
        TextField("Notiz", text: $draft)
            .onChange(of: probe.typedText) { _, text in
                draft = text
                probe.visibleDraft = text
            }
            .refreshOnActivation(id: 10, refreshAction: {
                probe.refreshRequests[section, default: 0] += 1
                probe.refreshedDraft = draft
            }) {
                probe.initialRequests[section, default: 0] += 1
            }
    }
}

//
//  WattNuApp.swift
//  WattNu
//
//  Created by Sebastian Bauhaus on 09.06.26.
//

import SwiftUI

@main
struct DatLaeuftApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var locationStore = LocationStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(session.localSettings)
                .environmentObject(locationStore)
                .task {
                    await session.bootstrap()
                }
        }
    }
}

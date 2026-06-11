//
//  RootView.swift
//  WattNu
//
//  Created by Sebastian Bauhaus on 09.06.26.
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        Group {
            if session.isLoading && session.accessToken != nil && session.user == nil {
                ProgressView("Wird geladen …")
            } else if session.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .alert("Hinweis", isPresented: Binding(
            get: { session.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    session.errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                session.errorMessage = nil
            }
        } message: {
            Text(session.errorMessage ?? "")
        }
    }
}

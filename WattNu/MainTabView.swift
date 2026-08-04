//
//  MainTabView.swift
//  WattNu
//
//  Created by Sebastian Bauhaus on 09.06.26.
//

import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            CommissionListView()
                .tabItem {
                    Label(
                        "Aufträge",
                        systemImage: "list.bullet.clipboard"
                    )
                }

            InventoryView()
                .tabItem {
                    Label(
                        "Lager",
                        systemImage: "shippingbox"
                    )
                }

            AppSettingsView()
                .tabItem {
                    Label(
                        "Einstellungen",
                        systemImage: "gearshape"
                    )
                }
        }
    }
}

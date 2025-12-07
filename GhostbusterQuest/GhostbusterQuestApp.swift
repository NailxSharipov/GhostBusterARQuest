//
//  GhostbusterQuestApp.swift
//  GhostbusterQuest
//
//  Created by Nail Sharipov on 7.12.2025.
//

import SwiftUI

@main
struct GhostbusterQuestApp: App {
    @StateObject private var store = GameStore()
    @StateObject private var locationProvider = UserLocationProvider()

    var body: some Scene {
        WindowGroup {
            GameListView()
                .environmentObject(store)
                .environmentObject(locationProvider)
        }
    }
}

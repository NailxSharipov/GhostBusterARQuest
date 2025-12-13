//
//  ContentView.swift
//  GhostbusterQuest
//
//  Created by Nail Sharipov on 7.12.2025.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        GameListView()
            .environmentObject(GameStore())
            .environmentObject(UserLocationProvider())
            .environmentObject(GhostModelStore())
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

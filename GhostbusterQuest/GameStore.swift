//
//  GameStore.swift
//  GhostbusterQuest
//
//  Created by Nail Sharipov on 7.12.2025.
//

import Foundation
import CoreLocation
import Combine
import SwiftUI

@MainActor
final class GameStore: ObservableObject {
    @Published var games: [Game] = GameStore.makeMock()

    // TODO: hook up JSON persistence
    func save() {
        // placeholder for disk write
    }

    func load() {
        // placeholder for disk read
    }

    func addGame() {
        let newGame = Game(name: "Новая игра", locationLayout: [], ghosts: [], isActive: false)
        games.append(newGame)
    }

    func delete(at offsets: IndexSet) {
        games.remove(atOffsets: offsets)
    }

    func resetProgress(for gameID: UUID) {
        guard let index = games.firstIndex(where: { $0.id == gameID }) else { return }
        for ghostIndex in games[index].ghosts.indices {
            games[index].ghosts[ghostIndex].state = .idle
            games[index].ghosts[ghostIndex].currentLatitude = games[index].ghosts[ghostIndex].baseLatitude
            games[index].ghosts[ghostIndex].currentLongitude = games[index].ghosts[ghostIndex].baseLongitude
        }
    }

    func setActive(gameID: UUID) {
        for idx in games.indices {
            games[idx].isActive = games[idx].id == gameID
        }
    }
}

private extension GameStore {
    static func makeMock() -> [Game] {
        let base = CLLocationCoordinate2D(latitude: 55.7558, longitude: 37.6173)
        let circle = CircleZone(center: base, radiusMeters: 120)
        let ghost = Ghost(name: "Полтергейст", modelID: "ghost_01", baseLocation: base)
        let game = Game(name: "Патриаршие пруды", locationLayout: [circle], ghosts: [ghost], isActive: true)
        return [game]
    }
}

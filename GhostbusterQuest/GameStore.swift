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
    @Published var games: [Game] = []
    private var saveCancellable: AnyCancellable?
    private let fileName = "games.json"

    init() {
        load()
        observeChanges()
    }

    // MARK: - Persistence

    private func observeChanges() {
        saveCancellable = $games
            .dropFirst()
            .sink { [weak self] _ in
                self?.save()
            }
    }

    private func documentsURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    private func storageURL() -> URL? {
        documentsURL()?.appendingPathComponent(fileName)
    }

    func save() {
        guard let url = storageURL() else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(games)
            try data.write(to: url, options: .atomic)
        } catch {
            print("GameStore save error: \(error)")
        }
    }

    func load() {
        guard let url = storageURL(),
              let data = try? Data(contentsOf: url) else {
            games = GameStore.makeMock()
            return
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            games = try decoder.decode([Game].self, from: data)
        } catch {
            print("GameStore load error: \(error)")
            games = GameStore.makeMock()
        }
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

    func markCaptured(ghostID: UUID) {
        for gameIndex in games.indices {
            if let ghostIndex = games[gameIndex].ghosts.firstIndex(where: { $0.id == ghostID }) {
                games[gameIndex].ghosts[ghostIndex].state = .captured
                chooseNextTarget(in: gameIndex)
                return
            }
        }
    }

    func clearActive() {
        for idx in games.indices {
            games[idx].isActive = false
        }
    }
}

private extension GameStore {
    func chooseNextTarget(in gameIndex: Int) {
        var assigned = false
        for idx in games[gameIndex].ghosts.indices {
            if games[gameIndex].ghosts[idx].state == .captured {
                continue
            }
            if !assigned {
                games[gameIndex].ghosts[idx].state = .active
                assigned = true
            } else if games[gameIndex].ghosts[idx].state == .active {
                games[gameIndex].ghosts[idx].state = .idle
            }
        }

        if !assigned {
            for idx in games[gameIndex].ghosts.indices where games[gameIndex].ghosts[idx].state == .active {
                games[gameIndex].ghosts[idx].state = .idle
            }
        }
    }

    static func makeMock() -> [Game] {
        let base = CLLocationCoordinate2D(latitude: 55.7558, longitude: 37.6173)
        let ghost = Ghost(name: "Полтергейст", modelID: "ghost_01", baseLocation: base)
        let game = Game(name: "Патриаршие пруды", locationLayout: [], ghosts: [ghost], isActive: true)
        return [game]
    }
}

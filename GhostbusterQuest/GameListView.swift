//
//  GameListView.swift
//  GhostbusterQuest
//
//  Created by Nail Sharipov on 7.12.2025.
//

import SwiftUI
import MapKit

enum GameNavigation: Hashable {
    case game(UUID)
    case ghost(UUID)
    case scanner
}

struct GameListView: View {
    @EnvironmentObject private var store: GameStore
    @State private var path: [GameNavigation] = []
    @State private var pendingAlert: PendingGameAlert?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach($store.games) { $game in
                    NavigationLink(value: GameNavigation.game(game.id)) {
                        GameRowView(game: game)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingAlert = .delete(game.id)
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            store.setActive(gameID: game.id)
                        } label: {
                            Label("Играть", systemImage: "play.fill")
                        }
                        .tint(.green)

                        Button {
                            pendingAlert = .reset(game.id)
                        } label: {
                            Label("Сброс", systemImage: "arrow.counterclockwise")
                        }
                        .tint(.orange)
                    }
                }
                .onDelete(perform: store.delete)
            }
            .navigationTitle("Сценарии")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        store.addGame()
                    } label: {
                        Label("Новая игра", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    if let activeGame = store.games.first(where: { $0.isActive }) {
                        Menu {
                            Text(activeGame.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button {
                                path.append(.scanner)
                            } label: {
                                Label("Сканер", systemImage: "location.north.line")
                            }

                            Button {
                                pendingAlert = .reset(activeGame.id)
                            } label: {
                                Label("Сброс прогресса", systemImage: "arrow.counterclockwise")
                            }

                            Button(role: .destructive) {
                                pendingAlert = .delete(activeGame.id)
                            } label: {
                                Label("Удалить игру", systemImage: "trash")
                            }

                            Button(role: .destructive) {
                                store.clearActive()
                            } label: {
                                Label("Очистить активную", systemImage: "xmark.circle")
                            }
                        } label: {
                            Label("Охота", systemImage: "target")
                        }
                    }
                }
            }
            .alert(item: $pendingAlert) { alert in
                switch alert {
                case .delete(let id):
                    return Alert(
                        title: Text("Удалить игру?"),
                        message: Text("Все зоны и призраки будут удалены из сценария."),
                        primaryButton: .destructive(Text("Удалить")) { delete(gameID: id) },
                        secondaryButton: .cancel(Text("Отмена"))
                    )
                case .reset(let id):
                    return Alert(
                        title: Text("Сбросить прогресс?"),
                        message: Text("Все призраки будут оживлены, и счёт пойманных будет обнулён."),
                        primaryButton: .destructive(Text("Сбросить")) { store.resetProgress(for: id) },
                        secondaryButton: .cancel(Text("Отмена"))
                    )
                }
            }
            .navigationDestination(for: GameNavigation.self) { destination in
                switch destination {
                case .game(let id):
                    if let binding = binding(for: id) {
                        GameDetailView(game: binding)
                            .navigationTitle(binding.wrappedValue.name)
                    } else {
                        Text("Игра не найдена")
                    }
                case .ghost(let ghostID):
                    if let binding = ghostBinding(for: ghostID) {
                        GhostDetailView(ghost: binding) {
                            deleteGhost(id: ghostID)
                        }
                    } else {
                        Text("Призрак не найден")
                    }
                case .scanner:
                    ScannerView()
                }
            }
        }
    }

    private func binding(for id: UUID) -> Binding<Game>? {
        guard let index = store.games.firstIndex(where: { $0.id == id }) else { return nil }
        return $store.games[index]
    }

    private func delete(gameID: UUID) {
        if let index = store.games.firstIndex(where: { $0.id == gameID }) {
            store.games.remove(at: index)
        }
    }

    private func ghostBinding(for id: UUID) -> Binding<Ghost>? {
        for gameIndex in store.games.indices {
            if let ghostIndex = store.games[gameIndex].ghosts.firstIndex(where: { $0.id == id }) {
                return $store.games[gameIndex].ghosts[ghostIndex]
            }
        }
        return nil
    }

    private func deleteGhost(id: UUID) {
        for gameIndex in store.games.indices {
            if let ghostIndex = store.games[gameIndex].ghosts.firstIndex(where: { $0.id == id }) {
                store.games[gameIndex].ghosts.remove(at: ghostIndex)
                break
            }
        }
    }
}

private enum PendingGameAlert: Identifiable {
    case delete(UUID)
    case reset(UUID)

    var id: String {
        switch self {
        case .delete(let id):
            return "delete-\(id.uuidString)"
        case .reset(let id):
            return "reset-\(id.uuidString)"
        }
    }
}

private struct GameRowView: View {
    var game: Game

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(game.name)
                    .font(.headline)
                let total = game.ghosts.count
                let captured = game.capturedCount
                if total > 0 {
                    Text("Поймано \(captured) / \(total)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Новая игра (0 призраков)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if game.isActive {
                Label("Активна", systemImage: "target")
                    .font(.caption)
                    .padding(6)
                    .background(.blue.opacity(0.1), in: Capsule())
            }
        }
    }
}

struct GameListView_Previews: PreviewProvider {
    static var previews: some View {
        GameListView()
            .environmentObject(GameStore())
            .environmentObject(UserLocationProvider())
            .environmentObject(GhostModelStore())
    }
}

//
//  GameDetailView.swift
//  GhostbusterQuest
//
//  Created by Nail Sharipov on 7.12.2025.
//

import SwiftUI
import MapKit

struct GameDetailView: View {
    @Binding var game: Game
    @EnvironmentObject private var locationProvider: UserLocationProvider
    @EnvironmentObject private var store: GameStore
    @State private var mapPosition: MapCameraPosition?
    @State private var showClearAlert = false
    @State private var showGhostPicker = false

    private var mapRegion: MKCoordinateRegion { regionForContent() }

    var body: some View {
        List {
            Section("Карта") {
                Map(position: Binding(get: {
                    mapPosition ?? .region(mapRegion)
                }, set: { newValue in
                    mapPosition = newValue
                })) {
                    ForEach(game.ghosts) { ghost in
                        Marker(ghost.name, coordinate: ghost.currentLocation)
                            .tint(.purple)
                    }
                    if let user = locationProvider.lastLocation {
                        Marker("Вы", coordinate: user)
                            .tint(.red)
                    }
                }
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topTrailing) {
                    Button {
                        centerOnUser()
                    } label: {
                        Image(systemName: "location.fill")
                            .padding(10)
                            .background(.thinMaterial, in: Circle())
                    }
                    .padding(8)
                }
            }

            Section("Призраки") {
                ForEach(Array(game.ghosts.indices), id: \.self) { index in
                    let ghost = $game.ghosts[index]
                    NavigationLink(value: GameNavigation.ghost(ghost.wrappedValue.id)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ghost.wrappedValue.name)
                            Text("main \(Int(ghost.wrappedValue.mainZoneRadius)) м · fight \(Int(ghost.wrappedValue.fightRadius)) м")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { (offsets: IndexSet) in
                    game.ghosts.remove(atOffsets: offsets)
                }
                Button {
                    addGhost()
                } label: {
                    Label("Добавить призрака", systemImage: "plus")
                }
            }

            Section {
                Button(role: .destructive) {
                    showClearAlert = true
                } label: {
                    Label("Очистить игру", systemImage: "trash")
                }
            }

            Section {
                if game.isActive {
                    Label("Игра активна", systemImage: "target")
                        .foregroundStyle(.green)
                } else {
                    Button {
                        showGhostPicker = true
                    } label: {
                        Label("Старт игры", systemImage: "play.fill")
                    }
                    .tint(.green)
                }
            }
        }
        .alert("Очистить игру?", isPresented: $showClearAlert) {
            Button("Удалить всё", role: .destructive) {
                game.ghosts.removeAll()
            }
            Button("Отмена", role: .cancel) { }
        } message: {
            Text("Будут удалены все призраки этого сценария.")
        }
        .confirmationDialog("Выберите призрака для охоты", isPresented: $showGhostPicker) {
            ForEach(game.ghosts) { ghost in
                Button(ghost.name) {
                    startHunt(with: ghost.id)
                }
            }
            Button("Отмена", role: .cancel) { }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func startHunt(with ghostID: UUID) {
        store.setActive(gameID: game.id)
        for idx in game.ghosts.indices {
            game.ghosts[idx].state = game.ghosts[idx].id == ghostID ? .active : .idle
        }
    }

    private func addGhost() {
        let base = mapRegion.center
        let ghost = Ghost(name: "Новый призрак", modelID: "model_id", baseLocation: base)
        game.ghosts.append(ghost)
    }

    private func regionForContent() -> MKCoordinateRegion {
        var rect = MKMapRect.null
        var centerAccumulator: (lat: Double, lon: Double, count: Double) = (0, 0, 0)

        for ghost in game.ghosts {
            let point = MKMapPoint(ghost.currentLocation)
            let ghostRect = MKMapRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20)
            rect = rect.union(ghostRect)
            centerAccumulator.lat += ghost.currentLatitude
            centerAccumulator.lon += ghost.currentLongitude
            centerAccumulator.count += 1
        }

        if let user = locationProvider.lastLocation {
            let point = MKMapPoint(user)
            let userRect = MKMapRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20)
            rect = rect.union(userRect)
        }

        if rect.isNull {
            if let user = locationProvider.lastLocation {
                let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                return MKCoordinateRegion(center: user, span: span)
            } else {
                return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 55.7558, longitude: 37.6173), span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
            }
        }

        let padded = rect.insetBy(dx: -rect.size.width * 0.25, dy: -rect.size.height * 0.25)
        var region = MKCoordinateRegion(padded)
        if centerAccumulator.count > 0 {
            region.center = CLLocationCoordinate2D(
                latitude: centerAccumulator.lat / centerAccumulator.count,
                longitude: centerAccumulator.lon / centerAccumulator.count
            )
        }
        return region
    }

    private func centerOnUser() {
        guard let user = locationProvider.lastLocation else { return }
        let span = MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
        mapPosition = .region(MKCoordinateRegion(center: user, span: span))
    }
}

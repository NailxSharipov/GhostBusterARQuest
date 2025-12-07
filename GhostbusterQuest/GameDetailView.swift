//
//  GameDetailView.swift
//  GhostbusterQuest
//
//  Created by Nail Sharipov on 7.12.2025.
//

import SwiftUI
import MapKit
import Combine

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
            Section("Карта локаций") {
                MapReader { proxy in
                    Map(position: Binding(get: {
                        mapPosition ?? .region(mapRegion)
                    }, set: { newValue in
                        mapPosition = newValue
                    })) {
                        ForEach(Array(game.locationLayout.enumerated()), id: \.element.id) { entry in
                            let index = entry.offset
                            let zone = entry.element
                            let center = zone.coordinate

                            MapCircle(center: center, radius: zone.radiusMeters)
                                .foregroundStyle(.blue.opacity(0.2))
                            MapCircle(center: center, radius: 4.0)
                                .foregroundStyle(.blue.opacity(0.35))
                            Annotation("", coordinate: center) {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.white)
                                    )
                                    .shadow(radius: 4)
                                    .gesture(
                                        DragGesture()
                                            .onChanged { value in
                                                moveZone(at: index, translation: value.translation, center: center, proxy: proxy)
                                            }
                                    )
                            }
                        }
                        ForEach(game.ghosts) { ghost in
                            Marker(ghost.name, coordinate: ghost.currentLocation)
                                .tint(.purple)
                        }
                        if let user = locationProvider.lastLocation {
                            Marker("Вы", coordinate: user)
                                .tint(.red)
                        }
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
                Button {
                    addZone()
                } label: {
                    Label("Добавить окружность", systemImage: "plus.circle")
                }
            }

            Section("Окружности") {
                if game.locationLayout.isEmpty {
                    Text("Добавьте зону на карте или кнопкой выше")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(game.locationLayout.indices), id: \.self) { index in
                    let zone = $game.locationLayout[index]
                    let zoneColor = ZoneStyling.color(for: zone.wrappedValue.id, in: game.locationLayout)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Зона \(zone.wrappedValue.id.uuidString.prefix(4))")
                            .font(.subheadline)
                        Slider(value: zone.radiusMeters, in: 50...250, step: 10) {
                            Text("Радиус")
                        } minimumValueLabel: {
                            Text("50")
                        } maximumValueLabel: {
                            Text("250")
                        }
                        Text("Радиус: \(Int(zone.wrappedValue.radiusMeters)) м")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Spacer()
                            RoundedRectangle(cornerRadius: 3)
                                .fill(zoneColor)
                                .frame(width: 20, height: 12)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { (offsets: IndexSet) in
                    game.locationLayout.remove(atOffsets: offsets)
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
                game.locationLayout.removeAll()
            }
            Button("Отмена", role: .cancel) { }
        } message: {
            Text("Будут удалены все окружности и призраки этого сценария.")
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

    private func addZone() {
        let base = CLLocationCoordinate2D(latitude: mapRegion.center.latitude, longitude: mapRegion.center.longitude)
        let zone = CircleZone(center: base, radiusMeters: 120)
        game.locationLayout.append(zone)
    }

    private func addGhost() {
        let base = mapRegion.center
        let ghost = Ghost(name: "Новый призрак", modelID: "model_id", baseLocation: base)
        game.ghosts.append(ghost)
    }

    private func regionForContent() -> MKCoordinateRegion {
        var rect = MKMapRect.null
        var centerAccumulator: (lat: Double, lon: Double, count: Double) = (0, 0, 0)

        for zone in game.locationLayout {
            let centerPoint = MKMapPoint(zone.coordinate)
            let pointsPerMeter = MKMapPointsPerMeterAtLatitude(zone.centerLatitude)
            let delta = zone.radiusMeters * pointsPerMeter
            let zoneRect = MKMapRect(x: centerPoint.x - delta, y: centerPoint.y - delta, width: delta * 2, height: delta * 2)
            rect = rect.union(zoneRect)
            centerAccumulator.lat += zone.centerLatitude
            centerAccumulator.lon += zone.centerLongitude
            centerAccumulator.count += 1
        }

        for ghost in game.ghosts {
            let point = MKMapPoint(ghost.currentLocation)
            let ghostRect = MKMapRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20)
            rect = rect.union(ghostRect)
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

    private func moveZone(at index: Int, translation: CGSize, center: CLLocationCoordinate2D, proxy: MapProxy) {
        guard let currentPoint = proxy.convert(center, to: .local) else { return }
        let translatedPoint = CGPoint(
            x: currentPoint.x + translation.width,
            y: currentPoint.y + translation.height
        )
        if let newCoordinate = proxy.convert(translatedPoint, from: .local) {
            game.locationLayout[index].centerLatitude = newCoordinate.latitude
            game.locationLayout[index].centerLongitude = newCoordinate.longitude
        }
    }
}

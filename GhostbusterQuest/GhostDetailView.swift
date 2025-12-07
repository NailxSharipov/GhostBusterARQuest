//
//  GhostDetailView.swift
//  GhostbusterQuest
//
//  Created by Nail Sharipov on 7.12.2025.
//

import SwiftUI
import MapKit

struct GhostDetailView: View {
    @Binding var ghost: Ghost
    var onDelete: () -> Void
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss

    private let mainRange: ClosedRange<Double> = 100...200
    private let fightRange: ClosedRange<Double> = 10...30
    private let trapRange: ClosedRange<Double> = 5...10
    private let escapeRange: ClosedRange<Double> = 30...50
    @State private var showDeleteAlert = false

    private var mapRegion: MKCoordinateRegion {
        MKCoordinateRegion(center: ghost.currentLocation, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
    }

    var body: some View {
        Form {
            Section("Параметры") {
                TextField("Имя", text: $ghost.name)
                TextField("Модель (asset id)", text: $ghost.modelID)
            }

            Section("Базовая точка") {
                MapReader { proxy in
                    Map(initialPosition: .region(mapRegion)) {
                        let center = ghost.currentLocation
                        MapCircle(center: center, radius: ghost.mainZoneRadius)
                            .foregroundStyle(Color.blue.opacity(0.2))
                            .mapOverlayLevel(level: .aboveRoads)
                        MapCircle(center: center, radius: ghost.fightRadius)
                            .foregroundStyle(Color.red.opacity(0.18))
                            .mapOverlayLevel(level: .aboveRoads)
                        Annotation("", coordinate: ghost.currentLocation) {
                            Circle()
                                .fill(Color.purple)
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Image(systemName: "figure.wave")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white)
                                )
                                .shadow(radius: 4)
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            moveGhost(translation: value.translation, center: ghost.currentLocation, proxy: proxy)
                                        }
                                )
                        }
                    }
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                HStack(spacing: 16) {
                    legendRow(color: .blue, title: "Основная зона", value: Int(ghost.mainZoneRadius), suffix: "м")
                    legendRow(color: .red, title: "Радиус боя", value: Int(ghost.fightRadius), suffix: "м")
                }
                .padding(.top, 6)
                HStack {
                    Text("Lat \(ghost.baseLatitude, specifier: "%.4f")")
                    Spacer()
                    Text("Lon \(ghost.baseLongitude, specifier: "%.4f")")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Дистанции и время") {
                sliderRow(title: "Основная зона", value: $ghost.mainZoneRadius, range: mainRange, suffix: "м")
                sliderRow(title: "Радиус боя", value: $ghost.fightRadius, range: fightRange, suffix: "м")
                sliderRow(title: "Окно ловушки", value: $ghost.trapWindowDuration, range: trapRange, suffix: "с")
                sliderRow(title: "Отлетает на", value: $ghost.escapeDistanceMeters, range: escapeRange, suffix: "м")
            }

            Section {
                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Label("Удалить призрака", systemImage: "trash")
                }
            }
        }
        .navigationTitle(ghost.name.isEmpty ? "Призрак" : ghost.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Удалить призрака?", isPresented: $showDeleteAlert) {
            Button("Удалить", role: .destructive) {
                onDelete()
                dismiss()
            }
            Button("Отмена", role: .cancel) { }
        } message: {
            Text("Этот призрак будет удалён из игры.")
        }
    }

    private func legendRow(color: Color, title: String, value: Int, suffix: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 16, height: 12)
            Text("\(title) \(value) \(suffix)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func moveGhost(translation: CGSize, center: CLLocationCoordinate2D, proxy: MapProxy) {
        guard let currentPoint = proxy.convert(center, to: .local) else { return }
        let translatedPoint = CGPoint(
            x: currentPoint.x + translation.width,
            y: currentPoint.y + translation.height
        )
        if let newCoordinate = proxy.convert(translatedPoint, from: .local) {
            ghost.baseLatitude = newCoordinate.latitude
            ghost.baseLongitude = newCoordinate.longitude
            ghost.currentLocation = newCoordinate
        }
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(title): \(Int(value.wrappedValue)) \(suffix)")
            Slider(value: value, in: range, step: 1)
        }
    }
}

struct GhostDetailView_Previews: PreviewProvider {
    @State static var ghost = Ghost(name: "Полтергейст", modelID: "ghost_01", baseLocation: CLLocationCoordinate2D(latitude: 55.75, longitude: 37.61))
    static var previews: some View {
        let store = GameStore()
        store.games = [
            Game(name: "Парк", locationLayout: [
                CircleZone(center: ghost.baseLocation, radiusMeters: 120),
                CircleZone(center: CLLocationCoordinate2D(latitude: ghost.baseLatitude + 0.002, longitude: ghost.baseLongitude + 0.002), radiusMeters: 80)
            ], ghosts: [ghost], isActive: true)
        ]
        return NavigationStack {
            GhostDetailView(ghost: $ghost, onDelete: {})
        }
        .environmentObject(store)
    }
}

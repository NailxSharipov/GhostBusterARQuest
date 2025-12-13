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
    @EnvironmentObject private var modelStore: GhostModelStore
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
            }

            Section("Модель") {
                if modelOptions.isEmpty {
                    Text("Модели не найдены в бандле")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Файл", selection: $modelStore.settings.modelID) {
                        ForEach(modelOptions, id: \.self) { id in
                            Text(displayModelName(id))
                                .tag(id)
                        }
                    }
                }

                NavigationLink {
                    GhostModelSettingsView()
                } label: {
                    Label("Настроить модель", systemImage: "slider.horizontal.3")
                }

                Text("Настройки модели общие для всех призраков.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Базовая точка") {
                MapReader { proxy in
                    Map(initialPosition: .region(mapRegion)) {
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

    private var modelOptions: [String] {
        let available = modelStore.availableModels
        let selected = modelStore.settings.modelID
        if available.isEmpty {
            return selected.isEmpty ? [] : [selected]
        }
        if available.contains(selected) || selected.isEmpty {
            return available
        }
        return [selected] + available
    }

    private func displayModelName(_ id: String) -> String {
        id.split(separator: "/").last.map(String.init) ?? id
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
        .environmentObject(GhostModelStore())
    }
}

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

    private let mainRange: ClosedRange<Double> = 100...200
    private let fightRange: ClosedRange<Double> = 10...30
    private let trapRange: ClosedRange<Double> = 5...10
    private let escapeRange: ClosedRange<Double> = 30...50

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
                Map(initialPosition: .region(mapRegion)) {
                    Marker(ghost.name, coordinate: ghost.currentLocation)
                        .tint(.purple)
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
                Button(role: .destructive, action: onDelete) {
                    Label("Удалить призрака", systemImage: "trash")
                }
            }
        }
        .navigationTitle(ghost.name.isEmpty ? "Призрак" : ghost.name)
        .navigationBarTitleDisplayMode(.inline)
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
        NavigationStack {
            GhostDetailView(ghost: $ghost, onDelete: {})
        }
    }
}

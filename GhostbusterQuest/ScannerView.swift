//
//  ScannerView.swift
//  GhostbusterQuest
//
//  Created by Nail Sharipov on 10.12.2025.
//

import SwiftUI
import CoreLocation
import MapKit

struct ScannerView: View {
    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var locationProvider: UserLocationProvider
    private let radarRangeMeters: Double = 100
    private let waveDuration: Double = 3.0

    private var activeGame: Game? {
        store.games.first(where: { $0.isActive })
    }

    private var targetGhost: Ghost? {
        guard let game = activeGame else { return nil }
        if let active = game.ghosts.first(where: { $0.state == .active }) {
            return active
        }
        return game.ghosts.first
    }

    var body: some View {
        VStack(spacing: 24) {
            if let ghost = targetGhost, let user = locationProvider.lastLocation {
                let distance = user.distance(to: ghost.currentLocation)

                RadarView(
                    user: user,
                    ghost: ghost,
                    maxRange: radarRangeMeters,
                    waveDuration: waveDuration
                )
                .frame(height: 320)

                VStack(spacing: 8) {
                    Text("Призрак: \(ghost.name)")
                        .font(.title3)
                    Text("Дистанция: \(Int(distance)) м")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                if distance <= ghost.mainZoneRadius {
                    Text("Вы в основной зоне — можно переходить в AR")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                } else {
                    Text("Идите по волнам, чтобы войти в основную зону")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button {
                    // переход в режим ловли/AR — заглушка
                } label: {
                    Label("Ловить", systemImage: "scope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(distance > max(30, ghost.fightRadius))

                Spacer()
            } else {
                ContentUnavailableView("Нет активной охоты", systemImage: "slash.circle")
            }
        }
        .padding()
        .navigationTitle("Сканер")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RadarView: View {
    let user: CLLocationCoordinate2D
    let ghost: Ghost
    let maxRange: Double
    let waveDuration: Double
    private let spriteSize: CGFloat = 50

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let radiusPx = size / 2
            let scale = radiusPx / maxRange
            let vector = offsetVector(from: user, to: ghost.currentLocation, scale: scale)
            let clampedGhost = clamp(vector: vector, maxRadius: radiusPx * 0.96)
            let waveCenter = waveOrigin(vector: vector, maxRadius: radiusPx)
            let vectorMeters = hypot(vector.dx, vector.dy) / scale

            ZStack {
                Circle()
                    .stroke(.blue.opacity(0.8), lineWidth: 2)

                TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
                    let time = context.date.timeIntervalSinceReferenceDate
                    let progress = (time.truncatingRemainder(dividingBy: waveDuration)) / waveDuration
                    let waveRadius = radiusPx * 1.2 * CGFloat(progress)

                    Circle()
                        .stroke(.blue.opacity(0.28 * (1 - progress)), lineWidth: 3)
                        .frame(width: waveRadius * 2, height: waveRadius * 2)
                        .offset(x: waveCenter.dx, y: waveCenter.dy)
                        .frame(width: size, height: size, alignment: .center)
                        .clipped()
                }

                GhostSpriteView()
                    .frame(width: spriteSize, height: spriteSize)
                    .offset(x: clampedGhost.dx, y: clampedGhost.dy)
                    .opacity(vectorMeters <= maxRange ? 0.9 : 0.0)
                    .scaleEffect(vectorMeters <= maxRange ? 1.0 : 0.75)
            }
            .frame(width: size, height: size)
        }
    }

    private func waveOrigin(vector: (dx: CGFloat, dy: CGFloat), maxRadius: CGFloat) -> (dx: CGFloat, dy: CGFloat) {
        let length = sqrt(vector.dx * vector.dx + vector.dy * vector.dy)
        if length <= maxRadius {
            return vector
        }
        let ratio = (maxRadius * 1.1) / length
        return (dx: vector.dx * ratio, dy: vector.dy * ratio)
    }
}

private extension CLLocationCoordinate2D {
    func distance(to other: CLLocationCoordinate2D) -> Double {
        let loc1 = CLLocation(latitude: latitude, longitude: longitude)
        let loc2 = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return loc1.distance(from: loc2)
    }
}

private func offsetVector(from user: CLLocationCoordinate2D, to target: CLLocationCoordinate2D, scale: CGFloat) -> (dx: CGFloat, dy: CGFloat) {
    let userPoint = MKMapPoint(user)
    let targetPoint = MKMapPoint(target)
    let metersPerPoint = 1 / MKMapPointsPerMeterAtLatitude(user.latitude)
    let dxMeters = (targetPoint.x - userPoint.x) * metersPerPoint
    let dyMeters = (targetPoint.y - userPoint.y) * metersPerPoint
    // инвертируем y, чтобы север был вверх
    return (dx: CGFloat(dxMeters) * scale, dy: CGFloat(-dyMeters) * scale)
}

private func clamp(vector: (dx: CGFloat, dy: CGFloat), maxRadius: CGFloat) -> (dx: CGFloat, dy: CGFloat) {
    let length = sqrt(vector.dx * vector.dx + vector.dy * vector.dy)
    guard length > maxRadius else { return vector }
    let ratio = maxRadius / length
    return (dx: vector.dx * ratio, dy: vector.dy * ratio)
}

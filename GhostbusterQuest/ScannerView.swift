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
    @State private var showARPrototype = false
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
                    heading: locationProvider.heading,
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

                let canFight = distance <= ghost.fightRadius
                Button {
                    showARPrototype = true
                } label: {
                    Label("Ловить (AR)", systemImage: "scope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(canFight ? .green : .gray)
                .disabled(!canFight)

                Spacer()
            } else {
                ContentUnavailableView("Нет активной охоты", systemImage: "slash.circle")
            }
        }
        .padding()
        .navigationTitle("Сканер")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showARPrototype) {
            ARHuntView(ghostID: targetGhost?.id)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Стоп") {
                    store.clearActive()
                }
                .tint(.red)
            }
        }
    }
}

private struct RadarView: View {
    let user: CLLocationCoordinate2D
    let ghost: Ghost
    let heading: CLHeading?
    let maxRange: Double
    let waveDuration: Double
    private let spriteSize: CGFloat = 50

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let radiusPx = size / 2
            let scale = radiusPx / maxRange
            let vector = offsetVector(
                from: user,
                to: ghost.currentLocation,
                heading: heading,
                scale: scale
            )
            let clampedGhost = clamp(vector: vector, maxRadius: radiusPx * 0.96)
            let waveCenter = waveOrigin(vector: vector, maxRadius: radiusPx)
            let vectorMeters = hypot(vector.dx, vector.dy) / scale

            ZStack {
                Circle()
                    .stroke(.blue.opacity(0.8), lineWidth: 2)

                TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
                    let time = context.date.timeIntervalSinceReferenceDate
                    let progress = (time.truncatingRemainder(dividingBy: waveDuration)) / waveDuration
                    let waveRadius = radiusPx * 2 * CGFloat(progress)

                    Circle()
                        .stroke(.blue.opacity(0.5 * (1 - 0.8 * progress)), lineWidth: 3)
                        .frame(width: waveRadius * 2, height: waveRadius * 2)
                        .offset(x: waveCenter.dx, y: waveCenter.dy)
                        .frame(width: size, height: size, alignment: .center)
                        .clipped()
                }

                TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
                    let time = context.date.timeIntervalSinceReferenceDate
                    let phase = time * 0.25
                    let wobbleX = sin(phase) * 6 + sin(2 * phase) * 12
                    let wobbleY = cos(phase) * 6 - cos(2 * phase) * 12
                    let dirX = 6 * cos(phase) + 24 * cos(2 * phase)
                    let dirY = -6 * sin(phase) + 24 * sin(2 * phase)
                    let rotation = Angle(radians: atan2(dirY, dirX))

                    GhostSpriteView(tint: vectorMeters <= maxRange ? .green : .white)
                        .frame(width: spriteSize, height: spriteSize)
                        .rotationEffect(rotation)
                        .offset(x: clampedGhost.dx + wobbleX, y: clampedGhost.dy + wobbleY)
                        .opacity(vectorMeters <= maxRange ? 0.9 : 0.0)
                        .scaleEffect(vectorMeters <= maxRange ? 1.0 : 0.75)
                        .frame(width: size, height: size, alignment: .center)
                }
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

private func offsetVector(
    from user: CLLocationCoordinate2D,
    to target: CLLocationCoordinate2D,
    heading: CLHeading?,
    scale: CGFloat
) -> (dx: CGFloat, dy: CGFloat) {
    let distanceMeters = user.distance(to: target)

    if let heading {
        let headingDegrees = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
        let bearingDegrees = bearing(from: user, to: target)
        let relative = (bearingDegrees - headingDegrees).wrappedDegrees
        let radians = relative * .pi / 180
        let dx = sin(radians) * distanceMeters
        let dy = -cos(radians) * distanceMeters // вверх = направление взгляда
        return (dx: CGFloat(dx) * scale, dy: CGFloat(dy) * scale)
    }

    // fallback: север вверх
    let userPoint = MKMapPoint(user)
    let targetPoint = MKMapPoint(target)
    let metersPerPoint = 1 / MKMapPointsPerMeterAtLatitude(user.latitude)
    let dxMeters = (targetPoint.x - userPoint.x) * metersPerPoint
    let dyMeters = (targetPoint.y - userPoint.y) * metersPerPoint
    return (dx: CGFloat(dxMeters) * scale, dy: CGFloat(-dyMeters) * scale)
}

private func clamp(vector: (dx: CGFloat, dy: CGFloat), maxRadius: CGFloat) -> (dx: CGFloat, dy: CGFloat) {
    let length = sqrt(vector.dx * vector.dx + vector.dy * vector.dy)
    guard length > maxRadius else { return vector }
    let ratio = maxRadius / length
    return (dx: vector.dx * ratio, dy: vector.dy * ratio)
}

private func bearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
    let lat1 = start.latitude.radians
    let lon1 = start.longitude.radians
    let lat2 = end.latitude.radians
    let lon2 = end.longitude.radians

    let dLon = lon2 - lon1
    let y = sin(dLon) * cos(lat2)
    let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
    let bearing = atan2(y, x)
    return bearing.degrees
}

private extension Double {
    var radians: Double { self * .pi / 180 }
    var degrees: Double { self * 180 / .pi }

    var wrappedDegrees: Double {
        let normalized = truncatingRemainder(dividingBy: 360)
        return normalized < 0 ? normalized + 360 : normalized
    }
}

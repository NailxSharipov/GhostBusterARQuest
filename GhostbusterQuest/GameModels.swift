//
//  GameModels.swift
//  GhostbusterQuest
//
//  Created by Nail Sharipov on 7.12.2025.
//

import Foundation
import CoreLocation

struct CircleZone: Identifiable, Codable, Hashable {
    let id: UUID
    var centerLatitude: Double
    var centerLongitude: Double
    var radiusMeters: Double

    init(id: UUID = UUID(), center: CLLocationCoordinate2D, radiusMeters: Double = 100) {
        self.id = id
        self.centerLatitude = center.latitude
        self.centerLongitude = center.longitude
        self.radiusMeters = radiusMeters
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: centerLatitude, longitude: centerLongitude)
    }
}

enum GhostState: String, Codable, CaseIterable {
    case idle
    case active
    case arSearch
    case fight
    case trapWindow
    case escaped
    case captured
}

struct Ghost: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var modelID: String
    var baseLatitude: Double
    var baseLongitude: Double
    var currentLatitude: Double
    var currentLongitude: Double
    var mainZoneRadius: Double
    var fightRadius: Double
    var trapWindowDuration: TimeInterval
    var escapeDistanceMeters: Double
    var state: GhostState
    var lastEscapeDate: Date?

    init(
        id: UUID = UUID(),
        name: String,
        modelID: String,
        baseLocation: CLLocationCoordinate2D,
        mainZoneRadius: Double = 150,
        fightRadius: Double = 20,
        trapWindowDuration: TimeInterval = 7,
        escapeDistanceMeters: Double = 40,
        state: GhostState = .idle,
        lastEscapeDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.modelID = modelID
        self.baseLatitude = baseLocation.latitude
        self.baseLongitude = baseLocation.longitude
        self.currentLatitude = baseLocation.latitude
        self.currentLongitude = baseLocation.longitude
        self.mainZoneRadius = mainZoneRadius
        self.fightRadius = fightRadius
        self.trapWindowDuration = trapWindowDuration
        self.escapeDistanceMeters = escapeDistanceMeters
        self.state = state
        self.lastEscapeDate = lastEscapeDate
    }

    var baseLocation: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: baseLatitude, longitude: baseLongitude)
    }

    var currentLocation: CLLocationCoordinate2D {
        get { CLLocationCoordinate2D(latitude: currentLatitude, longitude: currentLongitude) }
        set {
            currentLatitude = newValue.latitude
            currentLongitude = newValue.longitude
        }
    }
}

struct Game: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var locationLayout: [CircleZone]
    var ghosts: [Ghost]
    var isActive: Bool

    init(
        id: UUID = UUID(),
        name: String,
        locationLayout: [CircleZone] = [],
        ghosts: [Ghost] = [],
        isActive: Bool = false
    ) {
        self.id = id
        self.name = name
        self.locationLayout = locationLayout
        self.ghosts = ghosts
        self.isActive = isActive
    }

    var capturedCount: Int {
        ghosts.filter { $0.state == .captured }.count
    }
}

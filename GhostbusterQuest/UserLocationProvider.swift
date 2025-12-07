//
//  UserLocationProvider.swift
//  GhostbusterQuest
//
//  Created by Nail Sharipov on 7.12.2025.
//

import Foundation
import CoreLocation
import Combine

final class UserLocationProvider: NSObject, ObservableObject {
    @Published var lastLocation: CLLocationCoordinate2D?
    @Published var heading: CLHeading?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        requestAccessIfNeeded()
    }

    private func requestAccessIfNeeded() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
        default:
            break
        }
    }
}

extension UserLocationProvider: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            lastLocation = location.coordinate
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading
    }
}

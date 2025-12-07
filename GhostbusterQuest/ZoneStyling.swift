//
//  ZoneStyling.swift
//  GhostbusterQuest
//
//  Created by Nail Sharipov on 10.12.2025.
//

import SwiftUI

enum ZoneStyling {
    private static let palette: [Color] = [
        .blue, .green, .orange, .pink, .purple, .teal, .yellow, .red, .indigo
    ]

    static func color(for zoneID: UUID, in zones: [CircleZone]) -> Color {
        guard let index = zones.firstIndex(where: { $0.id == zoneID }), !palette.isEmpty else {
            return .blue
        }
        return palette[index % palette.count]
    }
}

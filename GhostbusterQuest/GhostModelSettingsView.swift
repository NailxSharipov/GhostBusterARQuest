//
//  GhostModelSettingsView.swift
//  GhostbusterQuest
//
//  Created by Nail Sharipov on 13.12.2025.
//

import SwiftUI

struct GhostModelSettingsView: View {
    @EnvironmentObject private var modelStore: GhostModelStore

    private let realScaleRange: ClosedRange<Double> = 0.1...100

    var body: some View {
        Form {
            Section("Модель") {
                Text(displayModelName(modelStore.settings.modelID))
                    .foregroundStyle(.secondary)
            }

            Section("Размер") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Scale: \(scaleText(modelStore.settings.scale))")
                    Slider(value: logScaleBinding, in: logScaleRange, step: 0.01)
                }
            }
        }
        .navigationTitle("Настройка модели")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var logScaleRange: ClosedRange<Double> {
        log10(realScaleRange.lowerBound)...log10(realScaleRange.upperBound)
    }

    private var logScaleBinding: Binding<Double> {
        Binding(
            get: {
                log10(clamp(modelStore.settings.scale, to: realScaleRange))
            },
            set: { newLog in
                let value = pow(10, newLog)
                modelStore.settings.scale = clamp(value, to: realScaleRange)
            }
        )
    }

    private func displayModelName(_ id: String) -> String {
        id.split(separator: "/").last.map(String.init) ?? id
    }

    private func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func scaleText(_ value: Double) -> String {
        let clamped = clamp(value, to: realScaleRange)
        if clamped >= 10 {
            return String(format: "%.0f", clamped)
        }
        if clamped >= 1 {
            return String(format: "%.2f", clamped)
        }
        return String(format: "%.3f", clamped)
    }
}

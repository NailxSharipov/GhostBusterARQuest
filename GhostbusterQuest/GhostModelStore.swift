//
//  GhostModelStore.swift
//  GhostbusterQuest
//
//  Created by Nail Sharipov on 13.12.2025.
//

import Foundation
import Combine

struct GhostModelSettings: Codable, Hashable {
    var modelID: String
    var scale: Double

    static let `default` = GhostModelSettings(modelID: "Quaternius.usdc", scale: 0.12)
}

@MainActor
final class GhostModelStore: ObservableObject {
    @Published var settings: GhostModelSettings = .default

    private var saveCancellable: AnyCancellable?
    private let fileName = "ghost_model.json"

    init() {
        load()
        observeChanges()
    }

    var availableModels: [String] {
        var result = Set<String>()
        let exts = ["usdc", "usdz"]

        for ext in exts {
            if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: "Ghost") {
                for url in urls {
                    result.insert("Ghost/\(url.lastPathComponent)")
                }
            }
            if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) {
                for url in urls {
                    result.insert(url.lastPathComponent)
                }
            }
        }

        return result.sorted()
    }

    // MARK: - Persistence

    private func observeChanges() {
        saveCancellable = $settings
            .dropFirst()
            .sink { [weak self] _ in
                self?.save()
            }
    }

    private func documentsURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    private func storageURL() -> URL? {
        documentsURL()?.appendingPathComponent(fileName)
    }

    func save() {
        guard let url = storageURL() else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings)
            try data.write(to: url, options: .atomic)
        } catch {
            print("GhostModelStore save error: \(error)")
        }
    }

    func load() {
        guard let url = storageURL(),
              let data = try? Data(contentsOf: url) else {
            settings = .default
            return
        }
        do {
            let decoder = JSONDecoder()
            settings = try decoder.decode(GhostModelSettings.self, from: data)
        } catch {
            print("GhostModelStore load error: \(error)")
            settings = .default
        }
    }
}


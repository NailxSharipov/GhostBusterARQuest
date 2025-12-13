//
//  GhostModelPreviewView.swift
//  GhostbusterQuest
//
//  Created by Nail Sharipov on 13.12.2025.
//

import SwiftUI
import RealityKit
import Combine

struct GhostModelAnimationOption: Identifiable, Hashable {
    let id: String
    let title: String
}

struct GhostModelPreviewView: UIViewRepresentable {
    let modelID: String
    let scale: Double
    let selectedHitAnimationID: String?
    let playHitTrigger: Int
    let onAnimationsChanged: ([GhostModelAnimationOption]) -> Void

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(.black)
        view.environment.lighting.intensityExponent = 1.0

        let anchor = AnchorEntity(world: .zero)
        view.scene.addAnchor(anchor)
        context.coordinator.attach(view: view, anchor: anchor)
        context.coordinator.load(modelID: modelID, scale: Float(scale), onAnimationsChanged: onAnimationsChanged)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.update(
            modelID: modelID,
            scale: Float(scale),
            selectedHitAnimationID: selectedHitAnimationID,
            playHitTrigger: playHitTrigger,
            onAnimationsChanged: onAnimationsChanged
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private weak var view: ARView?
        private var anchor: AnchorEntity?
        private var modelEntity: ModelEntity?
        private var cancellable: AnyCancellable?
        private var lastModelID: String?
        private var lastScale: Float?
        private var lastPlayHitTrigger: Int = 0
        private var animations: [AnimationResource] = []
        private var animationOptions: [GhostModelAnimationOption] = []

        func attach(view: ARView, anchor: AnchorEntity) {
            self.view = view
            self.anchor = anchor
        }

        func update(
            modelID: String,
            scale: Float,
            selectedHitAnimationID: String?,
            playHitTrigger: Int,
            onAnimationsChanged: @escaping ([GhostModelAnimationOption]) -> Void
        ) {
            if lastModelID != modelID {
                load(modelID: modelID, scale: scale, onAnimationsChanged: onAnimationsChanged)
            } else if lastScale != scale {
                modelEntity?.scale = [scale, scale, scale]
                lastScale = scale
            }

            if playHitTrigger != lastPlayHitTrigger {
                lastPlayHitTrigger = playHitTrigger
                playHit(selectedHitAnimationID: selectedHitAnimationID)
            }
        }

        func load(modelID: String, scale: Float, onAnimationsChanged: @escaping ([GhostModelAnimationOption]) -> Void) {
            cancellable?.cancel()
            cancellable = nil
            lastModelID = modelID
            lastScale = scale

            anchor?.children.removeAll()
            modelEntity = nil
            animations.removeAll()
            animationOptions.removeAll()
            onAnimationsChanged([])

            guard let url = resolveModelURL(modelID: modelID) else {
                return
            }

            cancellable = ModelEntity.loadModelAsync(contentsOf: url)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] completion in
                    if case .failure(let error) = completion {
                        print("GhostModelPreviewView: load error: \(error)")
                    }
                    self?.cancellable = nil
                } receiveValue: { [weak self] entity in
                    guard let self else { return }
                    entity.position = .zero
                    entity.scale = [scale, scale, scale]
                    self.anchor?.addChild(entity)
                    self.modelEntity = entity
                    self.animations = entity.availableAnimations
                    self.animationOptions = self.animations.enumerated().map { idx, anim in
                        let name = anim.name ?? ""
                        let id = name.isEmpty ? "index:\(idx)" : name
                        let title = name.isEmpty ? "Animation \(idx + 1)" : name
                        return GhostModelAnimationOption(id: id, title: title)
                    }
                    onAnimationsChanged(self.animationOptions)
                }
        }

        private func playHit(selectedHitAnimationID: String?) {
            guard let entity = modelEntity else { return }
            guard !animations.isEmpty else { return }

            if let selectedHitAnimationID, !selectedHitAnimationID.isEmpty {
                if selectedHitAnimationID.hasPrefix("index:"),
                   let idx = Int(selectedHitAnimationID.dropFirst("index:".count)),
                   animations.indices.contains(idx) {
                    entity.playAnimation(animations[idx])
                    return
                }
                if let match = animations.first(where: { ($0.name ?? "") == selectedHitAnimationID }) {
                    entity.playAnimation(match)
                    return
                }
            }

            if let auto = animations.first(where: { ($0.name ?? "").localizedCaseInsensitiveContains("hit") }) {
                entity.playAnimation(auto)
            } else {
                entity.playAnimation(animations[0])
            }
        }

        private func resolveModelURL(modelID: String) -> URL? {
            let normalizedPath = modelID.replacingOccurrences(of: "\\", with: "/")
            let parts = normalizedPath.split(separator: "/").map(String.init)
            let fileName = parts.last ?? normalizedPath
            let subdirectory = parts.count > 1 ? parts.dropLast().joined(separator: "/") : nil

            let name: String
            let ext: String?
            if let dotIndex = fileName.lastIndex(of: ".") {
                name = String(fileName[..<dotIndex])
                ext = String(fileName[fileName.index(after: dotIndex)...])
            } else {
                name = fileName
                ext = nil
            }

            let extensionsToTry = ext.map { [$0] } ?? ["usdc", "usdz"]
            let subdirsToTry = [subdirectory, "Ghost", nil].compactMap { $0 }

            for fileExt in extensionsToTry {
                if let subdirectory {
                    if let url = Bundle.main.url(forResource: name, withExtension: fileExt, subdirectory: subdirectory) {
                        return url
                    }
                }
                for subdir in subdirsToTry {
                    if let url = Bundle.main.url(forResource: name, withExtension: fileExt, subdirectory: subdir) {
                        return url
                    }
                }
                if let url = Bundle.main.url(forResource: name, withExtension: fileExt) {
                    return url
                }
            }

            return nil
        }
    }
}

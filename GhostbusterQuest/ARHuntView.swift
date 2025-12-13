//
//  ARHuntView.swift
//  GhostbusterQuest
//
//  Created by Nail Sharipov on 11.12.2025.
//

import SwiftUI
import RealityKit
import ARKit
import Combine
import UIKit
import CoreLocation

struct ARHuntView: View {
    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var locationProvider: UserLocationProvider
    @EnvironmentObject private var modelStore: GhostModelStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine: ARHuntEngine
    private let ghostID: UUID?

    init(ghostID: UUID?) {
        self.ghostID = ghostID
        _engine = StateObject(wrappedValue: ARHuntEngine())
    }

    var body: some View {
        ZStack {
            ARHuntContainer(
                engine: engine,
                ghostLocation: ghostLocation,
                ghostModelID: modelStore.settings.modelID,
                ghostModelScale: modelStore.settings.scale,
                userLocation: locationProvider.lastLocation,
                heading: locationProvider.heading
            )
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in engine.startFiring() }
                        .onEnded { _ in engine.stopFiring() }
                )

            CrosshairView()

            if engine.canCatch {
                Button {
                    engine.performCatch {
                        captureGhostAndExit()
                    }
                } label: {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 72, height: 72)
                        .overlay(
                            Image(systemName: "sparkles")
                                .font(.title2)
                                .foregroundStyle(.white)
                        )
                        .shadow(color: .green.opacity(0.5), radius: 10)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .navigationTitle("AR-пойма")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var ghostLocation: CLLocationCoordinate2D? {
        guard let ghostID else { return nil }
        for game in store.games {
            if let ghost = game.ghosts.first(where: { $0.id == ghostID }) {
                return ghost.currentLocation
            }
        }
        return nil
    }

    private func captureGhostAndExit() {
        if let id = ghostID {
            store.markCaptured(ghostID: id)
        }
        dismiss()
    }
}

private struct ARHuntContainer: UIViewRepresentable {
    @ObservedObject var engine: ARHuntEngine
    let ghostLocation: CLLocationCoordinate2D?
    let ghostModelID: String?
    let ghostModelScale: Double
    let userLocation: CLLocationCoordinate2D?
    let heading: CLHeading?

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.automaticallyConfigureSession = false

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        view.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        engine.attach(to: view)
        engine.updateGhostModelSettings(modelID: ghostModelID, scale: ghostModelScale)
        engine.updateGhostPlacement(ghostLocation: ghostLocation, userLocation: userLocation, heading: heading)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        engine.updateGhostModelSettings(modelID: ghostModelID, scale: ghostModelScale)
        engine.updateGhostPlacement(ghostLocation: ghostLocation, userLocation: userLocation, heading: heading)
    }
}

// MARK: - Engine

@MainActor
final class ARHuntEngine: ObservableObject {
    private weak var arView: ARView?
    private let anchor = AnchorEntity(world: .zero)
    private let ghostRoot = Entity()
    private var target: ModelEntity?
    private var modelLoadCancellable: AnyCancellable?
    private var targetOriginalMaterials: [RealityKit.Material]?
    private var loadedModelKey: String?
    private var currentModelScale: Float = 0.12
    private var targetBaseScale: simd_float3 = [1, 1, 1]
    private var usingLoadedModel = false
    private var displayLink: CADisplayLink?
    private var time: CFTimeInterval = 0
    private var isFrozen = false
    private var freezePosition: simd_float3?
    private var defaultMaterial: RealityKit.Material = SimpleMaterial(color: .cyan, isMetallic: true)
    private var frozenMaterial: RealityKit.Material = SimpleMaterial(color: .red, isMetallic: true)
    private var projectiles: [Projectile] = []
    private let beamLength: Float = 0.5
    private let beamRadius: Float = 0.03
    private let projectileSpeed: Float = 10.0
    private let projectileSineAmplitude: Float = 0.08
    private let projectileSineFrequency: Float = 6.0 // Hz
    private let projectileSpin: Float = 5.0 // rad/sec
    private let projectileColor = UIColor(red: 1.0, green: 0.62, blue: 0.2, alpha: 1.0)
    private let projectileFadeDuration: Float = 2.0
    private var isFiring = false
    private var lastFireTime: CFTimeInterval = 0
    private let fireInterval: CFTimeInterval = 0.02
    @Published var canCatch = false
    private var isCaptured = false

    private let orbitRadius: Float = 0.9
    private let orbitSpeed: Float = 0.75
    private let orbitHeight: Float = 0.35
    private let orbitBobAmplitude: Float = 0.08

    private var originGeo: CLLocationCoordinate2D?
    private var originWorldPosition: simd_float3?
    private var originForwardWorld: simd_float3?
    private var originHeadingDegrees: Double?
    private var originNorthWorld: simd_float3?
    private var originEastWorld: simd_float3?

    func attach(to view: ARView) {
        arView = view
        view.scene.addAnchor(anchor)
        anchor.addChild(ghostRoot)
        setupTarget()
        startOrbitLoop()
    }

    deinit {
        displayLink?.invalidate()
    }

    func updateGhostModelSettings(modelID: String?, scale: Double) {
        let newScale = Float(max(0.01, scale))
        if abs(newScale - currentModelScale) > 0.0001 {
            currentModelScale = newScale
            applyScale()
        }
        updateGhostModel(modelID: modelID)
    }

    private func updateGhostModel(modelID: String?) {
        let key = ARHuntEngine.normalizedModelKey(modelID)
        guard loadedModelKey != key else { return }
        loadedModelKey = key
        loadGhostModel(modelID: modelID)
    }

    func updateGhostPlacement(
        ghostLocation: CLLocationCoordinate2D?,
        userLocation: CLLocationCoordinate2D?,
        heading: CLHeading?
    ) {
        guard let ghostLocation else { return }
        guard let arView else { return }

        if originGeo == nil, let userLocation {
            originGeo = userLocation
            originWorldPosition = arView.cameraTransform.translation

            let forward = ARHuntEngine.horizontalForward(from: arView.cameraTransform)
            originForwardWorld = forward
            originHeadingDegrees = heading?.resolvedHeadingDegrees
        }

        if originGeo != nil, originHeadingDegrees == nil, let headingDegrees = heading?.resolvedHeadingDegrees {
            originHeadingDegrees = headingDegrees
        }

        guard let originGeo, let originWorldPosition else { return }

        let forward = originForwardWorld ?? ARHuntEngine.horizontalForward(from: arView.cameraTransform)
        let headingDegrees = originHeadingDegrees

        let northWorld: simd_float3
        if let headingDegrees {
            let rotation = simd_quatf(angle: Float(-headingDegrees * .pi / 180), axis: [0, 1, 0])
            northWorld = simd_normalize(rotation.act(forward))
        } else {
            northWorld = forward
        }
        let eastWorld = simd_normalize(simd_cross(northWorld, [0, 1, 0]))
        originNorthWorld = northWorld
        originEastWorld = eastWorld

        let (eastMeters, northMeters) = ARHuntEngine.eastNorthMeters(from: originGeo, to: ghostLocation)
        let offset = eastWorld * Float(eastMeters) + northWorld * Float(northMeters)
        ghostRoot.position = originWorldPosition + offset
    }

    func startFiring() {
        guard !isCaptured else { return }
        if !isFiring {
            lastFireTime = time
            isFiring = true
            shootBeam()
        }
    }

    func stopFiring() {
        isFiring = false
    }

    private func shootBeam() {
        guard let arView else { return }
        let transform = arView.cameraTransform
        let forward = transform.forward
        let up = simd_float3(0, 1, 0)
        var lateral = simd_normalize(simd_cross(forward, up))
        if simd_length_squared(lateral) < 1e-4 {
            lateral = simd_normalize(simd_cross(forward, simd_float3(1, 0, 0)))
        }
        let rollSign: Float = Bool.random() ? 1 : -1

        let diameter = beamRadius * 2
        let material = SimpleMaterial(color: projectileColor.withAlphaComponent(0), isMetallic: false)
        let beam = ModelEntity(
            mesh: .generatePlane(width: diameter, depth: diameter),
            materials: [material]
        )
        beam.name = "projectile"
        let baseOrientation = simd_quatf(from: [0, 1, 0], to: forward)
        beam.orientation = baseOrientation
        // Spawn slightly in front of the camera so it doesn't overlap the screen
        let origin = transform.translation + forward * 0.35
        beam.position = origin
        beam.collision = CollisionComponent(
            shapes: [ShapeResource.generateSphere(radius: beamRadius * 1.1)],
            filter: .init(group: .projectile, mask: [.target])
        )
        anchor.addChild(beam)

        let projectile = Projectile(
            entity: beam,
            origin: origin,
            forward: forward,
            lateral: lateral,
            baseOrientation: baseOrientation,
            birthTime: time,
            rollSign: rollSign,
            baseColor: projectileColor
        )
        projectiles.append(projectile)
    }

    private func setupTarget() {
        defaultMaterial = SimpleMaterial(color: .cyan, isMetallic: true)
        frozenMaterial = SimpleMaterial(color: .red, isMetallic: true)

        let sphere = ModelEntity(mesh: .generateSphere(radius: 0.09), materials: [defaultMaterial])
        sphere.name = "target"
        sphere.collision = CollisionComponent(
            shapes: [ShapeResource.generateSphere(radius: 0.1)],
            filter: .init(group: .target, mask: [.projectile])
        )
        sphere.physicsBody = PhysicsBodyComponent(mode: .kinematic)

        ghostRoot.addChild(sphere)
        target = sphere
        targetOriginalMaterials = sphere.model?.materials
        targetBaseScale = sphere.scale
        usingLoadedModel = false

        updateGhostModel(modelID: nil)
    }

    private func loadGhostModel(modelID: String?) {
        modelLoadCancellable?.cancel()
        modelLoadCancellable = nil

        guard let url = resolveModelURL(modelID: modelID) else {
            print("ARHuntEngine: ghost model not found (modelID: \(modelID ?? "nil"))")
            return
        }

        modelLoadCancellable = ModelEntity.loadModelAsync(contentsOf: url)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                if case .failure(let error) = completion {
                    print("ARHuntEngine: failed to load ghost model: \(error)")
                }
                self?.modelLoadCancellable = nil
            } receiveValue: { [weak self] entity in
                self?.installGhostModel(entity)
            }
    }

    private static func normalizedModelKey(_ modelID: String?) -> String {
        let trimmed = (modelID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "model_id" {
            return "Quaternius.usdc"
        }
        return trimmed
    }

    private func resolveModelURL(modelID: String?) -> URL? {
        let trimmed = ARHuntEngine.normalizedModelKey(modelID)
        let normalizedPath = trimmed.replacingOccurrences(of: "\\", with: "/")
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

    private func installGhostModel(_ entity: ModelEntity) {
        target?.removeFromParent()

        entity.name = "target"
        entity.position = .zero
        entity.scale = [currentModelScale, currentModelScale, currentModelScale]
        entity.physicsBody = PhysicsBodyComponent(mode: .kinematic)

        let bounds = entity.visualBounds(relativeTo: entity)
        let extents = bounds.extents
        let radius = max(max(extents.x, max(extents.y, extents.z)) * 0.6, 0.08)
        entity.collision = CollisionComponent(
            shapes: [ShapeResource.generateSphere(radius: radius)],
            filter: .init(group: .target, mask: [.projectile])
        )

        ghostRoot.addChild(entity)
        target = entity
        targetOriginalMaterials = entity.model?.materials
        targetBaseScale = entity.scale
        usingLoadedModel = true
        applyScale()
    }

    private func applyScale() {
        guard usingLoadedModel, let target else { return }
        targetBaseScale = [currentModelScale, currentModelScale, currentModelScale]
        let mult: Float = isFrozen ? 1.12 : 1.0
        target.scale = targetBaseScale * mult
    }

    private static func horizontalForward(from transform: Transform) -> simd_float3 {
        var forward = transform.forward
        forward.y = 0
        if simd_length_squared(forward) < 1e-4 {
            return simd_float3(0, 0, -1)
        }
        return simd_normalize(forward)
    }

    private static func eastNorthMeters(from origin: CLLocationCoordinate2D, to target: CLLocationCoordinate2D) -> (east: Double, north: Double) {
        let earthRadius = 6_378_137.0
        let lat0 = origin.latitude * .pi / 180
        let dLat = (target.latitude - origin.latitude) * .pi / 180
        let dLon = (target.longitude - origin.longitude) * .pi / 180
        let north = dLat * earthRadius
        let east = dLon * earthRadius * cos(lat0)
        return (east: east, north: north)
    }

    private func startOrbitLoop() {
        displayLink = CADisplayLink(target: self, selector: #selector(stepOrbit))
        displayLink?.add(to: .main, forMode: .default)
    }

    @objc private func stepOrbit(link: CADisplayLink) {
        time += link.duration
        let delta = Float(link.duration)
        updateProjectiles(delta: delta)
        guard let target else { return }

        if isFiring {
            while time - lastFireTime >= fireInterval {
                shootBeam()
                lastFireTime += fireInterval
            }
        }

        if isFrozen {
            let base = freezePosition ?? target.position
            let shakeAmp: Float = 0.02
            let shakeFreq: Float = 28
            let t = Float(time)
            let jitter = SIMD3<Float>(
                sin(t * shakeFreq) * shakeAmp,
                cos(t * shakeFreq * 0.85) * shakeAmp * 0.5,
                cos(t * shakeFreq * 1.07) * shakeAmp
            )
            target.position = base + jitter
            target.scale = targetBaseScale * 1.12
            return
        }

        // Лемниската (восьмёрка) вокруг опорной точки
        let t = Float(time) * orbitSpeed * 1.3
        let x = sin(t) * orbitRadius
        let z = sin(t) * cos(t) * orbitRadius
        let bob = sin(Float(time) * 1.6) * orbitBobAmplitude

        target.position = [x, orbitHeight + bob, z]
        target.orientation = simd_quatf(angle: Float(time) * 0.4, axis: [0, 1, 0])
    }

    private func freezeTarget() {
        guard let target, !isCaptured else { return }
        isFrozen = true
        freezePosition = target.position
        if var model = target.model {
            let count = max(model.materials.count, 1)
            model.materials = Array(repeating: frozenMaterial, count: count)
            target.model = model
        }
        target.scale = targetBaseScale * 1.12
        canCatch = true
    }

    private func updateProjectiles(delta: Float) {
        guard let target else { return }
        var alive: [Projectile] = []
        let maxDistance: Float = 20
        let hitThreshold: Float = 0.2
        for projectile in projectiles {
            let age = Float(time - projectile.birthTime)
            let forwardOffset = projectile.forward * projectileSpeed * age
            let sinePhase = sin(age * .pi * 2 * projectileSineFrequency)
            let sineRamp = min(1, max(0, age * 5)) // ramp in first ~0.2s to keep spawn centered
            let sineOffset = projectile.lateral * sinePhase * projectileSineAmplitude * sineRamp
            projectile.entity.setPosition(projectile.origin + forwardOffset + sineOffset, relativeTo: nil)

            let rollAngle = age * projectileSpin * projectile.rollSign
            let roll = simd_quatf(angle: rollAngle, axis: projectile.forward)
            projectile.entity.orientation = roll * projectile.baseOrientation
            applyFade(to: projectile, age: age)

            let projectileWorld = projectile.entity.position(relativeTo: nil)
            let targetWorld = target.position(relativeTo: nil)
            let distance = simd_distance(projectileWorld, targetWorld)
            if !isFrozen && distance <= hitThreshold {
                projectile.entity.removeFromParent()
                freezeTarget()
                continue
            }

            let tooFar = simd_distance(projectileWorld, projectile.origin) > maxDistance
            let expired = time - projectile.birthTime > 3.0
            if tooFar || expired {
                projectile.entity.removeFromParent()
                continue
            }

            alive.append(projectile)
        }
        projectiles = alive
    }

    private func applyFade(to projectile: Projectile, age: Float) {
        guard var model = projectile.entity.model else { return }
        let t = min(max(age / projectileFadeDuration, 0), 1)
        if var material = model.materials.first as? SimpleMaterial {
            material.color.tint = projectile.baseColor.withAlphaComponent(CGFloat(t))
            model.materials = [material]
            projectile.entity.model = model
        }
    }

    func performCatch(completion: @escaping () -> Void) {
        guard let target, !isCaptured else {
            completion()
            return
        }
        isCaptured = true
        canCatch = false
        isFiring = false

        let baseTransform = target.transform
        let scaleUp = Transform(
            scale: baseTransform.scale * 1.6,
            rotation: baseTransform.rotation,
            translation: baseTransform.translation
        )

        target.move(to: scaleUp, relativeTo: target.parent, duration: 0.22, timingFunction: .easeInOut)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.23) { [weak self, weak target] in
                guard let self, let target else {
                    completion()
                    return
                }
                let camPos = self.arView?.cameraTransform.translation ?? target.position(relativeTo: nil)
                var final = Transform(matrix: target.transformMatrix(relativeTo: nil))
                final.translation = camPos
                final.scale = [0.05, 0.05, 0.05]

                target.move(to: final, relativeTo: nil, duration: 0.35, timingFunction: .easeIn)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
                target.removeFromParent()
                completion()
            }
        }
    }
}

// MARK: - Helpers

private struct Projectile {
    var entity: ModelEntity
    var origin: simd_float3
    var forward: simd_float3
    var lateral: simd_float3
    var baseOrientation: simd_quatf
    var birthTime: CFTimeInterval
    var rollSign: Float
    var baseColor: UIColor
}

private extension Transform {
    var forward: simd_float3 {
        let column = matrix.columns.2
        let vector = simd_float3(-column.x, -column.y, -column.z)
        return simd_normalize(vector)
    }
}

private extension CLHeading {
    var resolvedHeadingDegrees: Double {
        trueHeading >= 0 ? trueHeading : magneticHeading
    }
}

private extension CollisionGroup {
    static let target = CollisionGroup(rawValue: 1 << 0)
    static let projectile = CollisionGroup(rawValue: 1 << 1)
}

private struct CrosshairView: View {
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.white.opacity(0.9), lineWidth: 1)
                .frame(width: 40, height: 40)
            Circle()
                .strokeBorder(.white.opacity(0.5), lineWidth: 1)
                .frame(width: 18, height: 18)
            Rectangle()
                .fill(.white.opacity(0.8))
                .frame(width: 1, height: 32)
            Rectangle()
                .fill(.white.opacity(0.8))
                .frame(width: 32, height: 1)
        }
        .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 0)
    }
}

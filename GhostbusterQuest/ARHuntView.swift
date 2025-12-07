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

struct ARHuntView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine: ARHuntEngine
    private let ghostID: UUID?

    init(ghostID: UUID?) {
        self.ghostID = ghostID
        _engine = StateObject(wrappedValue: ARHuntEngine())
    }

    var body: some View {
        ZStack {
            ARHuntContainer(engine: engine)
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

    private func captureGhostAndExit() {
        if let id = ghostID {
            store.markCaptured(ghostID: id)
        }
        dismiss()
    }
}

private struct ARHuntContainer: UIViewRepresentable {
    @ObservedObject var engine: ARHuntEngine

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.automaticallyConfigureSession = false

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        view.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        engine.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

// MARK: - Engine

@MainActor
final class ARHuntEngine: ObservableObject {
    private weak var arView: ARView?
    private let anchor = AnchorEntity(world: .zero)
    private var target: ModelEntity?
    private var displayLink: CADisplayLink?
    private var time: CFTimeInterval = 0
    private var isFrozen = false
    private var freezePosition: simd_float3?
    private var defaultMaterial: RealityKit.Material = SimpleMaterial(color: .cyan, isMetallic: true)
    private var frozenMaterial: RealityKit.Material = SimpleMaterial(color: .red, isMetallic: true)
    private var projectiles: [Projectile] = []
    private let beamLength: Float = 0.5
    private let beamRadius: Float = 0.012
    private let projectileSpeed: Float = 10.0
    private let projectileSineAmplitude: Float = 0.08
    private let projectileSineFrequency: Float = 6.0 // Hz
    private let projectileSpin: Float = 5.0 // rad/sec
    private var isFiring = false
    private var lastFireTime: CFTimeInterval = 0
    private let fireInterval: CFTimeInterval = 0.02
    @Published var canCatch = false
    private var isCaptured = false

    private let orbitRadius: Float = 0.9
    private let orbitSpeed: Float = 0.75
    private let orbitHeight: Float = 0.35
    private let orbitBobAmplitude: Float = 0.08

    func attach(to view: ARView) {
        arView = view
        view.scene.addAnchor(anchor)
        setupTarget()
        startOrbitLoop()
    }

    deinit {
        displayLink?.invalidate()
    }

    func startFiring() {
        isFiring = true
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

        let size = SIMD3<Float>(beamRadius * 2, beamLength, beamRadius * 2)
        let beam = ModelEntity(
            mesh: .generateBox(size: size, cornerRadius: beamRadius * 0.5),
            materials: [SimpleMaterial(color: .red, isMetallic: true)]
        )
        beam.name = "projectile"
        let baseOrientation = simd_quatf(from: [0, 1, 0], to: forward)
        beam.orientation = baseOrientation
        let origin = transform.translation + forward * 0.25 // push spawn forward so it doesn't overlap the screen
        beam.position = origin + forward * (beamLength * 0.5)
        beam.collision = CollisionComponent(
            shapes: [ShapeResource.generateBox(size: size)],
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
            rollSign: rollSign
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

        anchor.addChild(sphere)
        target = sphere
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

        if isFiring, time - lastFireTime >= fireInterval {
            shootBeam()
            lastFireTime = time
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
            target.scale = [1.12, 1.12, 1.12]
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
        target.model?.materials = [frozenMaterial]
        target.scale = [1.12, 1.12, 1.12]
        canCatch = true
    }

    private func updateProjectiles(delta: Float) {
        guard let target else { return }
        var alive: [Projectile] = []
        let maxDistance: Float = 20
        let hitThreshold: Float = 0.14
        for projectile in projectiles {
            let age = Float(time - projectile.birthTime)
            let forwardOffset = projectile.forward * projectileSpeed * age
            let sinePhase = sin(age * .pi * 2 * projectileSineFrequency)
            let sineRamp = min(1, max(0, age * 5)) // ramp in first ~0.2s to keep spawn centered
            let sineOffset = projectile.lateral * sinePhase * projectileSineAmplitude * sineRamp
            projectile.entity.position = projectile.origin + forwardOffset + sineOffset

            let rollAngle = age * projectileSpin * projectile.rollSign
            let roll = simd_quatf(angle: rollAngle, axis: projectile.forward)
            projectile.entity.orientation = roll * projectile.baseOrientation

            let distance = simd_distance(projectile.entity.position, target.position)
            if !isFrozen && distance <= hitThreshold {
                projectile.entity.removeFromParent()
                freezeTarget()
                continue
            }

            let tooFar = simd_length(projectile.entity.position) > maxDistance
            let expired = time - projectile.birthTime > 3.0
            if tooFar || expired {
                projectile.entity.removeFromParent()
                continue
            }

            alive.append(projectile)
        }
        projectiles = alive
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
            let camPos = self.arView?.cameraTransform.translation ?? target.position
            var final = target.transform
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
}

private extension Transform {
    var forward: simd_float3 {
        let column = matrix.columns.2
        let vector = simd_float3(-column.x, -column.y, -column.z)
        return simd_normalize(vector)
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

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
    @StateObject private var engine = ARHuntEngine()

    var body: some View {
        ZStack {
            ARHuntContainer(engine: engine)
                .ignoresSafeArea()
                .onTapGesture {
                    engine.shootLaser()
                }

            CrosshairView()

            VStack {
                Spacer()
                Button {
                    engine.shootLaser()
                } label: {
                    Label("Выстрелить", systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("AR-пойма")
        .navigationBarTitleDisplayMode(.inline)
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
    private var collisionSubscription: Cancellable?
    private var time: CFTimeInterval = 0
    private var isFrozen = false
    private var freezePosition: simd_float3?
    private var defaultMaterial: Material = SimpleMaterial(color: .cyan, isMetallic: true)
    private var frozenMaterial: Material = SimpleMaterial(color: .red, isMetallic: true)

    private let orbitRadius: Float = 0.9
    private let orbitSpeed: Float = 0.75
    private let orbitHeight: Float = 0.35
    private let orbitBobAmplitude: Float = 0.08

    private let laserSpeed: Float = 14.0 // м/с — быстро, но не мгновенно
    private let laserLifetime: TimeInterval = 1.2

    func attach(to view: ARView) {
        arView = view
        view.scene.addAnchor(anchor)
        setupTarget()
        startOrbitLoop()
        subscribeToCollisions()
    }

    deinit {
        displayLink?.invalidate()
        collisionSubscription?.cancel()
    }

    func shootLaser() {
        guard let arView else { return }

        let transform = arView.cameraTransform
        let forward = transform.forward
        let origin = transform.translation + forward * 0.2

        let beamLength: Float = 0.4
        let beamRadius: Float = 0.009
        let beamSize = SIMD3<Float>(beamRadius * 2, beamLength, beamRadius * 2)
        let beam = ModelEntity(
            mesh: .generateBox(size: beamSize, cornerRadius: beamRadius * 0.6),
            materials: [SimpleMaterial(color: .red, isMetallic: true)]
        )

        beam.name = "projectile"
        beam.orientation = simd_quatf(from: [0, 1, 0], to: forward)
        beam.position = origin + forward * (beamLength * 0.5)

        beam.physicsBody = PhysicsBodyComponent(mode: .kinematic)
        beam.physicsMotion = PhysicsMotionComponent(linearVelocity: forward * laserSpeed)
        beam.collision = CollisionComponent(
            shapes: [ShapeResource.generateBox(size: beamSize)],
            filter: .init(group: .projectile, mask: [.target])
        )

        anchor.addChild(beam)

        DispatchQueue.main.asyncAfter(deadline: .now() + laserLifetime) { [weak beam] in
            beam?.removeFromParent()
        }
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
        guard let target else { return }

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

    private func subscribeToCollisions() {
        collisionSubscription = arView?.scene.subscribe(to: CollisionEvents.Began.self) { [weak self] event in
            self?.handleCollision(event)
        }
    }

    private func handleCollision(_ event: CollisionEvents.Began) {
        guard let target else { return }

        let entities = [event.entityA, event.entityB]
        let hitTarget = entities.contains(target)
        let projectile = entities.first { $0.name == "projectile" }

        guard hitTarget else { return }

        if let projectile {
            projectile.removeFromParent()
        }

        flashTarget()
    }

    private func flashTarget() {
        guard let target, var materials = target.model?.materials else { return }
        let original = materials
        materials = [SimpleMaterial(color: .yellow, isMetallic: true)]
        target.model?.materials = materials

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            target.model?.materials = original
        }
    }
}

// MARK: - Helpers

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

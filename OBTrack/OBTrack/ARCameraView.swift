// ARCameraView.swift
// Wraps RealityKit's ARView to display:
//   • Live camera feed (always shown when session is running)
//   • Yellow feature point cloud — the visual features ARKit uses for motion tracking
//   • World origin XYZ axes
//   • LiDAR scene mesh — the 3D reconstruction built from the depth sensor (toggleable)
//   • Depth heat-map overlay — per-pixel distance colourised red (near) → blue (far)

import SwiftUI
import RealityKit
import ARKit

// MARK: - ARCameraView

struct ARCameraView: UIViewRepresentable {

    /// Shared ARSession managed by ARTrackingManager
    let session: ARSession

    /// Latest depth heat-map image produced from the LiDAR depth buffer
    let depthImage: UIImage?

    /// Whether to overlay the depth heat-map
    @Binding var showDepth: Bool

    /// Whether to show the LiDAR mesh wireframe
    @Binding var showMesh: Bool

    // MARK: - UIViewRepresentable

    func makeUIView(context: Context) -> ARView {
        // automaticallyConfigureSession = false — we control the session ourselves
        let arView = ARView(frame: .zero,
                            cameraMode: .ar,
                            automaticallyConfigureSession: false)
        arView.session = session

        // Feature points (yellow dots) show what the camera-tracking algorithm is latching onto.
        // World origin draws the red/green/blue XYZ axes at the starting position.
        // Scene understanding draws the LiDAR mesh when mesh reconstruction is active.
        arView.debugOptions = [.showFeaturePoints, .showWorldOrigin, .showSceneUnderstanding]

        // Depth heat-map overlay — inserted above the camera layer
        let depthOverlay = UIImageView()
        depthOverlay.contentMode = .scaleAspectFill
        depthOverlay.alpha = 0
        depthOverlay.tag = 42
        arView.addSubview(depthOverlay)
        depthOverlay.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            depthOverlay.topAnchor.constraint(equalTo: arView.topAnchor),
            depthOverlay.bottomAnchor.constraint(equalTo: arView.bottomAnchor),
            depthOverlay.leadingAnchor.constraint(equalTo: arView.leadingAnchor),
            depthOverlay.trailingAnchor.constraint(equalTo: arView.trailingAnchor),
        ])

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // Toggle LiDAR mesh on/off
        var opts: ARView.DebugOptions = [.showFeaturePoints, .showWorldOrigin]
        if showMesh { opts.insert(.showSceneUnderstanding) }
        if uiView.debugOptions != opts { uiView.debugOptions = opts }

        // Update depth overlay visibility and image
        if let overlay = uiView.viewWithTag(42) as? UIImageView {
            let target = showDepth ? depthImage : nil
            if overlay.image !== target {
                UIView.animate(withDuration: 0.1) {
                    overlay.image = target
                    overlay.alpha = (showDepth && target != nil) ? 0.55 : 0
                }
            }
        }
    }
}

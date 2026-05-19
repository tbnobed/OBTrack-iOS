// ARTrackingManager.swift
// Manages the ARKit session for OBTrack.
// Runs ARWorldTrackingConfiguration, reads the camera transform every frame,
// and publishes position, rotation, and tracking-state updates to the UI.
// Also drives the UDP client at the configured frame rate.

import Foundation
import ARKit
import Combine

// MARK: - ARTrackingManager

final class ARTrackingManager: NSObject, ObservableObject, ARSessionDelegate {

    // MARK: - Published state (observed by ContentView)

    @Published var isTracking: Bool = false
    @Published var trackingState: String = "notAvailable"
    @Published var position: Position = Position(x: 0, y: 0, z: 0)
    @Published var rotation: Rotation = Rotation(qx: 0, qy: 0, qz: 0, qw: 1)
    @Published var frameCount: Int = 0
    @Published var udpStatus: String = "Idle"

    // MARK: - Internal

    private let session = ARSession()
    private let udpClient = UDPClient()

    /// Desired send rate in frames-per-second (30 or 60)
    var sendRate: Int = 30

    /// Interval in seconds between UDP sends
    private var sendInterval: TimeInterval { 1.0 / TimeInterval(sendRate) }
    private var lastSendTime: TimeInterval = 0

    override init() {
        super.init()
        session.delegate = self
    }

    // MARK: - Session Control

    /// Start an ARWorldTracking session and open the UDP socket.
    func startTracking(destinationIP: String, destinationPort: UInt16) {
        guard !isTracking else { return }

        // Configure ARKit for 6DOF world tracking
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity          // Y-axis aligns with gravity
        config.isAutoFocusEnabled = true

        session.run(config, options: [.resetTracking, .removeExistingAnchors])

        // Open UDP socket to the target machine
        udpClient.configure(host: destinationIP, port: destinationPort)

        lastSendTime = 0
        isTracking = true
        trackingState = "limited"
    }

    /// Stop the ARKit session and close the UDP socket.
    func stopTracking() {
        guard isTracking else { return }
        session.pause()
        udpClient.close()
        isTracking = false
        trackingState = "notAvailable"
        udpStatus = "Stopped"
    }

    // MARK: - ARSessionDelegate

    /// Called every frame by ARKit — this is where tracking data is read.
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let camera = frame.camera

        // Update tracking state string
        let stateString: String
        switch camera.trackingState {
        case .normal:
            stateString = "normal"
        case .limited(let reason):
            switch reason {
            case .initializing:    stateString = "limited (initializing)"
            case .excessiveMotion: stateString = "limited (motion)"
            case .insufficientFeatures: stateString = "limited (features)"
            case .relocalizing:    stateString = "limited (relocalizing)"
            @unknown default:      stateString = "limited"
            }
        case .notAvailable:
            stateString = "notAvailable"
        }

        // Extract position from transform column 3
        let t = camera.transform.columns.3
        let pos = Position(x: t.x, y: t.y, z: t.z)

        // Extract quaternion from the rotation portion of the 4×4 matrix
        let q = simd_quaternion(camera.transform)
        let rot = Rotation(qx: q.imag.x, qy: q.imag.y, qz: q.imag.z, qw: q.real)

        // Publish to UI on the main thread
        let currentFrame = frameCount + 1
        DispatchQueue.main.async {
            self.trackingState = stateString
            self.position = pos
            self.rotation = rot
            self.frameCount = currentFrame
        }

        // Rate-limit UDP sends to the configured FPS
        let now = frame.timestamp
        guard now - lastSendTime >= sendInterval else { return }
        lastSendTime = now

        // Build and send the JSON packet
        let packet = TrackingPacket.from(camera: camera, frame: currentFrame)
        if let data = packet.toJSONData() {
            udpClient.send(data)
        }

        // Relay UDP send status to UI
        DispatchQueue.main.async {
            self.udpStatus = self.udpClient.sendStatus
        }
    }

    /// Called when ARKit loses tracking — update state but keep session running.
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        // trackingState is already updated per-frame above; nothing extra needed here.
    }

    /// Called when an unrecoverable ARKit error occurs.
    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.trackingState = "error: \(error.localizedDescription)"
            self.isTracking = false
        }
    }

    /// Called when the ARKit session is interrupted (e.g. app goes to background).
    func sessionWasInterrupted(_ session: ARSession) {
        DispatchQueue.main.async {
            self.trackingState = "interrupted"
        }
    }

    /// Called when the ARKit session interruption ends.
    func sessionInterruptionEnded(_ session: ARSession) {
        // Re-run the configuration to resume tracking
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        session.run(config, options: [.resetTracking])
    }
}

// ARTrackingManager.swift
// Manages the ARKit session for OBTrack.
// Runs ARWorldTrackingConfiguration with optional LiDAR mesh reconstruction and
// depth semantics, reads the camera transform every frame, publishes tracking
// data to the UI, drives the UDP client at the configured frame rate, and (when
// not in Lite mode) produces a depth heat-map image from the LiDAR depth buffer
// for display in ARCameraView.

import Foundation
import ARKit
import UIKit
import Combine

// MARK: - ARTrackingManager

final class ARTrackingManager: NSObject, ObservableObject, ARSessionDelegate {

    // MARK: - Published state (observed by ContentView — ALWAYS mutated on main)

    @Published var isTracking: Bool = false
    @Published var trackingState: String = "notAvailable"
    @Published var position: Position = Position(x: 0, y: 0, z: 0)
    @Published var rotation: Rotation = Rotation(qx: 0, qy: 0, qz: 0, qw: 1)
    @Published var frameCount: Int = 0
    @Published var udpStatus: String = "Idle"

    /// Latest LiDAR depth heat-map image (nil when no depth data available or
    /// when running in Lite mode).
    @Published var depthImage: UIImage? = nil

    /// Active calibration profile. When non-nil the broadcast pose is the
    /// stage-frame *lens* pose (origin/yaw aligned, phone→lens offset applied);
    /// when nil the raw ARKit pose is broadcast unchanged.
    @Published private(set) var activeProfile: CalibrationProfile? = nil

    /// Live output trim (axis flips + position nudges). Set from TrimView,
    /// persisted to UserDefaults, and sent inside every UDP packet so the
    /// gateway applies it without any server-side action.
    @Published private(set) var trim: TrimSettings = .identity

    /// Latest raw ARKit position, updated every frame on main. Used by the
    /// calibration wizard to capture poses on a button tap.
    @Published private(set) var latestRawPositionVec: SIMD3<Float>? = nil
    @Published private(set) var latestRawQuaternion: simd_quatf?    = nil
    var latestRawPosition: SIMD3<Float>? { latestRawPositionVec }

    // MARK: - Internal

    let session = ARSession()
    private let udpClient = UDPClient()

    /// Mirror of `activeProfile`, owned by `sessionQueue`. Read every frame to
    /// avoid touching @Published off-main. Updated via `sessionQueue.async`.
    private var sessionProfile: CalibrationProfile? = nil

    /// Mirror of `trim`, owned by `sessionQueue` (same pattern as above).
    private var sessionTrim: TrimSettings = .identity

    /// Dedicated serial queue for the ARSession delegate. Keeping per-frame
    /// work off the main thread frees SwiftUI to render smoothly.
    private let sessionQueue = DispatchQueue(label: "com.obtrack.arsession",
                                             qos: .userInteractive)

    /// Desired UDP send rate in frames-per-second (30 or 60)
    var sendRate: Int = 30
    private var sendInterval: TimeInterval { 1.0 / TimeInterval(sendRate) }

    /// Mutated only on `sessionQueue`.
    private var lastSendTime: TimeInterval = 0
    private var lastDepthTime: TimeInterval = 0
    private var sendSeq: Int = 0
    private var liteMode: Bool = false

    /// Depth processing runs at 10 fps to avoid CPU overload
    private let depthInterval: TimeInterval = 1.0 / 10.0
    private let depthQueue = DispatchQueue(label: "com.obtrack.depth", qos: .utility)

    // Pre-computed jet colormap lookup table (256 entries, near=red → far=blue)
    private static let colourLUT: [(r: UInt8, g: UInt8, b: UInt8)] = {
        (0..<256).map { i in
            let t = Float(i) / 255.0
            return jetColour(t)
        }
    }()

    override init() {
        super.init()
        session.delegate = self
        // Move per-frame delegate work OFF the main thread.
        session.delegateQueue = sessionQueue

        // Bridge UDP client status updates (delivered on its own queue) to the
        // @Published `udpStatus` on main.
        udpClient.onStatusChange = { [weak self] status in
            DispatchQueue.main.async { self?.udpStatus = status }
        }

        // Restore last-active profile from disk.
        if let name = UserDefaults.standard.activeProfileName,
           let p = ProfileStore.shared.list().first(where: { $0.name == name }) {
            setActiveProfile(p)
        }

        // Restore live trim from the previous session.
        setTrim(TrimSettings.loadFromDefaults())
    }

    // MARK: - Calibration

    /// Set (or clear) the active calibration profile. Safe to call from main.
    func setActiveProfile(_ profile: CalibrationProfile?) {
        activeProfile = profile
        UserDefaults.standard.activeProfileName = profile?.name
        sessionQueue.async { [weak self] in
            self?.sessionProfile = profile
        }
    }

    /// Update the live output trim. Safe to call from main; takes effect on
    /// the next outgoing packet — including mid-take.
    func setTrim(_ newTrim: TrimSettings) {
        trim = newTrim
        newTrim.saveToDefaults()
        sessionQueue.async { [weak self] in
            self?.sessionTrim = newTrim
        }
    }

    // MARK: - Session Control

    /// Start an ARWorldTracking session and open the UDP socket.
    ///
    /// - Parameter lite: when `true`, skips LiDAR mesh reconstruction, depth
    ///   frame semantics, and the depth heat-map. Recommended for long shooting
    ///   takes to avoid thermal throttling on a device whose only job is to
    ///   stream pose.
    func startTracking(destinationIP: String,
                       destinationPort: UInt16,
                       lite: Bool = false) {
        guard !isTracking else { return }

        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        config.isAutoFocusEnabled = true

        if !lite {
            // Enable LiDAR mesh reconstruction when the device supports it (iPhone 12 Pro+)
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                config.sceneReconstruction = .mesh
            }
            // Enable depth frame semantics for the heat-map overlay
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
                config.frameSemantics.insert(.smoothedSceneDepth)
            } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                config.frameSemantics.insert(.sceneDepth)
            }
        }

        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        udpClient.configure(host: destinationIP, port: destinationPort)

        // Prevent the screen from dimming or locking while tracking is active.
        UIApplication.shared.isIdleTimerDisabled = true

        // Reset session-queue-owned counters before flipping isTracking.
        sessionQueue.async { [weak self] in
            self?.lastSendTime = 0
            self?.lastDepthTime = 0
            self?.sendSeq = 0
            self?.liteMode = lite
        }

        isTracking = true
        trackingState = "limited"
        depthImage = nil
    }

    /// Stop the ARKit session and close the UDP socket.
    func stopTracking() {
        guard isTracking else { return }
        session.pause()
        udpClient.close()

        UIApplication.shared.isIdleTimerDisabled = false

        isTracking = false
        trackingState = "notAvailable"
        udpStatus = "Stopped"
        depthImage = nil
    }

    // MARK: - ARSessionDelegate (runs on `sessionQueue`)

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let camera = frame.camera

        // Map ARKit tracking state to a display string
        let stateString: String
        switch camera.trackingState {
        case .normal:
            stateString = "normal"
        case .limited(let reason):
            switch reason {
            case .initializing:         stateString = "limited (initializing)"
            case .excessiveMotion:      stateString = "limited (motion)"
            case .insufficientFeatures: stateString = "limited (features)"
            case .relocalizing:         stateString = "limited (relocalizing)"
            @unknown default:           stateString = "limited"
            }
        case .notAvailable:
            stateString = "notAvailable"
        }

        // Raw ARKit world pose
        let t = camera.transform.columns.3
        let rawPos = SIMD3<Float>(t.x, t.y, t.z)
        let rawQuat = simd_quaternion(camera.transform)

        // Apply active calibration profile (if any). Result is stage-frame lens pose.
        let outPos: SIMD3<Float>
        let outQuat: simd_quatf
        if let prof = sessionProfile {
            (outPos, outQuat) = prof.apply(rawPosition: rawPos, rawQuaternion: rawQuat)
        } else {
            outPos  = rawPos
            outQuat = rawQuat
        }

        let pos = Position(x: outPos.x, y: outPos.y, z: outPos.z)
        let rot = Rotation(qx: outQuat.imag.x, qy: outQuat.imag.y,
                           qz: outQuat.imag.z, qw: outQuat.real)

        // Frame counter lives on the session queue so we never read a
        // @Published property off-main.
        sendSeq &+= 1
        let currentFrame = sendSeq
        let now = frame.timestamp
        let profName = sessionProfile?.name

        // Publish to UI on the main thread (raw + calibrated)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.trackingState = stateString
            self.position = pos
            self.rotation = rot
            self.frameCount = currentFrame
            self.latestRawPositionVec = rawPos
            self.latestRawQuaternion  = rawQuat
        }

        // Rate-limited UDP send (uses ARKit capture time, not wall clock)
        if now - lastSendTime >= sendInterval {
            lastSendTime = now
            let packet = TrackingPacket(
                timestamp: now,
                frame: currentFrame,
                position: pos,
                rotation: rot,
                trackingState: stateString,
                profile: profName,
                trim: sessionTrim.isIdentity ? nil : sessionTrim
            )
            if let data = packet.toJSONData() {
                udpClient.send(data)
            }
        }

        // Rate-limited depth processing from LiDAR (skipped in Lite mode)
        if !liteMode, now - lastDepthTime >= depthInterval {
            lastDepthTime = now
            if let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth {
                let pixelBuffer = depthData.depthMap
                depthQueue.async { [weak self] in
                    guard let self else { return }
                    let img = Self.depthBufferToImage(pixelBuffer, lut: Self.colourLUT)
                    DispatchQueue.main.async { self.depthImage = img }
                }
            }
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.trackingState = "error: \(error.localizedDescription)"
            self?.isTracking = false
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        DispatchQueue.main.async { [weak self] in
            self?.trackingState = "interrupted"
        }
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        // Re-enable mesh on resume only if not in Lite mode.
        let isLite = self.liteMode
        if !isLite,
           ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        session.run(config, options: [.resetTracking])
    }

    // MARK: - Depth Buffer → UIImage

    /// Convert a Float32 LiDAR depth CVPixelBuffer to a colourised UIImage.
    /// Uses a pre-computed jet colormap LUT: near (small depth) = red, far = blue.
    private static func depthBufferToImage(
        _ pixelBuffer: CVPixelBuffer,
        lut: [(r: UInt8, g: UInt8, b: UInt8)]
    ) -> UIImage? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width   = CVPixelBufferGetWidth(pixelBuffer)
        let height  = CVPixelBufferGetHeight(pixelBuffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let floats = base.assumingMemoryBound(to: Float32.self)
        let stride = rowBytes / MemoryLayout<Float32>.size

        // Pass 1: find min/max depth for normalisation (ignore non-finite values)
        var minD: Float = .greatestFiniteMagnitude
        var maxD: Float = 0
        for row in 0..<height {
            for col in 0..<width {
                let d = floats[row * stride + col]
                if d.isFinite, d > 0 {
                    if d < minD { minD = d }
                    if d > maxD { maxD = d }
                }
            }
        }
        let range = maxD - minD
        guard range > 0 else { return nil }

        // Pass 2: build RGBA bitmap using the LUT
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            for col in 0..<width {
                let d = floats[row * stride + col]
                let lutIdx: Int
                if d.isFinite, d > 0 {
                    lutIdx = min(Int(((d - minD) / range) * 255), 255)
                } else {
                    lutIdx = 0
                }
                let colour = lut[lutIdx]
                let i = (row * width + col) * 4
                rgba[i]     = colour.r
                rgba[i + 1] = colour.g
                rgba[i + 2] = colour.b
                rgba[i + 3] = 210
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        return rgba.withUnsafeMutableBytes { ptr in
            guard let ctx = CGContext(
                data: ptr.baseAddress,
                width: width, height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ), let cgImg = ctx.makeImage() else { return nil }
            return UIImage(cgImage: cgImg)
        }
    }

    /// Reversed jet colormap: t=0 (near) → red, t=1 (far) → blue
    private static func jetColour(_ t: Float) -> (r: UInt8, g: UInt8, b: UInt8) {
        let r: Float, g: Float, b: Float
        if t < 0.25 {
            let s = t / 0.25
            (r, g, b) = (1.0, s, 0.0)
        } else if t < 0.5 {
            let s = (t - 0.25) / 0.25
            (r, g, b) = (1.0 - s, 1.0, 0.0)
        } else if t < 0.75 {
            let s = (t - 0.5) / 0.25
            (r, g, b) = (0.0, 1.0, s)
        } else {
            let s = min((t - 0.75) / 0.25, 1.0)
            (r, g, b) = (0.0, 1.0 - s, 1.0)
        }
        return (UInt8(r * 255), UInt8(g * 255), UInt8(b * 255))
    }
}

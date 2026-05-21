// ARTrackingManager.swift
// Manages the ARKit session for OBTrack.
// Runs ARWorldTrackingConfiguration with LiDAR mesh reconstruction and depth semantics,
// reads the camera transform every frame, publishes tracking data to the UI,
// drives the UDP client at the configured frame rate, and produces a depth heat-map
// image from the LiDAR depth buffer for display in ARCameraView.

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

    /// Latest LiDAR depth heat-map image (nil when no depth data available)
    @Published var depthImage: UIImage? = nil

    // MARK: - Internal

    let session = ARSession()
    private let udpClient = UDPClient()

    /// Desired UDP send rate in frames-per-second (30 or 60)
    var sendRate: Int = 30
    private var sendInterval: TimeInterval { 1.0 / TimeInterval(sendRate) }
    private var lastSendTime: TimeInterval = 0

    /// Depth processing runs at 10 fps to avoid CPU overload
    private var lastDepthTime: TimeInterval = 0
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
    }

    // MARK: - Session Control

    /// Start an ARWorldTracking session with LiDAR mesh + depth, and open the UDP socket.
    func startTracking(destinationIP: String, destinationPort: UInt16) {
        guard !isTracking else { return }

        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        config.isAutoFocusEnabled = true

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

        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        udpClient.configure(host: destinationIP, port: destinationPort)

        lastSendTime = 0
        lastDepthTime = 0
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
        depthImage = nil
    }

    // MARK: - ARSessionDelegate

    /// Called every frame — read tracking data, send UDP, process depth.
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

        // Extract world-space position and quaternion from the camera transform
        let t = camera.transform.columns.3
        let pos = Position(x: t.x, y: t.y, z: t.z)
        let q = simd_quaternion(camera.transform)
        let rot = Rotation(qx: q.imag.x, qy: q.imag.y, qz: q.imag.z, qw: q.real)

        let currentFrame = frameCount + 1

        // Publish to UI on the main thread
        DispatchQueue.main.async {
            self.trackingState = stateString
            self.position = pos
            self.rotation = rot
            self.frameCount = currentFrame
        }

        // Rate-limited UDP send
        let now = frame.timestamp
        if now - lastSendTime >= sendInterval {
            lastSendTime = now
            let packet = TrackingPacket.from(camera: camera, frame: currentFrame)
            if let data = packet.toJSONData() {
                udpClient.send(data)
            }
            DispatchQueue.main.async { self.udpStatus = self.udpClient.sendStatus }
        }

        // Rate-limited depth processing from LiDAR
        if now - lastDepthTime >= depthInterval {
            lastDepthTime = now
            // Prefer smoothed depth (less noise) — fall back to raw depth
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
        DispatchQueue.main.async {
            self.trackingState = "error: \(error.localizedDescription)"
            self.isTracking = false
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        DispatchQueue.main.async { self.trackingState = "interrupted" }
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
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
                rgba[i + 3] = 210  // semi-transparent
            }
        }

        // Wrap in CGContext → CGImage → UIImage
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

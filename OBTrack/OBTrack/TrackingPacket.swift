// TrackingPacket.swift
// Defines the data model for a single AR tracking packet.
// This struct is Codable so it can be serialized to JSON for UDP transmission.

import Foundation
import ARKit

// MARK: - Sub-structures

/// 3D position in world space (meters)
struct Position: Codable {
    var x: Float
    var y: Float
    var z: Float
}

/// Quaternion rotation extracted from the ARCamera transform
struct Rotation: Codable {
    var qx: Float
    var qy: Float
    var qz: Float
    var qw: Float
}

// MARK: - Main Packet

/// The JSON packet sent via UDP for every tracking frame.
/// Matches the format specified in the OBTrack protocol.
struct TrackingPacket: Codable {
    /// Device identifier string
    var device: String = "iphone16promax"
    /// ARKit capture time (monotonic; matches `ARFrame.timestamp`). Seconds.
    var timestamp: Double
    /// Monotonically increasing frame counter
    var frame: Int
    /// World-space position of the device
    var position: Position
    /// World-space rotation of the device as a quaternion
    var rotation: Rotation
    /// ARKit tracking quality: "normal", "limited", or "notAvailable"
    var trackingState: String

    // MARK: - Factory helper

    /// Build a TrackingPacket from an ARCamera, a frame counter, and the ARKit
    /// capture time of the frame (must be `ARFrame.timestamp`, NOT wall clock).
    static func from(camera: ARCamera, frame: Int, timestamp: TimeInterval) -> TrackingPacket {
        // Extract position from the 4th column of the transform matrix (translation)
        let t = camera.transform.columns.3
        let pos = Position(x: t.x, y: t.y, z: t.z)

        // Convert the 3×3 rotation part of the transform matrix to a quaternion.
        // simd_quaternion(float4x4) uses the upper-left 3×3 of the matrix.
        let q = simd_quaternion(camera.transform)
        let rot = Rotation(qx: q.imag.x, qy: q.imag.y, qz: q.imag.z, qw: q.real)

        // Map ARCamera.TrackingState to a human-readable string
        let stateString: String
        switch camera.trackingState {
        case .normal:
            stateString = "normal"
        case .limited:
            stateString = "limited"
        case .notAvailable:
            stateString = "notAvailable"
        }

        return TrackingPacket(
            timestamp: timestamp,
            frame: frame,
            position: pos,
            rotation: rot,
            trackingState: stateString
        )
    }

    /// Serialize the packet to UTF-8 encoded JSON Data.
    func toJSONData() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return try? encoder.encode(self)
    }
}

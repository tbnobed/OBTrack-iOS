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
    /// Position. Raw ARKit world if no calibration profile is active;
    /// stage-frame lens position when a profile is active.
    var position: Position
    /// Rotation as a quaternion, matching `position` (raw ARKit or stage lens).
    var rotation: Rotation
    /// ARKit tracking quality: "normal", "limited", or "notAvailable"
    var trackingState: String
    /// Name of the active calibration profile, or nil for raw pose.
    /// Downstream tools log this so a take can be tied back to a known rig.
    var profile: String? = nil

    /// Serialize the packet to UTF-8 encoded JSON Data.
    func toJSONData() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return try? encoder.encode(self)
    }
}

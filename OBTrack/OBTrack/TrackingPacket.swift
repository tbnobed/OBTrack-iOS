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

// MARK: - Output trim

/// Live output adjustments made on the phone and applied by the gateway
/// bridge in the FreeD output frame (X = right, Y = forward, Z = up).
/// Sent inside every packet, so the operator never has to touch the
/// server — flips and nudges take effect on the next frame.
struct TrimSettings: Codable, Equatable {
    // Rotation inverts (bridge negates the angle after conversion)
    var flipPan:  Bool = false
    var flipTilt: Bool = false
    var flipRoll: Bool = false
    // Position mirrors (bridge negates the axis after conversion)
    var flipX: Bool = false
    var flipY: Bool = false
    var flipZ: Bool = false
    // Additive nudges, metres in FreeD axes (applied after mirroring)
    var offsetX: Float = 0
    var offsetY: Float = 0
    var offsetZ: Float = 0

    static let identity = TrimSettings()
    var isIdentity: Bool { self == TrimSettings.identity }

    // -- Persistence ---------------------------------------------------------
    private static let defaultsKey = "OBTrack.trimSettings"

    static func loadFromDefaults() -> TrimSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let t = try? JSONDecoder().decode(TrimSettings.self, from: data)
        else { return .identity }
        return t
    }

    func saveToDefaults() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
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
    /// Live output trim set on the phone; nil when everything is neutral.
    /// The gateway bridge applies it to the FreeD output each frame.
    var trim: TrimSettings? = nil

    /// Serialize the packet to UTF-8 encoded JSON Data.
    func toJSONData() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return try? encoder.encode(self)
    }
}

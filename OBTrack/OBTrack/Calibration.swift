// Calibration.swift
// Stage calibration for OBTrack.
//
// Concept:
//   The iPhone is a *sensor*, the cinema lens is the thing Unreal needs to
//   track. ARKit gives us the phone's pose in its own world frame; this file
//   transforms that pose into the stage's world frame, with the lens centre
//   (not the phone IMU) as the reported position.
//
// Two transforms:
//
//   T_world_align  — per-shoot. Sets where (0,0,0) is on stage and which
//                    horizontal direction is "forward". Captured live via the
//                    on-set wizard (set origin + walking-test for direction).
//
//   T_phone→lens   — per-rig.   Rigid offset between the phone IMU and the
//                    cinema lens entrance pupil. Measured once with a tape
//                    measure and saved in the profile.
//
// Math, per frame:
//   1. p_rel       = p_arkit − origin           (translate to stage origin)
//   2. p_aligned   = R_yaw · p_rel               (rotate so walked dir = ARKit −Z)
//      q_aligned   = R_yaw · q_arkit
//   3. p_lens      = p_aligned + q_aligned · lens_offset_body
//      q_lens      = q_aligned · q_lens_offset
//
// The bridge's existing FreeD axis swizzle (P_BASIS/R_BASIS) keeps working
// unchanged: the calibrated stage frame still uses ARKit-style axes
// (Y up, walked direction = −Z = forward).

import Foundation
import simd

// MARK: - Profile

/// One saved calibration profile. JSON-serialisable, shareable between phones.
struct CalibrationProfile: Codable, Identifiable, Equatable {
    var id: UUID            = UUID()
    var name: String
    var createdAt: Date     = Date()
    var notes: String       = ""

    // -- T_world_align ------------------------------------------------------
    /// ARKit-world position of the stage origin. Subtracted from every frame.
    var originX: Float = 0
    var originY: Float = 0
    var originZ: Float = 0
    /// Yaw rotation (radians, around +Y) that takes the walked direction to
    /// ARKit's −Z axis, i.e. makes "forward in the stage" = "forward in ARKit".
    var yawAlignRad: Float = 0
    /// Floor / lens height samples (Y in ARKit world, before alignment) —
    /// informational, used only for the verify-on-stage readout.
    var floorY: Float            = 0
    var lensHeightCapturedM: Float = 0    // captured (lens-Y − floor-Y)
    var lensHeightTypedM: Float    = 0    // optional user-entered override

    // -- T_phone → lens (rig offset, phone body frame) ----------------------
    // Phone body frame: +X = phone right edge, +Y = phone top edge,
    //                   +Z = out of screen (toward operator).
    var lensOffsetXmm: Float = 0      // right of phone
    var lensOffsetYmm: Float = 0      // above phone
    var lensOffsetZmm: Float = 0      // in front of screen (negative = behind = lens side)
    var lensRotPitchDeg: Float = 0
    var lensRotYawDeg: Float   = 0
    var lensRotRollDeg: Float  = 0

    // -- Derived ------------------------------------------------------------

    static let identity = CalibrationProfile(name: "Identity (no calibration)")

    var originARKit: SIMD3<Float> {
        SIMD3(originX, originY, originZ)
    }

    var yawAlignQuat: simd_quatf {
        simd_quatf(angle: yawAlignRad, axis: SIMD3<Float>(0, 1, 0))
    }

    /// Lens offset vector in phone body frame (meters).
    var lensOffsetMeters: SIMD3<Float> {
        SIMD3(lensOffsetXmm, lensOffsetYmm, lensOffsetZmm) * 0.001
    }

    /// Small rotational misalignment phone-vs-lens (phone body frame).
    var lensRotQuat: simd_quatf {
        let p = lensRotPitchDeg * .pi / 180
        let y = lensRotYawDeg   * .pi / 180
        let r = lensRotRollDeg  * .pi / 180
        let qx = simd_quatf(angle: p, axis: SIMD3<Float>(1, 0, 0))
        let qy = simd_quatf(angle: y, axis: SIMD3<Float>(0, 1, 0))
        let qz = simd_quatf(angle: r, axis: SIMD3<Float>(0, 0, 1))
        return qy * qx * qz
    }

    /// Apply this profile to a raw ARKit pose, returning the stage-frame lens pose.
    func apply(rawPosition pAR: SIMD3<Float>,
               rawQuaternion qAR: simd_quatf) -> (pos: SIMD3<Float>, quat: simd_quatf) {
        let pRel     = pAR - originARKit
        let qAlign   = yawAlignQuat
        let pAligned = qAlign.act(pRel)
        let qAligned = qAlign * qAR

        let offsetStage = qAligned.act(lensOffsetMeters)
        let pLens       = pAligned + offsetStage
        let qLens       = qAligned * lensRotQuat
        return (pLens, qLens)
    }

    // MARK: - Calibration step builders

    /// Step 1: set origin = current phone position.
    mutating func setOrigin(from p: SIMD3<Float>) {
        originX = p.x; originY = p.y; originZ = p.z
        // Origin capture also samples the floor Y (assume phone is on the
        // floor at origin; user can override in step 3).
        floorY  = p.y
    }

    /// Step 2: compute yaw so the line from `pStart` to `pEnd` becomes the
    /// stage's forward axis. Walk-distance must be ≥ ~0.3 m for a stable angle.
    mutating func setForward(from pStart: SIMD3<Float>, to pEnd: SIMD3<Float>) {
        let d = pEnd - pStart
        // Project to the horizontal plane (drop Y).
        let dx = d.x
        let dz = d.z
        let mag = sqrt(dx*dx + dz*dz)
        guard mag >= 0.05 else { return }   // refuse tiny walks
        // Yaw β around +Y that takes (dx, 0, dz) to (0, 0, −|d|): β = atan2(dx, −dz)
        yawAlignRad = atan2(dx, -dz)
    }

    /// Step 3 variant A: capture the phone at floor and at lens-height.
    mutating func setHeight(floor: SIMD3<Float>, lens: SIMD3<Float>) {
        floorY = floor.y
        lensHeightCapturedM = max(0, lens.y - floor.y)
    }

    /// Step 3 variant B: type the lens height in metres.
    mutating func setHeight(typedMeters m: Float) {
        lensHeightTypedM = m
    }

    /// The lens height the rig should report on stage (typed wins if set).
    var effectiveLensHeightM: Float {
        lensHeightTypedM > 0 ? lensHeightTypedM : lensHeightCapturedM
    }
}

// MARK: - Common rig presets for step 4

enum LensOffsetPreset: String, CaseIterable, Identifiable {
    case zero          = "None / phone at lens centre"
    case topMount50mm  = "Top mount · 50 mm lens"
    case topMount85mm  = "Top mount · 85 mm lens"
    case sideMountL    = "Side mount · left"
    case sideMountR    = "Side mount · right"
    var id: String { rawValue }

    /// (X right mm, Y above mm, Z in-front-of-screen mm).
    /// Numbers are starting points — measure with a tape and refine.
    var offsetMm: SIMD3<Float> {
        switch self {
        case .zero:         return SIMD3( 0,    0,    0)
        case .topMount50mm: return SIMD3( 0,  -85,  -30)
        case .topMount85mm: return SIMD3( 0,  -95,  -45)
        case .sideMountL:   return SIMD3(-75,   0,  -30)
        case .sideMountR:   return SIMD3( 75,   0,  -30)
        }
    }
}

// MARK: - Persistence

/// Saves / loads `CalibrationProfile` JSON files under
/// `Documents/profiles/<name>.json`. Files are shareable via the iOS share
/// sheet so the same rig calibration can be moved between phones.
final class ProfileStore {

    static let shared = ProfileStore()

    let directory: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory,
                                            in: .userDomainMask)[0]
        directory = docs.appendingPathComponent("profiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory,
                                                  withIntermediateDirectories: true)
    }

    func list() -> [CalibrationProfile] {
        guard let names = try? FileManager.default
            .contentsOfDirectory(atPath: directory.path) else { return [] }
        return names.compactMap { name -> CalibrationProfile? in
            guard name.hasSuffix(".json") else { return nil }
            let url = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else { return nil }
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            return try? dec.decode(CalibrationProfile.self, from: data)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    func save(_ profile: CalibrationProfile) throws -> URL {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(profile)
        let url  = fileURL(for: profile)
        try data.write(to: url, options: .atomic)
        return url
    }

    func delete(_ profile: CalibrationProfile) {
        try? FileManager.default.removeItem(at: fileURL(for: profile))
    }

    func fileURL(for profile: CalibrationProfile) -> URL {
        directory.appendingPathComponent("\(safeFilename(profile.name)).json")
    }

    private func safeFilename(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?*|\"<>\n\r\t")
        return name.components(separatedBy: bad)
                   .joined(separator: "_")
                   .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Active-profile name persistence

extension UserDefaults {
    private static let activeProfileKey = "OBTrack.activeProfileName"
    var activeProfileName: String? {
        get { string(forKey: Self.activeProfileKey) }
        set { setValue(newValue, forKey: Self.activeProfileKey) }
    }
}

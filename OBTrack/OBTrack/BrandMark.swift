// BrandMark.swift
// OBTrack lock-reticle identity, drawn as SwiftUI shapes so it scales and
// recolours cleanly at any size. Geometry matches the master SVG in
// Brand/obtrack-icon.svg (viewBox 0 0 120 120, stroke 8.5).

import SwiftUI

/// OBTrack brand palette.
enum BrandColor {
    static let accent      = Color(red: 0x38/255, green: 0xBD/255, blue: 0xF8/255) // sky-400
    static let accentDeep  = Color(red: 0x25/255, green: 0x63/255, blue: 0xEB/255) // blue-600
    static let inkLight    = Color(red: 0xE8/255, green: 0xEE/255, blue: 0xF6/255)
    static let inkDark     = Color(red: 0x0B/255, green: 0x12/255, blue: 0x20/255)

    static let accentGradient = LinearGradient(
        colors: [accent, accentDeep],
        startPoint: .topLeading,
        endPoint:   .bottomTrailing
    )
}

/// The four corner brackets of the reticle (each a rounded "L").
private struct ReticleBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        // Source geometry is 120×120; scale uniformly into rect.
        let s = min(rect.width, rect.height) / 120.0
        let ox = rect.midX - 60 * s
        let oy = rect.midY - 60 * s
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x * s, y: oy + y * s)
        }

        var path = Path()
        // Top-left bracket: M34 12 L18.5 12 Q12 12 12 18.5 L12 34
        path.move(to: p(34, 12))
        path.addLine(to: p(18.5, 12))
        path.addQuadCurve(to: p(12, 18.5), control: p(12, 12))
        path.addLine(to: p(12, 34))
        // Top-right
        path.move(to: p(86, 12))
        path.addLine(to: p(101.5, 12))
        path.addQuadCurve(to: p(108, 18.5), control: p(108, 12))
        path.addLine(to: p(108, 34))
        // Bottom-left
        path.move(to: p(12, 86))
        path.addLine(to: p(12, 101.5))
        path.addQuadCurve(to: p(18.5, 108), control: p(12, 108))
        path.addLine(to: p(34, 108))
        // Bottom-right
        path.move(to: p(108, 86))
        path.addLine(to: p(108, 101.5))
        path.addQuadCurve(to: p(101.5, 108), control: p(108, 108))
        path.addLine(to: p(86, 108))
        return path
    }
}

/// The OBTrack reticle: gradient brackets + white ring + accent dot.
struct OBTrackMark: View {
    /// Edge length in points. The artwork is square.
    var size: CGFloat = 28

    var body: some View {
        let unit       = size / 120.0
        let strokeW    = 8.5 * unit
        let ringDia    = 48.0 * unit   // r=24 in source
        let dotDia     = 12.0 * unit   // r=6  in source

        ZStack {
            ReticleBrackets()
                .stroke(BrandColor.accentGradient,
                        style: StrokeStyle(lineWidth: strokeW,
                                           lineCap: .round,
                                           lineJoin: .round))

            Circle()
                .stroke(BrandColor.inkLight, lineWidth: strokeW)
                .frame(width: ringDia, height: ringDia)

            Circle()
                .fill(BrandColor.accent)
                .frame(width: dotDia, height: dotDia)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("OBTrack")
    }
}

/// Mark + wordmark, matching the master lockup.
struct OBTrackLockup: View {
    var markSize: CGFloat = 28
    var showTagline: Bool = false

    var body: some View {
        HStack(spacing: markSize * 0.36) {
            OBTrackMark(size: markSize)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 0) {
                    Text("OB")
                        .foregroundStyle(BrandColor.inkLight)
                    Text("Track")
                        .foregroundStyle(BrandColor.accent)
                }
                .font(.system(size: markSize * 0.68,
                              weight: .heavy,
                              design: .default))
                .tracking(-0.5)

                if showTagline {
                    Text("6DOF CAMERA TRACKING")
                        .font(.system(size: markSize * 0.26, weight: .medium))
                        .tracking(markSize * 0.12)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
    }
}

#Preview {
    ZStack {
        BrandColor.inkDark.ignoresSafeArea()
        VStack(spacing: 32) {
            OBTrackMark(size: 96)
            OBTrackLockup(markSize: 44, showTagline: true)
            OBTrackLockup(markSize: 22)
        }
    }
}

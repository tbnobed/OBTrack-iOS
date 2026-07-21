// ContentView.swift
// Main screen for OBTrack iOS.
//
// Layout:
//   • Full-screen ARCameraView showing live camera, feature points, LiDAR mesh, and depth overlay
//   • Semi-transparent control overlay on top:
//       Portrait  — top bar + collapsible settings + bottom data/controls panel
//       Landscape — right sidebar panel (controls) | left camera (full height)

import SwiftUI
import ARKit

// MARK: - ContentView

struct ContentView: View {

    // MARK: - State

    @StateObject private var tracker = ARTrackingManager()

    // Persisted across launches — the app remembers the last server used.
    @AppStorage("OBTrack.destinationIP")   private var destinationIP: String   = "192.168.1.100"
    @AppStorage("OBTrack.destinationPort") private var destinationPort: String = "5005"
    @AppStorage("OBTrack.sendRate")        private var sendRate: Int           = 30

    /// Lite (shooting) mode — disables LiDAR mesh + depth to avoid thermal
    /// throttling during long takes. Stream pose only. Persisted.
    @AppStorage("OBTrack.liteMode") private var liteMode: Bool = false

    /// Whether the depth heat-map overlay is active
    @State private var showDepth: Bool = true
    /// Whether the LiDAR mesh wireframe is shown
    @State private var showMesh: Bool  = true
    /// Whether the settings panel is expanded
    @State private var showSettings: Bool = true
    /// Calibration wizard sheet
    @State private var showCalibration: Bool = false

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var isLandscape: Bool { verticalSizeClass == .compact }

    // MARK: - Body

    var body: some View {
        Group {
            if isLandscape {
                landscapeLayout
            } else {
                portraitLayout
            }
        }
        .sheet(isPresented: $showCalibration) {
            CalibrationView(tracker: tracker)
        }
    }

    // MARK: - Layouts

    /// Landscape: camera fills the screen, controls panel on the right
    private var landscapeLayout: some View {
        HStack(spacing: 0) {

            // Camera — fills remaining width
            cameraLayer
                .ignoresSafeArea()

            // Right sidebar
            ScrollView {
                VStack(spacing: 10) {
                    settingsPanel
                    Divider().background(.white.opacity(0.3))
                    controlButtons
                    Divider().background(.white.opacity(0.3))
                    statusPanel
                    liveDataPanel
                    visualTogglePanel
                }
                .padding(12)
            }
            .frame(width: 270)
            .background(.ultraThinMaterial)
        }
    }

    /// Portrait: camera fills the screen, controls are overlaid top and bottom
    private var portraitLayout: some View {
        ZStack(alignment: .top) {

            // Camera — full screen background
            cameraLayer
                .ignoresSafeArea()

            VStack(spacing: 0) {

                // Top bar — always visible
                topBar
                    .background(.ultraThinMaterial)

                // Collapsible settings below the top bar
                if showSettings {
                    settingsPanel
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .background(.ultraThinMaterial)
                }

                Spacer()

                // Bottom panel — status, data, controls
                VStack(spacing: 10) {
                    statusPanel
                    liveDataPanel
                    visualTogglePanel
                    controlButtons
                }
                .padding(12)
                .background(.ultraThinMaterial)
            }
        }
    }

    // MARK: - Camera Layer

    private var cameraLayer: some View {
        Group {
            if tracker.isTracking {
                ARCameraView(
                    session: tracker.session,
                    depthImage: tracker.depthImage,
                    showDepth: $showDepth,
                    showMesh: $showMesh
                )
            } else {
                // Placeholder while session is not running
                ZStack {
                    BrandColor.inkDark
                    VStack(spacing: 20) {
                        OBTrackMark(size: 84)
                        OBTrackLockup(markSize: 26, showTagline: true)
                        Text("Camera starts with tracking")
                            .foregroundStyle(.white.opacity(0.45))
                            .font(.callout)
                            .padding(.top, 12)
                    }
                }
            }
        }
    }

    // MARK: - Sub-panels

    /// Top navigation bar (portrait only)
    private var topBar: some View {
        HStack {
            OBTrackLockup(markSize: 24)

            Spacer()

            // Tracking status dot
            TrackingStateIndicator(state: tracker.trackingState)

            // Calibration wizard
            Button {
                showCalibration = true
            } label: {
                Image(systemName: "scope")
                    .foregroundStyle(tracker.activeProfile == nil
                                     ? .white : BrandColor.accent)
                    .font(.title3)
            }
            .padding(.leading, 8)

            // Settings gear toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSettings.toggle()
                }
            } label: {
                Image(systemName: showSettings ? "chevron.up.circle.fill" : "gearshape.fill")
                    .foregroundStyle(.white)
                    .font(.title3)
            }
            .padding(.leading, 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Network destination + send rate settings
    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Network", systemImage: "network")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.7))

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("IP").font(.caption2).foregroundStyle(.white.opacity(0.6))
                    TextField("192.168.1.100", text: $destinationIP)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .disabled(tracker.isTracking)
                        .font(.caption)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Port").font(.caption2).foregroundStyle(.white.opacity(0.6))
                    TextField("5005", text: $destinationPort)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .disabled(tracker.isTracking)
                        .font(.caption)
                        .frame(width: 64)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Rate").font(.caption2).foregroundStyle(.white.opacity(0.6))
                    Picker("Rate", selection: $sendRate) {
                        Text("30").tag(30)
                        Text("60").tag(60)
                    }
                    .pickerStyle(.segmented)
                    .disabled(tracker.isTracking)
                    .frame(width: 80)
                }
            }

            Toggle(isOn: $liteMode) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lite (shooting) mode")
                        .font(.caption)
                        .foregroundStyle(.white)
                    Text("No mesh, no depth — pose only. Use for long takes.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .toggleStyle(.switch)
            .tint(.green)
            .disabled(tracker.isTracking)
            .padding(.top, 4)
        }
        .padding(10)
        .background(.black.opacity(0.35))
        .cornerRadius(10)
    }

    /// Start / Stop buttons
    private var controlButtons: some View {
        HStack(spacing: 10) {
            Button(action: startTracking) {
                Label("Start", systemImage: "dot.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .font(.callout.bold())
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(tracker.isTracking)

            Button(action: stopTracking) {
                Label("Stop", systemImage: "stop.circle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .font(.callout.bold())
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(!tracker.isTracking)
        }
    }

    /// Tracking state + UDP status
    private var statusPanel: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Status").font(.caption2).foregroundStyle(.white.opacity(0.6))
                Spacer()
                TrackingStateIndicator(state: tracker.trackingState)
            }
            HStack {
                Text("UDP").font(.caption2).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text(tracker.udpStatus)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
            HStack {
                Text("Frames").font(.caption2).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text("\(tracker.frameCount)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
            }
            HStack {
                Text("Profile").font(.caption2).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text(tracker.activeProfile?.name ?? "raw (no calibration)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(tracker.activeProfile == nil
                                     ? .white.opacity(0.6)
                                     : BrandColor.accent)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(10)
        .background(.black.opacity(0.35))
        .cornerRadius(10)
    }

    /// Live position + quaternion display
    private var liveDataPanel: some View {
        VStack(spacing: 8) {
            // Position
            VStack(spacing: 4) {
                HStack {
                    Text("Position (m)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                }
                HStack(spacing: 8) {
                    DataField(label: "X", value: tracker.position.x)
                    DataField(label: "Y", value: tracker.position.y)
                    DataField(label: "Z", value: tracker.position.z)
                }
            }
            Divider().background(.white.opacity(0.2))
            // Rotation
            VStack(spacing: 4) {
                HStack {
                    Text("Quaternion")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                }
                HStack(spacing: 4) {
                    DataField(label: "QX", value: tracker.rotation.qx)
                    DataField(label: "QY", value: tracker.rotation.qy)
                    DataField(label: "QZ", value: tracker.rotation.qz)
                    DataField(label: "QW", value: tracker.rotation.qw)
                }
            }
        }
        .padding(10)
        .background(.black.opacity(0.35))
        .cornerRadius(10)
    }

    /// Toggles for depth heat-map and LiDAR mesh.
    /// Hidden entirely when Lite mode is on — there is nothing to display.
    @ViewBuilder
    private var visualTogglePanel: some View {
        if !liteMode {
            HStack(spacing: 10) {
                Toggle(isOn: $showDepth) {
                    Label("Depth", systemImage: "square.3.layers.3d")
                        .font(.caption)
                        .foregroundStyle(.white)
                }
                .toggleStyle(.button)
                .tint(.orange)

                Toggle(isOn: $showMesh) {
                    Label("Mesh", systemImage: "cube.transparent")
                        .font(.caption)
                        .foregroundStyle(.white)
                }
                .toggleStyle(.button)
                .tint(.cyan)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Actions

    private func startTracking() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        let port = UInt16(destinationPort) ?? 5005
        tracker.sendRate = sendRate
        tracker.startTracking(destinationIP: destinationIP,
                              destinationPort: port,
                              lite: liteMode)
        withAnimation { showSettings = false }
    }

    private func stopTracking() {
        tracker.stopTracking()
        withAnimation { showSettings = true }
    }
}

// MARK: - Reusable components

/// Coloured dot + label for tracking state
struct TrackingStateIndicator: View {
    let state: String

    private var color: Color {
        if state == "normal" { return .green }
        if state.hasPrefix("limited") { return .orange }
        return .red
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(state)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(color)
        }
    }
}

/// Single numeric readout with an axis label
struct DataField: View {
    let label: String
    let value: Float

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.5))
            Text(String(format: "%.3f", value))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
    }
}

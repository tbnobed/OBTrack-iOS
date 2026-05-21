// ContentView.swift
// Main screen for OBTrack iOS.
// Provides controls for starting/stopping AR tracking, configuring the UDP
// destination, selecting the send rate, and displaying live tracking data.
// Layout adapts automatically: single column in portrait, two columns in landscape
// so the phone can be mounted sideways on a camera rig.

import SwiftUI
import ARKit

// MARK: - ContentView

struct ContentView: View {

    // MARK: - State

    @StateObject private var tracker = ARTrackingManager()

    /// Destination IP address for UDP packets
    @State private var destinationIP: String = "192.168.1.100"

    /// Destination UDP port (as String for TextField binding)
    @State private var destinationPort: String = "5005"

    /// Selected send rate: 30 or 60 fps
    @State private var sendRate: Int = 30

    // Detect landscape: iPhones report verticalSizeClass = .compact in landscape
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isLandscape: Bool { verticalSizeClass == .compact }

    // MARK: - Body

    var body: some View {
        NavigationView {
            Group {
                if isLandscape {
                    // ── Landscape: two-column side-by-side layout ──────
                    // Left: settings + controls  |  Right: status + live data
                    HStack(alignment: .top, spacing: 12) {
                        ScrollView {
                            VStack(spacing: 12) {
                                settingsCard
                                controlsCard
                            }
                            .padding(.leading)
                            .padding(.vertical)
                        }
                        .frame(maxWidth: .infinity)

                        ScrollView {
                            VStack(spacing: 12) {
                                statusCard
                                liveDataCard
                            }
                            .padding(.trailing)
                            .padding(.vertical)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .background(Color(.systemGroupedBackground))
                } else {
                    // ── Portrait: single-column stacked layout ─────────
                    ScrollView {
                        VStack(spacing: 20) {
                            settingsCard
                            controlsCard
                            statusCard
                            liveDataCard
                        }
                        .padding()
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle("OBTrack")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Sub-views

    /// Network destination settings card
    private var settingsCard: some View {
        CardView(title: "Network") {
            VStack(alignment: .leading, spacing: 12) {

                LabeledField(label: "Destination IP") {
                    TextField("192.168.1.100", text: $destinationIP)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .disabled(tracker.isTracking)
                }

                LabeledField(label: "UDP Port") {
                    TextField("5005", text: $destinationPort)
                        .keyboardType(.numberPad)
                        .disabled(tracker.isTracking)
                }

                LabeledField(label: "Send Rate") {
                    Picker("Send Rate", selection: $sendRate) {
                        Text("30 fps").tag(30)
                        Text("60 fps").tag(60)
                    }
                    .pickerStyle(.segmented)
                    .disabled(tracker.isTracking)
                }
            }
        }
    }

    /// Start / Stop tracking buttons card
    private var controlsCard: some View {
        CardView(title: "Controls") {
            HStack(spacing: 16) {

                // Start Tracking button
                Button(action: startTracking) {
                    Label("Start Tracking", systemImage: "dot.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(tracker.isTracking)

                // Stop Tracking button
                Button(action: stopTracking) {
                    Label("Stop Tracking", systemImage: "stop.circle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!tracker.isTracking)
            }
        }
    }

    /// Tracking state and UDP send status card
    private var statusCard: some View {
        CardView(title: "Status") {
            VStack(alignment: .leading, spacing: 8) {

                HStack {
                    Text("Tracking")
                        .foregroundStyle(.secondary)
                    Spacer()
                    TrackingStateIndicator(state: tracker.trackingState)
                }

                HStack {
                    Text("UDP")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(tracker.udpStatus)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack {
                    Text("Frames sent")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(tracker.frameCount)")
                        .font(.system(.caption, design: .monospaced))
                }
            }
        }
    }

    /// Live position and quaternion data card
    private var liveDataCard: some View {
        CardView(title: "Live Data") {
            VStack(alignment: .leading, spacing: 12) {

                // Position display
                Group {
                    Text("Position (m)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        DataField(label: "X", value: tracker.position.x)
                        DataField(label: "Y", value: tracker.position.y)
                        DataField(label: "Z", value: tracker.position.z)
                    }
                }

                Divider()

                // Rotation display (quaternion)
                Group {
                    Text("Rotation (quaternion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        DataField(label: "QX", value: tracker.rotation.qx)
                        DataField(label: "QY", value: tracker.rotation.qy)
                        DataField(label: "QZ", value: tracker.rotation.qz)
                        DataField(label: "QW", value: tracker.rotation.qw)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func startTracking() {
        // Dismiss keyboard before starting
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)

        let port = UInt16(destinationPort) ?? 5005
        tracker.sendRate = sendRate
        tracker.startTracking(destinationIP: destinationIP, destinationPort: port)
    }

    private func stopTracking() {
        tracker.stopTracking()
    }
}

// MARK: - Reusable Sub-components

/// A rounded card container with a title header
struct CardView<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

/// A horizontally-arranged label + content pair
struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }
}

/// Displays a single float value with its axis label
struct DataField: View {
    let label: String
    let value: Float

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(String(format: "%.4f", value))
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Color-coded dot + text showing the ARKit tracking state
struct TrackingStateIndicator: View {
    let state: String

    private var color: Color {
        switch state {
        case "normal":  return .green
        case let s where s.hasPrefix("limited"): return .orange
        default:        return .red
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(state)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(color)
        }
    }
}

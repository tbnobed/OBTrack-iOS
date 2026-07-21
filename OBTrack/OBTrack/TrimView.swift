// TrimView.swift
// Live output trim sheet.
//
// Lets the operator fix mirrored / inverted motion and nudge the reported
// position WITHOUT touching the gateway. The settings ride inside every UDP
// packet ("trim" field) and freed_bridge.py applies them to the FreeD output
// on the very next frame — works mid-take, survives app restarts.

import SwiftUI

struct TrimView: View {

    @ObservedObject var tracker: ARTrackingManager
    @Environment(\.dismiss) private var dismiss

    @State private var trim: TrimSettings = .identity

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(
                        tracker.isTracking
                        ? "Streaming — changes apply instantly in Unreal / LiveFX."
                        : "Not streaming. Settings are saved and used on the next Start.",
                        systemImage: tracker.isTracking
                        ? "dot.radiowaves.left.and.right" : "pause.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(tracker.isTracking ? .green : .secondary)
                }

                Section {
                    Toggle("Invert pan (yaw)", isOn: $trim.flipPan)
                    Toggle("Invert tilt (pitch)", isOn: $trim.flipTilt)
                    Toggle("Invert roll", isOn: $trim.flipRoll)
                } header: {
                    Text("Invert rotation")
                } footer: {
                    Text("Flip one at a time: yaw the phone left — if the CG "
                         + "camera yaws right, invert pan. Then repeat for tilt "
                         + "and roll.")
                }

                Section {
                    Toggle("Mirror X (right / left)", isOn: $trim.flipX)
                    Toggle("Mirror Y (forward / back)", isOn: $trim.flipY)
                    Toggle("Mirror Z (up / down)", isOn: $trim.flipZ)
                } header: {
                    Text("Mirror position")
                } footer: {
                    Text("Walk right — if the CG camera moves left, mirror X. "
                         + "Same drill for forward (Y) and up (Z).")
                }

                Section {
                    offsetStepper("X (right)",   value: $trim.offsetX)
                    offsetStepper("Y (forward)", value: $trim.offsetY)
                    offsetStepper("Z (up)",      value: $trim.offsetZ)
                } header: {
                    Text("Nudge position (cm)")
                } footer: {
                    Text("Shifts the reported camera position in the output "
                         + "frame: X = right, Y = forward, Z = up. Applied "
                         + "after mirroring.")
                }

                Section {
                    Button("Reset all trims", role: .destructive) {
                        trim = .identity
                    }
                    .disabled(trim.isIdentity)
                }
            }
            .navigationTitle("Live Trim")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { trim = tracker.trim }
        .onChange(of: trim) { _, newValue in
            tracker.setTrim(newValue)
        }
    }

    /// Stepper editing a Float metres binding in whole centimetres.
    private func offsetStepper(_ label: String,
                               value: Binding<Float>) -> some View {
        let cm = Binding<Int>(
            get: { Int((value.wrappedValue * 100).rounded()) },
            set: { value.wrappedValue = Float($0) / 100 }
        )
        return Stepper(value: cm, in: -1000...1000) {
            HStack {
                Text(label)
                Spacer()
                Text("\(cm.wrappedValue) cm")
                    .monospacedDigit()
                    .foregroundStyle(cm.wrappedValue == 0 ? .secondary : .primary)
            }
        }
    }
}

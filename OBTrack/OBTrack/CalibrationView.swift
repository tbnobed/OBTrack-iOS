// CalibrationView.swift
// On-set calibration wizard: 5 stepped cards + profile manager.
//
// Each card is self-contained: read the instructions, tap one button.
// Designed for time-pressured stage use — minimal reading, no nested menus.

import SwiftUI
import simd

// MARK: - View-model

/// Drives the wizard. Holds a mutable draft `profile` plus the intermediate
/// captures needed before some values can be computed.
@MainActor
final class CalibrationViewModel: ObservableObject {

    @Published var profile: CalibrationProfile

    // Step 2 (forward / walking test) — captured start position.
    @Published var forwardStart: SIMD3<Float>? = nil

    // Step 3 (height) — captured floor and lens-height samples.
    @Published var floorSample: SIMD3<Float>? = nil
    @Published var lensSample:  SIMD3<Float>? = nil

    @Published var saveError: String? = nil

    init(profile: CalibrationProfile = CalibrationProfile(name: "Untitled")) {
        self.profile = profile
    }

    // MARK: Step actions — all read the latest raw ARKit pose from the tracker

    func captureOrigin(from tracker: ARTrackingManager) {
        guard let p = tracker.latestRawPosition else { return }
        profile.setOrigin(from: p)
    }

    func captureForwardStart(from tracker: ARTrackingManager) {
        forwardStart = tracker.latestRawPosition
    }

    func captureForwardEnd(from tracker: ARTrackingManager) {
        guard let start = forwardStart,
              let end   = tracker.latestRawPosition else { return }
        profile.setForward(from: start, to: end)
    }

    func captureFloor(from tracker: ARTrackingManager) {
        floorSample = tracker.latestRawPosition
        if let f = floorSample { profile.floorY = f.y }
    }

    func captureLensHeight(from tracker: ARTrackingManager) {
        lensSample = tracker.latestRawPosition
        if let f = floorSample, let l = lensSample {
            profile.setHeight(floor: f, lens: l)
        }
    }

    func resetStep2() { forwardStart = nil; profile.yawAlignRad = 0 }
    func resetStep3() { floorSample = nil; lensSample = nil
        profile.lensHeightCapturedM = 0 }
}

// MARK: - Root wizard

struct CalibrationView: View {

    @ObservedObject var tracker: ARTrackingManager
    @StateObject private var vm: CalibrationViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var stepIndex: Int = 0
    @State private var showProfilePicker: Bool = false

    init(tracker: ARTrackingManager) {
        self.tracker = tracker
        let initial = tracker.activeProfile
            ?? CalibrationProfile(name: "Untitled rig")
        _vm = StateObject(wrappedValue: CalibrationViewModel(profile: initial))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerBar
                TabView(selection: $stepIndex) {
                    step1Origin   .tag(0)
                    step2Forward  .tag(1)
                    step3Height   .tag(2)
                    step4Offset   .tag(3)
                    step5Save     .tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayStyle: .always))
                navButtons
            }
            .background(BrandColor.inkDark.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showProfilePicker = true
                    } label: {
                        Label("Profiles", systemImage: "folder")
                    }
                }
            }
            .sheet(isPresented: $showProfilePicker) {
                ProfilePickerView(tracker: tracker) { picked in
                    vm.profile = picked
                    showProfilePicker = false
                }
            }
        }
    }

    // MARK: - Step navigation

    /// Explicit Back / Next buttons — swiping between cards also works, but
    /// buttons are reliable even with the keyboard open or a scrolled card.
    private var navButtons: some View {
        HStack {
            Button {
                withAnimation { stepIndex = max(0, stepIndex - 1) }
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .disabled(stepIndex == 0)

            Spacer()

            Button {
                withAnimation { stepIndex = min(4, stepIndex + 1) }
            } label: {
                HStack(spacing: 4) {
                    Text(stepIndex == 3 ? "Next: Save" : "Next")
                    Image(systemName: "chevron.right")
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
                .font(.callout.bold())
            }
            .buttonStyle(.borderedProminent)
            .tint(BrandColor.accent)
            .disabled(stepIndex == 4)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(spacing: 4) {
            OBTrackLockup(markSize: 22)
            Text("Calibration  ·  Step \(stepIndex + 1) of 5")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
            if !tracker.isTracking {
                Text("⚠︎ Start tracking first to capture poses")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.black.opacity(0.4))
    }

    // MARK: - Steps

    private var step1Origin: some View {
        StepCard(
            number: 1, title: "Set Origin",
            blurb: "Place the phone flat on the stage's zero mark, screen up. " +
                   "Tap Capture. This becomes (0, 0, 0) in Unreal.",
            captured: "Origin (ARKit m): " +
                      vec3(SIMD3(vm.profile.originX, vm.profile.originY, vm.profile.originZ))
        ) {
            primaryButton("Capture origin", system: "scope") {
                vm.captureOrigin(from: tracker)
            }
        }
    }

    private var step2Forward: some View {
        StepCard(
            number: 2, title: "Set Forward Direction",
            blurb: "1. Stand at the origin, hold the phone naturally.\n" +
                   "2. Tap “Capture start”.\n" +
                   "3. Walk 2 m forward (whatever direction should be +X in Unreal).\n" +
                   "4. Tap “Capture end”.",
            captured: forwardCapturedText
        ) {
            HStack(spacing: 10) {
                primaryButton(
                    vm.forwardStart == nil ? "Capture start" : "Re-capture start",
                    system: "1.circle"
                ) { vm.captureForwardStart(from: tracker) }

                primaryButton(
                    "Capture end", system: "2.circle",
                    enabled: vm.forwardStart != nil
                ) { vm.captureForwardEnd(from: tracker) }
            }
            Button("Reset") { vm.resetStep2() }
                .buttonStyle(.bordered)
                .tint(.white)
        }
    }

    private var forwardCapturedText: String {
        if vm.profile.yawAlignRad == 0 && vm.forwardStart == nil {
            return "Not captured"
        }
        let deg = vm.profile.yawAlignRad * 180 / .pi
        let startStr = vm.forwardStart.map(vec3) ?? "—"
        return "Start: \(startStr)\nYaw alignment: \(fmt(deg))°"
    }

    private var step3Height: some View {
        StepCard(
            number: 3, title: "Set Camera Height",
            blurb: "Place the phone on the floor at origin, tap “Capture floor”. " +
                   "Then place it at lens height and tap “Capture lens”. " +
                   "Or just type the lens height in metres.",
            captured: heightCapturedText
        ) {
            HStack(spacing: 10) {
                primaryButton(
                    vm.floorSample == nil ? "Capture floor" : "Re-capture floor",
                    system: "arrow.down.to.line"
                ) { vm.captureFloor(from: tracker) }

                primaryButton(
                    "Capture lens",
                    system: "arrow.up.to.line",
                    enabled: vm.floorSample != nil
                ) { vm.captureLensHeight(from: tracker) }
            }

            HStack {
                Text("Type lens height (m):")
                    .foregroundStyle(.white.opacity(0.7))
                    .font(.callout)
                TextField("1.45",
                          value: $vm.profile.lensHeightTypedM,
                          format: .number)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
            }
            .padding(.top, 6)

            Button("Reset") { vm.resetStep3() }
                .buttonStyle(.bordered)
                .tint(.white)
        }
    }

    private var heightCapturedText: String {
        let captured = vm.profile.lensHeightCapturedM
        let typed    = vm.profile.lensHeightTypedM
        let eff      = vm.profile.effectiveLensHeightM
        var lines: [String] = []
        if captured > 0 { lines.append("Captured: \(fmt(captured)) m") }
        if typed   > 0  { lines.append("Typed:    \(fmt(typed)) m") }
        if eff     > 0  { lines.append("→ Using:  \(fmt(eff)) m") }
        return lines.isEmpty ? "Not set" : lines.joined(separator: "\n")
    }

    private var step4Offset: some View {
        StepCard(
            number: 4, title: "Phone-to-Lens Offset",
            blurb: "Measure with a tape from the phone IMU to the lens entrance " +
                   "pupil. Sign convention is relative to the phone body — see labels.",
            captured: ""
        ) {
            VStack(spacing: 10) {
                Picker("Preset", selection: Binding(
                    get: { LensOffsetPreset.zero },
                    set: { applyPreset($0) }
                )) {
                    ForEach(LensOffsetPreset.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

                offsetField("Right of phone (mm)",  value: $vm.profile.lensOffsetXmm)
                offsetField("Above phone (mm)",     value: $vm.profile.lensOffsetYmm)
                offsetField("In front of screen (mm) — negative = lens side",
                            value: $vm.profile.lensOffsetZmm)

                DisclosureGroup("Fine rotation (advanced)") {
                    offsetField("Pitch (°)", value: $vm.profile.lensRotPitchDeg)
                    offsetField("Yaw (°)",   value: $vm.profile.lensRotYawDeg)
                    offsetField("Roll (°)",  value: $vm.profile.lensRotRollDeg)
                }
                .tint(.white)
                .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var step5Save: some View {
        StepCard(
            number: 5, title: "Save / Load Profile",
            blurb: "Name the rig and save. Loaded profiles apply instantly to the " +
                   "live stream — Unreal will start reporting lens position.",
            captured: vm.saveError ?? ""
        ) {
            TextField("Profile name (e.g. ALEXA + 50mm top-mount)",
                      text: $vm.profile.name)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()

            HStack(spacing: 10) {
                primaryButton("Save & set active", system: "checkmark.circle.fill") {
                    saveAndActivate()
                }
                Button {
                    showProfilePicker = true
                } label: {
                    Label("Load existing", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }

            if let active = tracker.activeProfile {
                Text("Currently active: \(active.name)")
                    .font(.caption)
                    .foregroundStyle(BrandColor.accent)
                    .padding(.top, 6)
            }
        }
    }

    // MARK: - Helpers

    private func saveAndActivate() {
        do {
            try ProfileStore.shared.save(vm.profile)
            tracker.setActiveProfile(vm.profile)
            vm.saveError = "Saved ✓"
        } catch {
            vm.saveError = "Save failed: \(error.localizedDescription)"
        }
    }

    private func applyPreset(_ preset: LensOffsetPreset) {
        let v = preset.offsetMm
        vm.profile.lensOffsetXmm = v.x
        vm.profile.lensOffsetYmm = v.y
        vm.profile.lensOffsetZmm = v.z
    }

    private func offsetField(_ label: String,
                             value: Binding<Float>) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.numbersAndPunctuation)
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private func primaryButton(_ title: String,
                               system: String,
                               enabled: Bool = true,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: system)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .font(.callout.bold())
        }
        .buttonStyle(.borderedProminent)
        .tint(BrandColor.accent)
        .disabled(!enabled || !tracker.isTracking)
    }

    private func vec3(_ v: SIMD3<Float>) -> String {
        "(\(fmt(v.x)), \(fmt(v.y)), \(fmt(v.z)))"
    }

    private func fmt(_ f: Float) -> String { String(format: "%+.3f", f) }
}

// MARK: - Step card

private struct StepCard<Content: View>: View {
    let number: Int
    let title: String
    let blurb: String
    let captured: String
    @ViewBuilder var actions: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Step \(number)")
                        .font(.caption.bold())
                        .foregroundStyle(BrandColor.accent)
                    Text(title)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }

                Text(blurb)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 10) {
                    actions()
                }
                .padding(.top, 4)

                if !captured.isEmpty {
                    Text(captured)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.35))
                        .cornerRadius(8)
                }
            }
            .padding(20)
        }
        // Drag the card down to tuck the keyboard away — the decimal pad has
        // no Return key, so without this it can cover the nav buttons.
        .scrollDismissesKeyboard(.interactively)
    }
}

// MARK: - Profile picker

struct ProfilePickerView: View {

    @ObservedObject var tracker: ARTrackingManager
    let onSelect: (CalibrationProfile) -> Void

    @State private var profiles: [CalibrationProfile] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if profiles.isEmpty {
                    Text("No saved profiles yet — finish the wizard and save one.")
                        .foregroundStyle(.secondary)
                }
                ForEach(profiles) { p in
                    Button {
                        onSelect(p)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(.headline)
                            Text(p.createdAt.formatted(date: .abbreviated,
                                                       time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { idx in
                    for i in idx { ProfileStore.shared.delete(profiles[i]) }
                    profiles = ProfileStore.shared.list()
                }
            }
            .navigationTitle("Profiles")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        tracker.setActiveProfile(nil)
                        dismiss()
                    } label: {
                        Label("Clear active", systemImage: "xmark.circle")
                    }
                }
            }
            .onAppear { profiles = ProfileStore.shared.list() }
        }
    }
}

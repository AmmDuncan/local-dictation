import AppKit
import AVFoundation
import SwiftUI

struct AudioInputSection: View {
    @Binding var deviceUID: String
    var isActive: Bool

    @State private var meter = AudioLevelMeter()
    @State private var devices: [AudioInputDevice] = []
    @State private var micAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

    var body: some View {
        Picker("Microphone", selection: $deviceUID) {
            Text("System Default").tag("")
            ForEach(devices) { device in
                Text(device.name).tag(device.uid)
            }
        }

        Group {
            if micAuthorized {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Input level")
                    LevelMeterBar(level: meter.level)
                        .frame(height: 26)
                    Text("Speak to test — aim for the green range")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                LabeledContent("Input level") {
                    Text("Available once microphone access is granted")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            micAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            devices = AudioDevices.inputDevices()
            if isActive { meter.start(deviceUID: deviceUID) }
        }
        .onDisappear {
            meter.stop()
        }
        // Run the mic-opening meter only while this tab is showing — switching
        // tabs doesn't fire onDisappear on macOS, so drive it off `isActive`.
        .onChange(of: isActive) {
            if isActive {
                devices = AudioDevices.inputDevices()
                meter.start(deviceUID: deviceUID)
            } else {
                meter.stop()
            }
        }
        .onChange(of: deviceUID) {
            if isActive { meter.restart(deviceUID: deviceUID) }
        }
        // Free the mic if the app is backgrounded / Settings window closed while
        // this tab is open (so Bluetooth headphones return to high quality).
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            meter.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if isActive { meter.start(deviceUID: deviceUID) }
        }
    }
}

/// Segmented level meter: filled bars track the current input level, greener as
/// it rises toward clipping.
private struct LevelMeterBar: View {
    var level: Double

    private let barCount = 18

    var body: some View {
        GeometryReader { geometry in
            let lit = Int((level * Double(barCount)).rounded())
            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color(for: index, lit: lit))
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: geometry.size.width)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Input level")
        .accessibilityValue("\(Int((level * 100).rounded())) percent")
    }

    private func color(for index: Int, lit: Int) -> Color {
        guard index < lit else {
            return Color.secondary.opacity(0.18)
        }
        if index >= barCount - 2 {
            return .red
        }
        if index >= barCount - 5 {
            return .yellow
        }
        return Brand.emerald
    }
}

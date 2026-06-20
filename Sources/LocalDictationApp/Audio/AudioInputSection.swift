import AVFoundation
import SwiftUI

struct AudioInputSection: View {
    @Binding var deviceUID: String

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

        LabeledContent("Input level") {
            if micAuthorized {
                LevelMeterBar(level: meter.level)
                    .frame(height: 18)
            } else {
                Text("Available once microphone access is granted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            micAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            devices = AudioDevices.inputDevices()
            meter.start(deviceUID: deviceUID)
        }
        .onDisappear {
            meter.stop()
        }
        .onChange(of: deviceUID) {
            meter.restart(deviceUID: deviceUID)
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
        return .green
    }
}

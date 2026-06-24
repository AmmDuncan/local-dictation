import Foundation

/// Minimal view of a Core Audio input device needed to pick one. The app's
/// `AudioInputDevice` conforms to this; tests use a lightweight stand-in.
public protocol AudioInputDeviceInfo {
    var deviceID: UInt32 { get }
    var uid: String { get }
    var isBluetooth: Bool { get }
    var isBuiltIn: Bool { get }
}

/// Pure input-device selection policy (no Core Audio calls, so it's testable).
public enum AudioInputSelection {
    /// Pick the input device to record from, for a saved UID:
    /// - An explicitly chosen, still-present device is honored as-is — even if
    ///   it's Bluetooth (the user asked for it).
    /// - Otherwise ("System Default", or a saved device that's gone) return
    ///   `nil` — record from the live OS default as-is, whatever it is
    ///   (including Bluetooth). Auto-detecting a Bluetooth default to steer
    ///   around it proved unreliable: AirPods' device identity and state shift
    ///   between connects and A2DP/HFP modes, so the result was inconsistent.
    ///   Following the OS default is predictable; the Settings copy warns that a
    ///   Bluetooth mic records in lower-quality call mode.
    ///
    /// A non-nil result is the device the caller must actively bind. The engine
    /// reliably captures only its *own default* input, so the caller makes this
    /// device the system default for the recording (see `AudioFileRecorder`),
    /// rather than forcing it via the audio unit's `CurrentDevice` override —
    /// that override silently delivers no audio.
    public static func choose<Device: AudioInputDeviceInfo>(
        uid: String,
        devices: [Device]
    ) -> UInt32? {
        guard !uid.isEmpty, let explicit = devices.first(where: { $0.uid == uid }) else {
            return nil
        }
        return explicit.deviceID
    }
}

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
    /// Pick the input device to bind for a saved UID:
    /// - An explicitly chosen, still-present device is honored as-is — even if
    ///   it's Bluetooth (the user asked for it).
    /// - Otherwise ("System Default", or a saved device that's gone) follow the
    ///   OS default, EXCEPT when that default is Bluetooth and a built-in mic
    ///   exists — then prefer built-in. A Bluetooth mic forces the device into
    ///   low-quality HFP/SCO call mode and negotiates slowly/unreliably.
    /// - `nil` means "no override" — the caller leaves the engine on its default.
    public static func choose<Device: AudioInputDeviceInfo>(
        uid: String,
        devices: [Device],
        systemDefaultID: UInt32?
    ) -> UInt32? {
        if !uid.isEmpty, let explicit = devices.first(where: { $0.uid == uid }) {
            return explicit.deviceID
        }
        guard let defaultID = systemDefaultID,
              let current = devices.first(where: { $0.deviceID == defaultID }),
              current.isBluetooth else {
            return nil
        }
        return devices.first(where: { $0.isBuiltIn })?.deviceID
    }
}

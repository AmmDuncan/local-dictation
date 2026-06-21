import AppKit
import SwiftUI

// MARK: - Brand palette

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

/// The shared visual language for the dictation surfaces — an emerald "signal"
/// green over a teal base. The overlay HUD and the review panel both draw from
/// this so they read as one app, not two screens bolted together.
enum Brand {
    static let emerald = Color(hex: 0x2FD6A3)
    static let teal = Color(hex: 0x0A7D63)
    static let signal = LinearGradient(
        colors: [Color(hex: 0x2FD6A3), Color(hex: 0x13B287), Color(hex: 0x0A7D63)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let error = LinearGradient(
        colors: [Color(hex: 0xFF8A6B), Color(hex: 0xFF5D5D)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let onSignal = Color(hex: 0x06231B)

    /// Foreground ink for the given scheme — near-white on dark, near-black on light.
    static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xF4F8F6) : Color(hex: 0x0E1A16)
    }
}

// MARK: - Shared chrome

/// Real system blur behind a panel (picks up the live desktop + light/dark),
/// masked to a rounded rect so the blur's own square corners don't show.
struct VisualEffectView: NSViewRepresentable {
    var cornerRadius: CGFloat = 26

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = Self.roundedMask(radius: cornerRadius)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.maskImage = Self.roundedMask(radius: cornerRadius)
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.set()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Emerald capsule button for primary actions on the dictation surfaces.
struct SignalButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Brand.onSignal)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(Brand.signal))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

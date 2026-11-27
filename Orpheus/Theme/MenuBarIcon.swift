import AppKit
import SwiftUI

/// Orpheus's lyre, drawn in a unit square (y pointing down) so it scales from the menu bar
/// to the app icon. The app icon in the asset catalog uses the same geometry.
enum LyreGeometry {
    /// The part of the unit square the lyre occupies, so it can be drawn at full size.
    static let bounds = CGRect(x: 0.04, y: 0.03, width: 0.92, height: 0.88)

    /// The two arms, with their curled horns, and the crossbar.
    static let frame: CGPath = {
        let path = CGMutablePath()
        for mirrored in [false, true] {
            let x: (CGFloat) -> CGFloat = mirrored ? { 1 - $0 } : { $0 }
            path.move(to: CGPoint(x: x(0.38), y: 0.80))
            path.addCurve(
                to: CGPoint(x: x(0.27), y: 0.17),
                control1: CGPoint(x: x(0.12), y: 0.70),
                control2: CGPoint(x: x(0.08), y: 0.32)
            )
            path.addQuadCurve(to: CGPoint(x: x(0.17), y: 0.08), control: CGPoint(x: x(0.29), y: 0.07))
        }
        path.move(to: CGPoint(x: 0.22, y: 0.27))
        path.addLine(to: CGPoint(x: 0.78, y: 0.27))
        return path
    }()

    /// The base the arms rest on.
    static let base = CGPath(
        roundedRect: CGRect(x: 0.27, y: 0.74, width: 0.46, height: 0.13),
        cornerWidth: 0.045,
        cornerHeight: 0.045,
        transform: nil
    )

    /// The strings.
    /// - Parameter positions: Horizontal positions in the unit square.
    /// - Returns: One vertical line per string.
    static func strings(at positions: [CGFloat]) -> CGPath {
        let path = CGMutablePath()
        for x in positions {
            path.move(to: CGPoint(x: x, y: 0.27))
            path.addLine(to: CGPoint(x: x, y: 0.75))
        }
        return path
    }
}

/// The menu-bar icon: a monochrome lyre at full size, with no background.
///
/// Like a template image, the lyre is white on a dark menu bar and black on a light one.
/// It is not a template image so the strings can show the state in the theme colours:
/// the same colour as the lyre normally, yellow when an app is boosted, pink when the
/// output is muted.
enum MenuBarIcon {
    /// What the icon shows.
    enum State: Hashable {
        case normal
        case muted
        case boosted
    }

    private static let pointSize = NSSize(width: 18, height: 18)
    /// Stroke widths as a fraction of the icon size.
    private static let armWidth: CGFloat = 0.12
    private static let stringWidth: CGFloat = 0.075
    private static let stringPositions: [CGFloat] = [0.42, 0.5, 0.58]
    private static let lightBarOpacity: CGFloat = 0.85
    private static var cache: [State: NSImage] = [:]

    /// The icon image for a state, created once and cached.
    ///
    /// The image draws lazily, so it follows the menu bar's appearance each time it is drawn.
    /// - Parameters:
    ///   - state: The state to show.
    ///   - theme: The theme providing the state colours.
    /// - Returns: The image.
    @MainActor
    static func image(for state: State, theme: Theme = .neon) -> NSImage {
        if let cached = cache[state] { return cached }
        let accent: NSColor? = switch state {
        case .normal: nil
        case .boosted: NSColor(theme.accentBoost)
        case .muted: NSColor(theme.accentAction)
        }
        let image = NSImage(size: pointSize, flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let isDark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let ink = isDark ? NSColor.white : NSColor.black.withAlphaComponent(lightBarOpacity)
            draw(in: context, rect: rect, frameColor: ink.cgColor, stringColor: (accent ?? ink).cgColor)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Orpheus"
        cache[state] = image
        return image
    }

    /// Draws the lyre stretched to fill `rect`.
    private static func draw(in context: CGContext, rect: CGRect, frameColor: CGColor, stringColor: CGColor) {
        let size = min(rect.width, rect.height)
        let bounds = LyreGeometry.bounds
        var transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width / bounds.width, y: rect.height / bounds.height)
            .translatedBy(x: -bounds.minX, y: -bounds.minY)

        context.saveGState()
        defer { context.restoreGState() }
        context.setLineCap(.round)
        context.setLineJoin(.round)

        if let strings = LyreGeometry.strings(at: stringPositions).copy(using: &transform) {
            context.addPath(strings)
            context.setStrokeColor(stringColor)
            context.setLineWidth(size * stringWidth)
            context.strokePath()
        }
        if let frame = LyreGeometry.frame.copy(using: &transform) {
            context.addPath(frame)
            context.setStrokeColor(frameColor)
            context.setLineWidth(size * armWidth)
            context.strokePath()
        }
        if let base = LyreGeometry.base.copy(using: &transform) {
            context.addPath(base)
            context.setFillColor(frameColor)
            context.fillPath()
        }
    }
}

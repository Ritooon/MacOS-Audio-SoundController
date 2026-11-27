import AppKit
import SwiftUI

/// Orpheus's lyre, drawn in a unit square so it scales from the menu bar to the app icon.
/// The app icon in the asset catalog uses the same geometry.
struct LyreGlyph: View {
    var frameColor: Color
    var stringColor: Color
    /// Stroke width of the arms and crossbar, as a fraction of the size.
    var armWidth: CGFloat = 0.09
    /// Stroke width of the strings, as a fraction of the size.
    var stringWidth: CGFloat = 0.035
    var stringPositions: [CGFloat] = [0.41, 0.47, 0.53, 0.59]

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                Self.strings(stringPositions)
                    .stroke(stringColor, style: StrokeStyle(lineWidth: size * stringWidth, lineCap: .round))
                Self.frame()
                    .stroke(frameColor, style: StrokeStyle(lineWidth: size * armWidth, lineCap: .round, lineJoin: .round))
                Self.base()
                    .fill(frameColor)
            }
            .frame(width: size, height: size)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private static func frame() -> UnitShape {
        UnitShape { path in
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
        }
    }

    private static func strings(_ positions: [CGFloat]) -> UnitShape {
        UnitShape { path in
            for x in positions {
                path.move(to: CGPoint(x: x, y: 0.27))
                path.addLine(to: CGPoint(x: x, y: 0.76))
            }
        }
    }

    private static func base() -> UnitShape {
        UnitShape { path in
            path.addRoundedRect(
                in: CGRect(x: 0.27, y: 0.74, width: 0.46, height: 0.13),
                cornerSize: CGSize(width: 0.045, height: 0.045)
            )
        }
    }
}

/// A shape described in a unit square and scaled to its rect.
private struct UnitShape: Shape {
    let build: (inout Path) -> Void

    func path(in rect: CGRect) -> Path {
        var path = Path()
        build(&path)
        let size = min(rect.width, rect.height)
        return path.applying(
            CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: size, y: size)
        )
    }
}

/// The coloured menu-bar icon: the lyre on a small game tile whose colour shows the state.
enum MenuBarIcon {
    /// What the icon shows.
    enum State: Hashable {
        case normal
        case muted
        case boosted
    }

    private static let pointSize: CGFloat = 18
    private static let tileInset: CGFloat = 1
    private static let glyphInset: CGFloat = 3
    private static let renderScale: CGFloat = 2
    private static var cache: [State: NSImage] = [:]

    /// The icon image for a state, rendered once and cached.
    /// - Parameters:
    ///   - state: The state to show.
    ///   - theme: The theme providing the colours.
    /// - Returns: A non-template image, so the theme colours show in the menu bar.
    @MainActor
    static func image(for state: State, theme: Theme = .neon) -> NSImage {
        if let cached = cache[state] { return cached }
        let tileColor: Color = switch state {
        case .normal: theme.accentPrimary
        case .muted: theme.accentAction
        case .boosted: theme.accentBoost
        }
        let content = ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(tileColor)
                .padding(tileInset)
            LyreGlyph(
                frameColor: theme.background,
                stringColor: theme.background,
                armWidth: 0.12,
                stringWidth: 0.07,
                stringPositions: [0.43, 0.5, 0.57]
            )
            .padding(glyphInset)
        }
        .frame(width: pointSize, height: pointSize)

        let renderer = ImageRenderer(content: content)
        renderer.scale = renderScale
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: nil) ?? NSImage()
        image.isTemplate = false
        image.accessibilityDescription = "Orpheus"
        cache[state] = image
        return image
    }
}

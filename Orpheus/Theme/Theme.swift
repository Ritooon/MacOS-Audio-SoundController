import AppKit
import SwiftUI

/// A set of colour tokens for the Orpheus panel.
///
/// Views read colours only from a `Theme`, never from hex values, so another theme
/// (Rétro 8-bit, Cosmos…) is just another set of tokens in the asset catalog.
struct Theme: Equatable {
    let name: String
    /// Panel background.
    let background: Color
    /// Main cards.
    let surface: Color
    /// Secondary cards, collapsed sections, icon buttons, bar tracks.
    let surfaceMuted: Color
    /// Titles, app and device names.
    let textPrimary: Color
    /// Subtitles and captions.
    let textSecondary: Color
    /// Inactive rows and muted items.
    let textDisabled: Color
    /// Default accent: badges, checkboxes, selected pickers, links.
    let accentPrimary: Color
    /// Volume bars and anything boost-related.
    let accentBoost: Color
    /// Background of yellow value chips.
    let boostChipBackground: Color
    /// Main action button, mute state, live indicator.
    let accentAction: Color
    /// Active, connected and "in use" states.
    let accentSuccess: Color
    /// Device and hardware information.
    let accentInfo: Color
    /// Background of info cards.
    let infoSurface: Color

    /// The default "Néon" theme.
    static let neon = Theme(name: "Néon", catalogFolder: "Theme")

    /// Loads a theme from a folder of colour sets in the asset catalog.
    /// - Parameters:
    ///   - name: The theme's display name.
    ///   - catalogFolder: The asset-catalog folder that holds one colour set per token.
    private init(name: String, catalogFolder: String) {
        func token(_ key: String) -> Color {
            Color("\(catalogFolder)/\(key)", bundle: .main)
        }
        self.name = name
        background = token("background")
        surface = token("surface")
        surfaceMuted = token("surfaceMuted")
        textPrimary = token("textPrimary")
        textSecondary = token("textSecondary")
        textDisabled = token("textDisabled")
        accentPrimary = token("accentPrimary")
        accentBoost = token("accentBoost")
        boostChipBackground = token("boostChipBackground")
        accentAction = token("accentAction")
        accentSuccess = token("accentSuccess")
        accentInfo = token("accentInfo")
        infoSurface = token("infoSurface")
    }

    /// The darker shade used for the "chunky" bottom edge of buttons and tiles.
    /// - Parameter color: The base colour.
    /// - Returns: The same colour, darkened.
    static func edge(of color: Color) -> Color {
        let base = NSColor(color)
        return Color(nsColor: base.blended(withFraction: Metrics.edgeDarkening, of: .black) ?? base)
    }
}

// MARK: - Metrics

extension Theme {
    /// Sizes shared by every component.
    enum Metrics {
        static let panelWidth: CGFloat = 360
        static let panelPadding: CGFloat = 16
        static let sectionSpacing: CGFloat = 14
        static let cardCornerRadius: CGFloat = 22
        static let cardPadding: CGFloat = 16
        static let tileSize: CGFloat = 38
        static let tileCornerRadius: CGFloat = 12
        static let iconButtonSize: CGFloat = 30
        static let iconButtonCornerRadius: CGFloat = 9
        static let barThickness: CGFloat = 10
        static let barHitHeight: CGFloat = 22
        static let chunkyDepth: CGFloat = 4
        static let edgeDarkening: CGFloat = 0.45
        static let contrastBorderWidth: CGFloat = 1
        static let glowRadius: CGFloat = 6
        static let toastDuration: Duration = .seconds(2)
    }
}

// MARK: - Typography

extension Theme {
    /// PostScript name of the bundled display font (Space Grotesk Bold, SIL OFL).
    private static let displayFontName = "SpaceGrotesk-Bold"

    /// The display font, for titles, section headers and big numbers.
    /// - Parameters:
    ///   - size: The point size at the default Dynamic Type size; never below 11 pt.
    ///   - style: The text style it scales with.
    /// - Returns: The font.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .headline) -> Font {
        .custom(displayFontName, size: max(size, minimumFontSize), relativeTo: style)
    }

    /// The smallest font size used anywhere in the panel.
    static let minimumFontSize: CGFloat = 11
}

// MARK: - Motion

extension Theme {
    /// The springy animation used for presses, toggles, sections and toasts,
    /// or a simple fade when Reduce Motion is on.
    /// - Parameter reduceMotion: The value of `accessibilityReduceMotion`.
    /// - Returns: The animation.
    static func motion(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.7)
    }
}

// MARK: - Environment

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.neon
}

extension EnvironmentValues {
    /// The theme of the panel.
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

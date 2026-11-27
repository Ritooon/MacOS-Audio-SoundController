import AppKit
import SwiftUI

/// The themes the user can pick for the panel.
enum ThemeID: String, CaseIterable, Identifiable {
    case neon
    case retro
    case cosmos
    case sylve
    case magma
    case givre
    case abysses

    var id: String { rawValue }

    /// Reads a saved identifier, falling back to Néon for missing or unknown values.
    /// - Parameter rawValue: The saved string, if any.
    /// - Returns: The matching theme identifier, or `.neon`.
    static func resolve(_ rawValue: String?) -> ThemeID {
        rawValue.flatMap(ThemeID.init(rawValue:)) ?? .neon
    }
}

/// A set of colour, shape and typography tokens for the Orpheus panel.
///
/// Views read colours, corner radii and the display font only from a `Theme`, never from
/// hard-coded values, so each theme is just another set of tokens. Colours live in the asset
/// catalog, one folder per theme.
struct Theme: Equatable, Identifiable {
    let id: ThemeID
    /// The display name shown in the theme picker.
    let name: String
    /// Whether the panel uses light backgrounds (dark text, light system controls).
    let isLight: Bool
    /// Corner radii and bar style.
    let shape: ShapeTokens
    /// The display font and how it is sized.
    let typography: Typography
    /// The small ornament drawn in the header.
    let decoration: Decoration

    /// Panel background.
    let background: Color
    /// A soft glow blended over the panel background, for atmosphere.
    let backgroundGlow: Color
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
    /// Background of boost value chips.
    let boostChipBackground: Color
    /// Text of boost value chips.
    let boostChipText: Color
    /// Main action button, mute state, live indicator.
    let accentAction: Color
    /// Active, connected and "in use" states.
    let accentSuccess: Color
    /// Device and hardware information.
    let accentInfo: Color
    /// Background of info cards.
    let infoSurface: Color
    /// Symbols and text drawn on a filled accent (tiles, toasts, checkmarks).
    let onAccent: Color

    // MARK: Themes

    /// The default "Néon" theme.
    static let neon = Theme(
        id: .neon, name: "Néon", catalogFolder: "Theme",
        shape: ShapeTokens(card: 22, control: 16, tile: 12, iconButton: 9, bar: ShapeTokens.pill, chip: ShapeTokens.pill, checkbox: 6),
        typography: Typography(fontName: "SpaceGrotesk-Bold", scale: 1, tracking: 1),
        decoration: .squares
    )

    /// "Rétro 8-bit": an 80s game menu, square corners, pixel font and block bars.
    static let retro = Theme(
        id: .retro, name: "Rétro 8-bit", catalogFolder: "ThemeRetro",
        shape: ShapeTokens(card: 0, control: 0, tile: 0, iconButton: 0, bar: 0, chip: 0, checkbox: 0, barThickness: 12, isBarSegmented: true),
        typography: Typography(fontName: "PressStart2P-Regular", scale: 0.62, tracking: 0),
        decoration: .pixels
    )

    /// "Cosmos": a spaceship cockpit with a nebula glow and a round porthole tile.
    static let cosmos = Theme(
        id: .cosmos, name: "Cosmos", catalogFolder: "ThemeCosmos",
        shape: ShapeTokens(card: 22, control: 12, tile: 19, iconButton: 15, bar: ShapeTokens.pill, chip: ShapeTokens.pill, checkbox: 6),
        typography: Typography(fontName: "Orbitron-Black", scale: 0.82, tracking: 1.6),
        decoration: .planet
    )

    /// "Sylve": an enchanted forest, moss green and treasure gold.
    static let sylve = Theme(
        id: .sylve, name: "Sylve", catalogFolder: "ThemeSylve",
        shape: ShapeTokens(card: 18, control: 10, tile: 12, iconButton: 8, bar: ShapeTokens.pill, chip: ShapeTokens.pill, checkbox: 6),
        typography: Typography(fontName: "CinzelRoman-Black", scale: 0.95, tracking: 0.8),
        decoration: .leaves
    )

    /// "Magma": a volcano level, lava bars and a glowing boost.
    static let magma = Theme(
        id: .magma, name: "Magma", catalogFolder: "ThemeMagma",
        shape: ShapeTokens(card: 16, control: 10, tile: 10, iconButton: 8, bar: ShapeTokens.pill, chip: ShapeTokens.pill, checkbox: 6),
        typography: Typography(fontName: "Bungee-Regular", scale: 0.88, tracking: 0.4),
        decoration: .embers
    )

    /// "Givre": the optional light theme, glacier blue with an orange boost.
    static let givre = Theme(
        id: .givre, name: "Givre", catalogFolder: "ThemeGivre", isLight: true,
        shape: ShapeTokens(card: 24, control: 14, tile: 14, iconButton: 10, bar: ShapeTokens.pill, chip: ShapeTokens.pill, checkbox: 7),
        typography: Typography(fontName: "Fredoka-Bold", scale: 1.05, tracking: 0.5),
        decoration: .crystals
    )

    /// "Abysses": the deep sea, round shapes and bioluminescent turquoise.
    static let abysses = Theme(
        id: .abysses, name: "Abysses", catalogFolder: "ThemeAbysses",
        shape: ShapeTokens(card: 26, control: 16, tile: 19, iconButton: 15, bar: ShapeTokens.pill, chip: ShapeTokens.pill, checkbox: 10),
        typography: Typography(fontName: "Righteous-Regular", scale: 1, tracking: 1),
        decoration: .bubbles
    )

    /// Every theme, in the order shown in the picker.
    static let all: [Theme] = [.neon, .retro, .cosmos, .sylve, .magma, .givre, .abysses]

    /// The theme for an identifier.
    /// - Parameter id: The theme identifier.
    /// - Returns: The matching theme.
    static func theme(for id: ThemeID) -> Theme {
        all.first { $0.id == id } ?? .neon
    }

    /// Loads a theme's colours from a folder of colour sets in the asset catalog.
    /// - Parameters:
    ///   - id: The theme identifier.
    ///   - name: The theme's display name.
    ///   - catalogFolder: The asset-catalog folder that holds one colour set per token.
    ///   - isLight: Whether the theme uses light backgrounds.
    ///   - shape: Corner radii and bar style.
    ///   - typography: The display font.
    ///   - decoration: The header ornament.
    private init(
        id: ThemeID,
        name: String,
        catalogFolder: String,
        isLight: Bool = false,
        shape: ShapeTokens,
        typography: Typography,
        decoration: Decoration
    ) {
        func token(_ key: String) -> Color {
            Color("\(catalogFolder)/\(key)", bundle: .main)
        }
        self.id = id
        self.name = name
        self.isLight = isLight
        self.shape = shape
        self.typography = typography
        self.decoration = decoration
        background = token("background")
        backgroundGlow = token("backgroundGlow")
        surface = token("surface")
        surfaceMuted = token("surfaceMuted")
        textPrimary = token("textPrimary")
        textSecondary = token("textSecondary")
        textDisabled = token("textDisabled")
        accentPrimary = token("accentPrimary")
        accentBoost = token("accentBoost")
        boostChipBackground = token("boostChipBackground")
        boostChipText = token("boostChipText")
        accentAction = token("accentAction")
        accentSuccess = token("accentSuccess")
        accentInfo = token("accentInfo")
        infoSurface = token("infoSurface")
        onAccent = token("onAccent")
    }

    static func == (lhs: Theme, rhs: Theme) -> Bool {
        lhs.id == rhs.id
    }

    /// The darker shade used for the "chunky" bottom edge of buttons and tiles.
    /// - Parameter color: The base colour.
    /// - Returns: The same colour, darkened.
    static func edge(of color: Color) -> Color {
        let base = NSColor(color)
        return Color(nsColor: base.blended(withFraction: Metrics.edgeDarkening, of: .black) ?? base)
    }
}

// MARK: - Shape tokens

extension Theme {
    /// Corner radii and bar style of a theme.
    struct ShapeTokens: Equatable {
        /// A radius large enough to turn any rounded rectangle into a capsule.
        static let pill: CGFloat = 999

        /// Main cards.
        var card: CGFloat
        /// Pickers, info cards, banners and other inner panels.
        var control: CGFloat
        /// The header badge tile.
        var tile: CGFloat
        /// Icon buttons and app icons.
        var iconButton: CGFloat
        /// Volume bar tracks and segment indicators.
        var bar: CGFloat
        /// Value chips and toasts.
        var chip: CGFloat
        /// Checkboxes.
        var checkbox: CGFloat
        /// Volume bar thickness.
        var barThickness: CGFloat = 10
        /// Whether volume bars are drawn as separate blocks, like a game health gauge.
        var isBarSegmented = false
    }
}

// MARK: - Decoration

extension Theme {
    /// The ornament drawn in the header, next to the settings button.
    enum Decoration: Equatable {
        case squares
        case pixels
        case planet
        case leaves
        case embers
        case crystals
        case bubbles
    }
}

// MARK: - Metrics

extension Theme {
    /// Sizes shared by every theme.
    enum Metrics {
        static let panelWidth: CGFloat = 360
        static let panelPadding: CGFloat = 16
        static let sectionSpacing: CGFloat = 14
        static let cardPadding: CGFloat = 16
        static let tileSize: CGFloat = 38
        static let iconButtonSize: CGFloat = 30
        static let barHitHeight: CGFloat = 22
        static let barSegmentWidth: CGFloat = 8
        static let barSegmentGap: CGFloat = 2
        static let chunkyDepth: CGFloat = 4
        static let edgeDarkening: CGFloat = 0.45
        static let contrastBorderWidth: CGFloat = 1
        static let glowRadius: CGFloat = 6
        static let toastDuration: Duration = .seconds(2)
    }
}

// MARK: - Typography

extension Theme {
    /// The display font of a theme.
    struct Typography: Equatable {
        /// PostScript name of the bundled display font (all SIL OFL, see `Resources/Fonts`).
        let fontName: String
        /// Size multiplier, so wide faces (pixel, geometric) fit the same layout.
        let scale: CGFloat
        /// Letter-spacing multiplier for uppercase titles.
        let tracking: CGFloat
    }

    /// The display font, for titles, section headers and big numbers.
    /// - Parameters:
    ///   - size: The nominal point size, before the theme's scale; never below 11 pt.
    ///   - style: The text style it scales with.
    /// - Returns: The font.
    func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .headline) -> Font {
        .custom(typography.fontName, size: max(size * typography.scale, Self.minimumFontSize), relativeTo: style)
    }

    /// Letter spacing for an uppercase display title.
    /// - Parameter base: The spacing used by the default theme.
    /// - Returns: The spacing for this theme.
    func tracking(_ base: CGFloat) -> CGFloat {
        base * typography.tracking
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

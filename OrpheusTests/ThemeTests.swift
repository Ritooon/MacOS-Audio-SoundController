import AppKit
import SwiftUI
import Testing
@testable import Orpheus

@MainActor
@Suite("Theme")
struct ThemeTests {
    @Test func everyThemeIDHasExactlyOneTheme() {
        #expect(Theme.all.map(\.id) == ThemeID.allCases)
        for id in ThemeID.allCases {
            #expect(Theme.theme(for: id).id == id)
        }
    }

    @Test func themeNamesAreUnique() {
        #expect(Set(Theme.all.map(\.name)).count == Theme.all.count)
    }

    @Test func savedIdentifierIsResolved() {
        #expect(ThemeID.resolve("cosmos") == .cosmos)
        #expect(ThemeID.resolve("givre") == .givre)
    }

    @Test func unknownOrMissingIdentifierFallsBackToNeon() {
        #expect(ThemeID.resolve(nil) == .neon)
        #expect(ThemeID.resolve("") == .neon)
        #expect(ThemeID.resolve("vaporwave") == .neon)
    }

    @Test func onlyGivreIsLight() {
        #expect(Theme.all.filter(\.isLight).map(\.id) == [.givre])
    }

    @Test func onlyRetroHasSegmentedSquareBars() {
        let segmented = Theme.all.filter(\.shape.isBarSegmented).map(\.id)
        #expect(segmented == [.retro])
        #expect(Theme.retro.shape.card == 0)
        #expect(Theme.retro.shape.bar == 0)
    }

    @Test(arguments: ThemeID.allCases)
    func displayFontIsBundled(_ id: ThemeID) {
        let fontName = Theme.theme(for: id).typography.fontName
        #expect(NSFont(name: fontName, size: 12) != nil, "Missing font \(fontName)")
    }

    @Test(arguments: ThemeID.allCases)
    func colourTokensResolveFromTheAssetCatalog(_ id: ThemeID) {
        let folder = id == .neon ? "Theme" : "Theme" + id.rawValue.prefix(1).uppercased() + id.rawValue.dropFirst()
        let keys = [
            "background", "backgroundGlow", "surface", "surfaceMuted", "textPrimary", "textSecondary",
            "textDisabled", "accentPrimary", "accentBoost", "boostChipBackground", "boostChipText",
            "accentAction", "accentSuccess", "accentInfo", "infoSurface", "onAccent",
        ]
        for key in keys {
            #expect(NSColor(named: "\(folder)/\(key)", bundle: .main) != nil, "Missing colour \(folder)/\(key)")
        }
    }

    @Test(arguments: ThemeID.allCases)
    func primaryTextIsReadableOnCards(_ id: ThemeID) throws {
        let theme = Theme.theme(for: id)
        let ratio = try #require(contrast(theme.textPrimary, theme.surface))
        #expect(ratio >= 4.5)
        let secondary = try #require(contrast(theme.textSecondary, theme.surface))
        #expect(secondary >= 4.5)
        let chip = try #require(contrast(theme.boostChipText, theme.boostChipBackground))
        #expect(chip >= 4.5)
    }

    /// WCAG contrast ratio between two colours.
    private func contrast(_ first: Color, _ second: Color) -> Double? {
        guard let lum1 = luminance(first), let lum2 = luminance(second) else { return nil }
        return (max(lum1, lum2) + 0.05) / (min(lum1, lum2) + 0.05)
    }

    private func luminance(_ color: Color) -> Double? {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        func channel(_ value: CGFloat) -> Double {
            let component = Double(value)
            return component <= 0.039_28 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.212_6 * channel(rgb.redComponent) + 0.715_2 * channel(rgb.greenComponent) + 0.072_2 * channel(rgb.blueComponent)
    }
}

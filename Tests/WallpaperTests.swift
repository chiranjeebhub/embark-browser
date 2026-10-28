import Foundation
import Testing

/// The new tab page's generated wallpapers: their colors and repeatable layouts.
struct WallpaperTests {
    @Test func paletteFillsInThreeAccentsFromOneColor() {
        let theme = SpaceTheme(colors: [ThemeColor(hue: 0.6, depth: 0.5)])
        let palette = WallpaperPalette(theme: theme, isDark: true)
        #expect(palette.accents.count == 3)
        #expect(palette.accents[0].hue == 0.6)
        #expect(Set(palette.accents.map(\.hue)).count == 3)
    }

    @Test func darkBackgroundIsDeeperThanItsAccentsAndLightIsPaler() {
        let theme = ThemePreset.all[0].theme
        let dark = WallpaperPalette(theme: theme, isDark: true)
        let light = WallpaperPalette(theme: theme, isDark: false)
        #expect(dark.background.allSatisfy { bg in dark.accents.allSatisfy { $0.lightness > bg.lightness } })
        #expect(light.background.allSatisfy { bg in light.accents.allSatisfy { $0.lightness < bg.lightness } })
    }

    @Test func layoutsRepeatForTheSameSpaceAndDifferBetweenSpaces() {
        let a = UUID()
        let b = UUID()
        #expect(WaveLayout(seed: a) == WaveLayout(seed: a))
        #expect(WaveLayout(seed: a) != WaveLayout(seed: b))
        #expect(OrbLayout(seed: a) == OrbLayout(seed: a))
    }

    @Test func wavesStackDownwardFromTheBack() {
        let layout = WaveLayout(seed: UUID())
        #expect(layout.waves.count == 5)
        #expect(layout.waves.first!.baseline < layout.waves.last!.baseline)
        #expect(layout.waves.allSatisfy { (0.25...0.95).contains($0.y(at: 0.5)) })
    }

    @Test func spacesSavedBeforeWallpapersGetWaves() throws {
        let space = Space(name: "A", profileID: UUID())
        let data = try JSONEncoder().encode(space)
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["wallpaper"] = nil
        let decoded = try JSONDecoder().decode(Space.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.resolvedWallpaper == .waves)
    }
}

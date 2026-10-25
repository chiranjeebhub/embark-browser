import Foundation
import Testing

/// Space themes (colors, gradient stops, editing), icons stored as symbols or text, and state
/// saved before themes still loading.
struct ThemeTests {
    /// Repeatable randomness for shuffle.
    private struct SplitMix: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    @Test func colorsFollowThePad() {
        let red = ThemeColor(hue: 0, depth: 0.5).rgb()
        #expect(red.red > red.green && red.red > red.blue)
        let blue = ThemeColor(hue: 0.66, depth: 0.5).rgb()
        #expect(blue.blue > blue.red && blue.blue > blue.green)
        // Top of the pad is light, bottom is dark.
        let light = ThemeColor(hue: 0.3, depth: 0).rgb(), dark = ThemeColor(hue: 0.3, depth: 1).rgb()
        #expect(light.green > dark.green)
        for c in [red, blue, light, dark] {
            #expect((0...1).contains(c.red) && (0...1).contains(c.green) && (0...1).contains(c.blue))
        }
    }

    @Test func zeroIntensityIsGray() {
        let gray = ThemeColor(hue: 0.4, depth: 0.5).rgb(intensity: 0)
        #expect(abs(gray.red - gray.green) < 1e-9 && abs(gray.green - gray.blue) < 1e-9)
    }

    @Test func colorCountStaysBetweenOneAndThree() {
        #expect(SpaceTheme(colors: []).colors.count == 1)
        let four = (0..<4).map { ThemeColor(hue: Double($0) / 4, depth: 0.5) }
        var theme = SpaceTheme(colors: four)
        #expect(theme.colors.count == SpaceTheme.maxColors)
        theme.addColor()
        #expect(theme.colors.count == SpaceTheme.maxColors)
        theme.removeLastColor(); theme.removeLastColor(); theme.removeLastColor()
        #expect(theme.colors.count == 1)
        theme.addColor()
        #expect(theme.colors.count == 2)
        #expect((0..<1).contains(theme.colors[1].hue))
    }

    @Test func oneColorStillMakesAGradient() {
        #expect(SpaceTheme(colors: [ThemeColor(hue: 0.5, depth: 0.5)]).gradientColors.count == 2)
        #expect(ThemePreset.all[2].theme.gradientColors.count == 3)
    }

    @Test func shuffleKeepsTheCount() {
        var generator = SplitMix(state: 42)
        var theme = ThemePreset.all[2].theme
        let before = theme.colors
        theme.shuffle(using: &generator)
        #expect(theme.colors.count == before.count)
        #expect(theme.colors != before)
        for color in theme.colors {
            #expect((0..<1).contains(color.hue))
            #expect((0.35...0.6).contains(color.depth))
        }
    }

    @Test func themeRoundTrips() throws {
        var space = Space(name: "Side Project", theme: ThemePreset.all[0].theme, profileID: UUID())
        space.theme?.grain = 0.8
        space.theme?.appearance = .dark
        let decoded = try JSONDecoder().decode(Space.self, from: JSONEncoder().encode(space))
        #expect(decoded.theme == space.theme)
        #expect(decoded.resolvedTheme.appearance == .dark)
    }

    @Test func stateFromBeforeThemesLoads() throws {
        let id = UUID()
        let json = """
        {"id":"\(UUID().uuidString)","name":"Work","tint":"teal","icon":"briefcase.fill",
         "profileID":"\(id.uuidString)","favorites":[],"tabs":[]}
        """
        let space = try JSONDecoder().decode(Space.self, from: Data(json.utf8))
        #expect(space.theme == nil)
        #expect(space.resolvedTheme == SpaceTheme(tint: .teal))
        let profile = try JSONDecoder().decode(Profile.self, from: Data(#"{"id":"\#(id.uuidString)","name":"Work"}"#.utf8))
        #expect(profile.tint == nil)
    }

    @Test func iconKinds() {
        #expect(SpaceIcon.kind(of: nil) == .initial)
        #expect(SpaceIcon.kind(of: "briefcase.fill") == .symbol("briefcase.fill"))
        #expect(SpaceIcon.kind(of: SpaceIcon.text("🚀")) == .text("🚀"))
        #expect(SpaceIcon.text("  ") == nil)
        #expect(SpaceIcon.kind(of: SpaceIcon.text("ABC")) == .text("AB"))
        #expect(SpaceIcon.kind(of: "text:") == .initial)
    }

    @Test func iconSuggestionsFromTheName() {
        #expect(SpaceIcon.suggestions(for: "Work").first == "briefcase.fill")
        #expect(SpaceIcon.suggestions(for: "Study group").first == "graduationcap.fill")
        #expect(SpaceIcon.suggestions(for: "Side Project").first == "chevron.left.forwardslash.chevron.right")
        // Short keywords only match whole words.
        #expect(!SpaceIcon.suggestions(for: "Meetings").contains("house.fill"))
        #expect(SpaceIcon.suggestions(for: "Zzz").isEmpty)
        // Every suggestion is offered in the picker too.
        for name in ["Work", "Home", "Study", "Shopping", "Travel", "Music", "Gym", "Recipes", "Research"] {
            for symbol in SpaceIcon.suggestions(for: name) { #expect(SpaceIcon.choices.contains(symbol)) }
        }
    }
}

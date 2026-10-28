import Foundation

/// The art behind a space's new tab page, drawn from the space's own colors.
enum Wallpaper: String, Codable, CaseIterable, Identifiable {
    /// Layered glass ribbons, like the macOS wallpapers.
    case waves
    /// A soft mesh of the colors, like light through fog.
    case aurora
    /// A few large glossy spheres.
    case orbs
    /// Just the theme's gradient.
    case none

    static let `default` = Wallpaper.waves

    var id: String { rawValue }

    var title: String {
        switch self {
        case .waves: "Waves"
        case .aurora: "Aurora"
        case .orbs: "Orbs"
        case .none: "Colors Only"
        }
    }
}

extension Space {
    var resolvedWallpaper: Wallpaper { wallpaper ?? .default }
}

/// The colors a wallpaper is drawn with: a deep (or, in light mode, pale) background from
/// the theme's first color, and three accents from its colors, with near hues filling in
/// for a theme of one or two colors.
struct WallpaperPalette: Equatable {
    /// Top and bottom of the background.
    var background: [ThemeColor]
    var accents: [ThemeColor]

    init(theme: SpaceTheme, isDark: Bool) {
        let base = theme.colors[0]
        background = isDark
            ? [ThemeColor(hue: base.hue, depth: 0.9), ThemeColor(hue: (base.hue + 0.04).truncatingRemainder(dividingBy: 1), depth: 1)]
            : [ThemeColor(hue: base.hue, depth: 0.02), ThemeColor(hue: (base.hue + 0.04).truncatingRemainder(dividingBy: 1), depth: 0.1)]
        var hues = theme.colors.map(\.hue)
        let extra = [0.07, -0.06]
        var i = 0
        while hues.count < 3 {
            hues.append((base.hue + extra[i] + 1).truncatingRemainder(dividingBy: 1))
            i += 1
        }
        // Accents stay in a range that shows against the background: brighter than it in dark
        // mode, deeper in light mode.
        let depths = isDark ? [0.38, 0.5, 0.62] : [0.28, 0.38, 0.48]
        accents = zip(hues, depths).map { ThemeColor(hue: $0, depth: $1) }
    }
}

/// The shape of a waves wallpaper, worked out from the space so each space gets its own.
struct WaveLayout: Equatable {
    struct Wave: Equatable {
        /// Where the wave's middle sits, 0 at the top and 1 at the bottom.
        var baseline: Double
        /// Height of the swell, as a fraction of the height.
        var amplitude: Double
        /// Swells across the width.
        var frequency: Double
        var phase: Double
        /// How much the wave rises from left to right.
        var tilt: Double
        /// Which accent the wave starts from.
        var color: Int

        /// The wave's height at `x` (0...1 across), as a fraction of the height from the top.
        func y(at x: Double) -> Double {
            baseline + amplitude * sin(2 * .pi * (frequency * x + phase)) - tilt * (x - 0.5)
        }
    }

    var waves: [Wave]

    /// Back to front: each wave sits a little lower than the one behind it.
    init(seed: UUID, count: Int = 5) {
        var random = SeededRandom(seed: seed)
        waves = (0..<count).map { i in
            let step = Double(i) / Double(max(count - 1, 1))
            return Wave(baseline: 0.42 + 0.4 * step + Double.random(in: -0.03...0.03, using: &random),
                        amplitude: Double.random(in: 0.04...0.09, using: &random),
                        frequency: Double.random(in: 0.5...1.1, using: &random),
                        phase: Double.random(in: 0..<1, using: &random),
                        tilt: Double.random(in: -0.1...0.18, using: &random),
                        color: i % 3)
        }
    }
}

/// Places for an orbs wallpaper's spheres, worked out from the space.
struct OrbLayout: Equatable {
    struct Orb: Equatable {
        /// Center, 0...1 across and down.
        var x: Double
        var y: Double
        /// Diameter as a fraction of the shorter side.
        var size: Double
        var color: Int
    }

    var orbs: [Orb]

    init(seed: UUID) {
        var random = SeededRandom(seed: seed)
        func jitter(_ value: Double) -> Double { value + Double.random(in: -0.05...0.05, using: &random) }
        // A big one off the top corner, a middle one low on the other side, a small one between.
        let flip = Bool.random(using: &random)
        let orbs = [
            Orb(x: jitter(0.86), y: jitter(0.12), size: jitter(0.75), color: 0),
            Orb(x: jitter(0.1), y: jitter(0.88), size: jitter(0.55), color: 1),
            Orb(x: jitter(0.72), y: jitter(0.78), size: jitter(0.2), color: 2),
        ]
        self.orbs = flip ? orbs.map { Orb(x: 1 - $0.x, y: $0.y, size: $0.size, color: $0.color) } : orbs
    }
}

/// Repeatable randomness from a space's id, so its wallpaper looks the same every time.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UUID) {
        let b = seed.uuid
        let bytes = [b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7, b.8, b.9, b.10, b.11, b.12, b.13, b.14, b.15]
        state = bytes.reduce(UInt64(0x9E37_79B9_7F4A_7C15)) { ($0 ^ UInt64($1)) &* 0x100_0000_01B3 }
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

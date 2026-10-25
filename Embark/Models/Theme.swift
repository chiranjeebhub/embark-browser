import SwiftUI

/// A space's look, as in Arc: one to three colors blended into a gradient over the window,
/// with optional film grain, and whether the space shows light, dark or follows the system.
struct SpaceTheme: Codable, Hashable {
    var colors: [ThemeColor]
    /// How strongly the colors show, 0...1. Low values fade toward gray.
    var intensity: Double = 0.7
    /// Film grain over the window, 0...1.
    var grain: Double = 0.3
    var appearance: Appearance = .system

    enum Appearance: String, Codable, CaseIterable {
        case light, dark, system
    }

    static let maxColors = 3

    init(colors: [ThemeColor], intensity: Double = 0.7, grain: Double = 0.3, appearance: Appearance = .system) {
        self.colors = colors.isEmpty ? [ThemeColor(hue: 0.6, depth: 0.5)] : Array(colors.prefix(Self.maxColors))
        self.intensity = intensity
        self.grain = grain
        self.appearance = appearance
    }

    /// The theme a space saved before themes had, from its tint.
    init(tint: SpaceTint) {
        switch tint {
        case .graphite: self.init(colors: [tint.themeColor], intensity: 0.12)
        default: self.init(colors: [tint.themeColor])
        }
    }

    /// The gradient's stops, first color at the top leading corner. One color gets a deeper
    /// shade of itself so it still reads as a gradient.
    var gradientColors: [Color] {
        let stops = colors.count == 1 ? [colors[0], colors[0].deeper] : colors
        return stops.map { $0.color(intensity: intensity) }
    }

    /// The space's icon and highlight color: its first color, kept away from the extremes so it
    /// reads on both light and dark backgrounds.
    var accent: Color {
        var color = colors[0]
        color.depth = min(max(color.depth, 0.3), 0.6)
        return color.color(intensity: max(intensity, 0.2))
    }

    /// Adds a color a step along the hue circle from the last one.
    mutating func addColor() {
        guard colors.count < Self.maxColors, let last = colors.last else { return }
        colors.append(ThemeColor(hue: (last.hue + 0.18).truncatingRemainder(dividingBy: 1), depth: last.depth))
    }

    mutating func removeLastColor() {
        guard colors.count > 1 else { return }
        colors.removeLast()
    }

    /// New colors, as many as now, close enough in hue to blend well.
    mutating func shuffle<G: RandomNumberGenerator>(using generator: inout G) {
        let base = Double.random(in: 0..<1, using: &generator)
        var hue = base
        colors = colors.indices.map { _ in
            defer { hue = (hue + Double.random(in: 0.08...0.28, using: &generator)).truncatingRemainder(dividingBy: 1) }
            return ThemeColor(hue: hue, depth: Double.random(in: 0.35...0.6, using: &generator))
        }
    }

    mutating func shuffle() {
        var generator = SystemRandomNumberGenerator()
        shuffle(using: &generator)
    }
}

/// A point on the theme picker's color pad: hue from left to right, and from light at the top
/// to dark at the bottom.
struct ThemeColor: Codable, Hashable {
    /// 0...1 around the color circle.
    var hue: Double
    /// 0 is the lightest, 1 the darkest.
    var depth: Double

    static let saturation = 0.85

    var lightness: Double { 0.92 - min(max(depth, 0), 1) * 0.8 }

    var deeper: ThemeColor { ThemeColor(hue: hue, depth: min(depth + 0.18, 1)) }

    /// sRGB components, each 0...1. `intensity` scales the saturation; 0 is gray.
    func rgb(intensity: Double = 1) -> (red: Double, green: Double, blue: Double) {
        let l = lightness
        let s = Self.saturation * min(max(intensity, 0), 1)
        let chroma = (1 - abs(2 * l - 1)) * s
        var h = hue.truncatingRemainder(dividingBy: 1)
        if h < 0 { h += 1 }
        let sector = h * 6
        let x = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double) = switch Int(sector) {
        case 0: (chroma, x, 0)
        case 1: (x, chroma, 0)
        case 2: (0, chroma, x)
        case 3: (0, x, chroma)
        case 4: (x, 0, chroma)
        default: (chroma, 0, x)
        }
        let m = l - chroma / 2
        return (r + m, g + m, b + m)
    }

    func color(intensity: Double = 1) -> Color {
        let c = rgb(intensity: intensity)
        return Color(.sRGB, red: c.red, green: c.green, blue: c.blue)
    }
}

/// Ready-made themes offered in the picker.
struct ThemePreset: Identifiable {
    let name: String
    let theme: SpaceTheme
    var id: String { name }

    static let all: [ThemePreset] = [
        ThemePreset(name: "Dusk", theme: SpaceTheme(colors: [.init(hue: 0.86, depth: 0.45), .init(hue: 0.64, depth: 0.5)])),
        ThemePreset(name: "Ocean", theme: SpaceTheme(colors: [.init(hue: 0.55, depth: 0.45), .init(hue: 0.66, depth: 0.55)])),
        ThemePreset(name: "Aurora", theme: SpaceTheme(colors: [.init(hue: 0.4, depth: 0.45), .init(hue: 0.58, depth: 0.5), .init(hue: 0.8, depth: 0.5)])),
        ThemePreset(name: "Sunset", theme: SpaceTheme(colors: [.init(hue: 0.1, depth: 0.45), .init(hue: 0.95, depth: 0.5)])),
        ThemePreset(name: "Forest", theme: SpaceTheme(colors: [.init(hue: 0.3, depth: 0.6), .init(hue: 0.42, depth: 0.66)])),
        ThemePreset(name: "Peach", theme: SpaceTheme(colors: [.init(hue: 0.08, depth: 0.3), .init(hue: 0.97, depth: 0.35)])),
        ThemePreset(name: "Lilac", theme: SpaceTheme(colors: [.init(hue: 0.78, depth: 0.3), .init(hue: 0.66, depth: 0.38)])),
        ThemePreset(name: "Graphite", theme: SpaceTheme(colors: [.init(hue: 0.6, depth: 0.6)], intensity: 0.1)),
    ]
}

extension SpaceTint {
    /// Where the tint sits on the theme picker's pad.
    var themeColor: ThemeColor {
        switch self {
        case .purple: ThemeColor(hue: 0.74, depth: 0.45)
        case .indigo: ThemeColor(hue: 0.67, depth: 0.45)
        case .blue: ThemeColor(hue: 0.59, depth: 0.5)
        case .teal: ThemeColor(hue: 0.48, depth: 0.55)
        case .green: ThemeColor(hue: 0.38, depth: 0.55)
        case .yellow: ThemeColor(hue: 0.12, depth: 0.45)
        case .orange: ThemeColor(hue: 0.06, depth: 0.45)
        case .red: ThemeColor(hue: 0.99, depth: 0.45)
        case .pink: ThemeColor(hue: 0.92, depth: 0.45)
        case .graphite: ThemeColor(hue: 0.6, depth: 0.6)
        }
    }
}

extension Space {
    /// The space's theme, or one made from the tint it was saved with before themes.
    var resolvedTheme: SpaceTheme { theme ?? SpaceTheme(tint: tint ?? .blue) }

    /// The color of the space's icon and highlights.
    var accent: Color { resolvedTheme.accent }

    /// Every page the space can have open: its tabs and its favorites' pages.
    var pageIDs: [BrowserTab.ID] { tabs.map(\.id) + favorites.compactMap(\.tab?.id) }
}

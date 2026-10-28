import SwiftUI

/// A space's new tab wallpaper, drawn from its theme: nothing is downloaded, and it follows
/// the theme's colors, grain and light or dark appearance. Each space's layout comes from its
/// id, so spaces with the same colors still look different.
struct WallpaperView: View {
    let wallpaper: Wallpaper
    let theme: SpaceTheme
    let seed: UUID
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        let art = WallpaperArt(palette: WallpaperPalette(theme: theme, isDark: isDark),
                               intensity: min(1, max(theme.intensity, 0.08) * 1.15), isDark: isDark)
        ZStack {
            LinearGradient(colors: art.palette.background.map(art.color), startPoint: .top, endPoint: .bottom)
            switch wallpaper {
            case .waves: WavesArt(layout: WaveLayout(seed: seed), art: art)
            case .aurora: AuroraArt(seed: seed, art: art)
            case .orbs: OrbsArt(layout: OrbLayout(seed: seed), art: art)
            case .none: EmptyView()
            }
            if theme.grain > 0 {
                Grain.image.resizable(resizingMode: .tile).opacity(theme.grain * 0.35)
            }
        }
        // Drawn once into a single layer on the GPU; nothing here animates.
        .drawingGroup()
        .allowsHitTesting(false)
    }
}

/// What the pieces share: the palette, how saturated to draw it and whether it's dark.
private struct WallpaperArt {
    let palette: WallpaperPalette
    let intensity: Double
    let isDark: Bool

    func color(_ color: ThemeColor) -> Color { color.color(intensity: intensity) }

    func accent(_ index: Int) -> ThemeColor { palette.accents[index % palette.accents.count] }

    func shade(_ color: ThemeColor, by amount: Double) -> Color {
        self.color(ThemeColor(hue: color.hue, depth: min(max(color.depth + amount, 0), 1)))
    }
}

/// Layered ribbons, each lit along its top edge and casting a soft shadow on the one behind.
private struct WavesArt: View {
    let layout: WaveLayout
    let art: WallpaperArt

    var body: some View {
        Canvas { context, size in
            for wave in layout.waves {
                let top = art.accent(wave.color)
                let next = art.accent(wave.color + 1)
                let curve = Self.curve(wave, in: size)
                var fill = curve
                fill.addLine(to: CGPoint(x: size.width, y: size.height))
                fill.addLine(to: CGPoint(x: 0, y: size.height))
                fill.closeSubpath()
                let crest = size.height * (wave.baseline - wave.amplitude - abs(wave.tilt) / 2)

                context.drawLayer { layer in
                    layer.addFilter(.shadow(color: .black.opacity(art.isDark ? 0.5 : 0.16), radius: 36, x: 0, y: -10))
                    layer.fill(fill, with: .linearGradient(
                        Gradient(colors: [art.color(top), art.shade(next, by: art.isDark ? 0.32 : 0.12)]),
                        startPoint: CGPoint(x: 0, y: crest), endPoint: CGPoint(x: size.width * 0.35, y: size.height)))
                }
                // A soft sheen just under the edge, then a thin bright rim: reads as glass.
                context.drawLayer { layer in
                    layer.clip(to: fill)
                    layer.addFilter(.blur(radius: 14))
                    layer.stroke(curve, with: .color(.white.opacity(art.isDark ? 0.14 : 0.3)), lineWidth: 26)
                }
                context.stroke(curve, with: .linearGradient(
                    Gradient(colors: [.white.opacity(0), .white.opacity(art.isDark ? 0.45 : 0.7), .white.opacity(0.05)]),
                    startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)), lineWidth: 1.2)
            }
        }
    }

    private static func curve(_ wave: WaveLayout.Wave, in size: CGSize) -> Path {
        var path = Path()
        let steps = 96
        for step in 0...steps {
            let x = Double(step) / Double(steps)
            let point = CGPoint(x: x * size.width, y: wave.y(at: x) * size.height)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// The colors drifting into each other through the middle, darker toward the edges.
private struct AuroraArt: View {
    let seed: UUID
    let art: WallpaperArt

    var body: some View {
        var random = SeededRandom(seed: seed)
        func jitter(_ value: Double, _ amount: Double = 0.12) -> Float {
            Float(value + Double.random(in: -amount...amount, using: &random))
        }
        let bg = art.palette.background.map(art.color)
        let a = (0..<3).map { art.color(art.accent($0)).opacity(art.isDark ? 0.9 : 0.75) }
        let points: [SIMD2<Float>] = [
            [0, 0], [jitter(0.5), 0], [1, 0],
            [0, jitter(0.45)], [jitter(0.55), jitter(0.55)], [1, jitter(0.5)],
            [0, 1], [jitter(0.45), 1], [1, 1],
        ]
        return ZStack {
            MeshGradient(width: 3, height: 3, points: points, colors: [
                bg[0], a[1], bg[0],
                a[0], a[2], a[1],
                bg[1], a[0], bg[1],
            ], smoothsColors: true)
            // A brighter ribbon of light across the upper middle.
            EllipticalGradient(colors: [.white.opacity(art.isDark ? 0.08 : 0.25), .clear],
                               center: UnitPoint(x: Double(jitter(0.5, 0.2)), y: 0.35),
                               startRadiusFraction: 0, endRadiusFraction: 0.45)
                .scaleEffect(x: 1.8, y: 0.5)
        }
    }
}

/// A few large glossy spheres in the space's colors, partly off the edges.
private struct OrbsArt: View {
    let layout: OrbLayout
    let art: WallpaperArt

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                ForEach(layout.orbs.indices, id: \.self) { i in
                    let orb = layout.orbs[i]
                    let d = orb.size * side
                    let color = art.accent(orb.color)
                    ZStack {
                        // Glow around it.
                        Circle()
                            .fill(RadialGradient(colors: [art.color(color).opacity(art.isDark ? 0.45 : 0.35), .clear],
                                                 center: .center, startRadius: d * 0.4, endRadius: d * 0.85))
                            .frame(width: d * 1.7, height: d * 1.7)
                        Circle()
                            .fill(RadialGradient(colors: [art.shade(color, by: -0.3), art.color(color), art.shade(color, by: 0.35)],
                                                 center: UnitPoint(x: 0.32, y: 0.28), startRadius: 0, endRadius: d * 0.8))
                            .overlay {
                                Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0)],
                                                                     startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                            }
                            .overlay {
                                // The window's reflection, high on the sphere.
                                Ellipse()
                                    .fill(LinearGradient(colors: [.white.opacity(art.isDark ? 0.35 : 0.5), .white.opacity(0)],
                                                         startPoint: .top, endPoint: .bottom))
                                    .frame(width: d * 0.5, height: d * 0.28)
                                    .offset(x: -d * 0.12, y: -d * 0.28)
                            }
                            .shadow(color: .black.opacity(art.isDark ? 0.45 : 0.18), radius: d * 0.1, y: d * 0.06)
                            .frame(width: d, height: d)
                    }
                    .position(x: orb.x * geo.size.width, y: orb.y * geo.size.height)
                }
            }
        }
    }
}

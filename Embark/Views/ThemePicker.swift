import SwiftUI

/// The window behind the sidebar and page, painted with a space's theme.
struct ThemeBackground: View {
    let theme: SpaceTheme

    var body: some View {
        ZStack {
            Rectangle().fill(.background)
            LinearGradient(colors: theme.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity(0.2 + 0.5 * theme.intensity)
            // A soft glow, drawn as a gradient: the same look as a heavily blurred circle, but
            // without a 100pt blur pass on every resize and space swipe.
            Circle()
                .fill(RadialGradient(stops: Self.glow.map { Gradient.Stop(color: theme.accent.opacity(0.3 * $0.opacity), location: $0.location) },
                                     center: .center, startRadius: 0, endRadius: 330))
                .frame(width: 660, height: 660)
                .offset(x: -420, y: -300)
            if theme.grain > 0 {
                Grain.image.resizable(resizingMode: .tile).opacity(theme.grain * 0.3)
            }
        }
    }

    /// The falloff of a 460pt circle blurred by 100pt, from its center out to where it fades.
    private static let glow: [(opacity: Double, location: Double)] = [
        (1, 0), (0.92, 0.3), (0.7, 0.5), (0.4, 0.66), (0.15, 0.82), (0.04, 0.92), (0, 1),
    ]
}

/// A tile of random light and dark specks, tiled over the window as film grain.
@MainActor
enum Grain {
    static let image: Image = {
        let size = 128
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for i in 0..<(size * size) {
            let alpha = UInt8.random(in: 0...70)
            // Premultiplied: a light or a dark speck at that opacity.
            let value = Bool.random() ? alpha : 0
            pixels[i * 4] = value
            pixels[i * 4 + 1] = value
            pixels[i * 4 + 2] = value
            pixels[i * 4 + 3] = alpha
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return Image(systemName: "circle") }
        return Image(decorative: image, scale: 2)
    }()
}

/// A theme's colors as a small gradient capsule.
struct ThemeSwatch: View {
    let theme: SpaceTheme

    var body: some View {
        Capsule()
            .fill(LinearGradient(colors: theme.colors.count == 1 ? theme.gradientColors : theme.colors.map { $0.color(intensity: theme.intensity) },
                                 startPoint: .leading, endPoint: .trailing))
            .overlay(Capsule().strokeBorder(.white.opacity(0.45), lineWidth: 1))
    }
}

/// Arc's theme picker: drag up to three colors around a pad of every hue, light to dark,
/// then set grain, intensity and light or dark. Edits apply as they happen.
struct ThemePicker: View {
    @Binding var theme: SpaceTheme
    /// The color a drag moves, picked when it starts.
    @State private var dragging: Int?
    @State private var active = 0

    static let padHeight: CGFloat = 170

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Theme").font(.system(size: 13, weight: .semibold))
                Spacer()
                Picker("Appearance", selection: $theme.appearance) {
                    Label("Light", systemImage: "sun.max").labelStyle(.iconOnly).tag(SpaceTheme.Appearance.light)
                    Label("Dark", systemImage: "moon").labelStyle(.iconOnly).tag(SpaceTheme.Appearance.dark)
                    Label("Match System", systemImage: "circle.lefthalf.filled").labelStyle(.iconOnly).tag(SpaceTheme.Appearance.system)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Light, dark, or match the system")
            }

            pad.frame(height: Self.padHeight)

            HStack(spacing: 8) {
                roundButton("minus", help: "Remove a color") { theme.removeLastColor(); active = min(active, theme.colors.count - 1) }
                    .disabled(theme.colors.count <= 1)
                Text(theme.colors.count == 1 ? "1 color" : "\(theme.colors.count) colors")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(minWidth: 52)
                roundButton("plus", help: "Add a color") { theme.addColor(); active = theme.colors.count - 1 }
                    .disabled(theme.colors.count >= SpaceTheme.maxColors)
                Spacer()
                Button { withAnimation(.snappy(duration: 0.25)) { theme.shuffle() } } label: {
                    Label("Shuffle", systemImage: "shuffle").font(.system(size: 12))
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }

            HStack(spacing: 0) {
                ForEach(ThemePreset.all) { preset in
                    Button { withAnimation(.snappy(duration: 0.25)) { apply(preset) } } label: {
                        Circle()
                            .fill(LinearGradient(colors: preset.theme.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1))
                            .frame(width: 24, height: 24)
                            .overlay {
                                if preset.theme.colors == theme.colors {
                                    Circle().strokeBorder(Color.primary.opacity(0.8), lineWidth: 2).padding(-3)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(preset.name)
                    .frame(maxWidth: .infinity)
                }
            }

            VStack(spacing: 6) {
                slider("Grain", value: $theme.grain)
                slider("Intensity", value: $theme.intensity)
            }
        }
        .frame(width: 268)
    }

    private var pad: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                ZStack {
                    LinearGradient(colors: stride(from: 0.0, through: 1.0, by: 1.0 / 12).map { ThemeColor(hue: $0, depth: 0.5).color() },
                                   startPoint: .leading, endPoint: .trailing)
                    LinearGradient(stops: [
                        .init(color: .white.opacity(0.92), location: 0),
                        .init(color: .white.opacity(0), location: 0.42),
                        .init(color: .black.opacity(0), location: 0.58),
                        .init(color: .black.opacity(0.9), location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                }
                .clipShape(.rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.2)))

                if theme.colors.count > 1 {
                    Path { path in path.addLines(theme.colors.map { point(for: $0, in: size) }) }
                        .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                }
                ForEach(theme.colors.indices, id: \.self) { i in
                    let diameter: CGFloat = i == active ? 26 : 20
                    Circle()
                        .fill(theme.colors[i].color())
                        .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                        .frame(width: diameter, height: diameter)
                        .position(point(for: theme.colors[i], in: size))
                        .animation(.snappy(duration: 0.15), value: active)
                }
            }
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragging == nil { dragging = nearest(to: value.startLocation, in: size) ?? active }
                        guard let i = dragging, theme.colors.indices.contains(i) else { return }
                        active = i
                        theme.colors[i] = ThemeColor(hue: min(max(value.location.x / size.width, 0), 1),
                                                     depth: min(max(value.location.y / size.height, 0), 1))
                    }
                    .onEnded { _ in dragging = nil }
            )
        }
    }

    private func point(for color: ThemeColor, in size: CGSize) -> CGPoint {
        CGPoint(x: color.hue * size.width, y: color.depth * size.height)
    }

    /// The color under a click, if one is close enough to grab.
    private func nearest(to location: CGPoint, in size: CGSize) -> Int? {
        let distances = theme.colors.indices.map { i -> (Int, CGFloat) in
            let p = point(for: theme.colors[i], in: size)
            return (i, hypot(p.x - location.x, p.y - location.y))
        }
        guard let best = distances.min(by: { $0.1 < $1.1 }), best.1 < 24 else { return nil }
        return best.0
    }

    private func apply(_ preset: ThemePreset) {
        theme.colors = preset.theme.colors
        theme.intensity = preset.theme.intensity
        active = 0
    }

    private func roundButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).frame(width: 14, height: 14)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.small)
        .help(help)
    }

    private func slider(_ title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
            Slider(value: value, in: 0...1).controlSize(.small)
        }
    }
}

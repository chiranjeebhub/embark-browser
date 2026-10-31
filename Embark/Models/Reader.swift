import Foundation

extension PreferenceKey {
    static let readerTheme = "readerTheme"
    static let readerFont = "readerFont"
    static let readerFontSize = "readerFontSize"
    static let readerWidth = "readerWidth"
}

/// A page's article as Mozilla's Readability finds it (see PageScripts.readerArticle).
struct ReaderArticle: Decodable, Equatable {
    var title: String?
    var byline: String?
    var siteName: String?
    /// The article's HTML, cleaned of scripts, ads and navigation, with absolute links.
    var content: String
    var textContent: String?
    var lang: String?
    var dir: String?
    var publishedTime: String?

    /// About how long the article takes to read, at 230 words a minute. Languages written
    /// without spaces count characters instead, at 500 a minute.
    var minutesToRead: Int {
        let text = textContent ?? ""
        let words = text.split(whereSeparator: \.isWhitespace).count
        let characters = text.count
        let perMinute = words * 20 < characters ? Double(characters) / 500 : Double(words) / 230
        return max(1, Int(perMinute.rounded()))
    }

    /// Readability found an article worth showing.
    var isUsable: Bool { (textContent?.count ?? 0) >= 140 }
}

/// How reader mode looks, picked from its Aa menu and kept for every article.
struct ReaderStyle: Equatable {
    var theme: Theme = .automatic
    var font: Font = .newYork
    var fontSize: Int = Self.defaultFontSize
    var width: Width = .standard

    static let fontSizes = [14, 15, 16, 17, 18, 19, 21, 23, 26, 29, 32]
    static let defaultFontSize = 19

    enum Theme: String, CaseIterable, Identifiable {
        case automatic, light, sepia, gray, dark
        var id: String { rawValue }

        var title: String {
            switch self {
            case .automatic: "Automatic"
            case .light: "White"
            case .sepia: "Sepia"
            case .gray: "Gray"
            case .dark: "Night"
            }
        }

        /// Page background and text colors, as hex.
        var colors: (background: String, text: String)? {
            switch self {
            case .automatic: nil
            case .light: ("#ffffff", "#1d1d1f")
            case .sepia: ("#f8f1e3", "#4f3a24")
            case .gray: ("#4a4a4f", "#ececee")
            case .dark: ("#1b1b1d", "#dcdcde")
            }
        }
    }

    enum Font: String, CaseIterable, Identifiable {
        case newYork, sanFrancisco, charter, iowan
        var id: String { rawValue }

        var title: String {
            switch self {
            case .newYork: "New York"
            case .sanFrancisco: "San Francisco"
            case .charter: "Charter"
            case .iowan: "Iowan"
            }
        }

        var css: String {
            switch self {
            case .newYork: "ui-serif, 'New York', Georgia, serif"
            case .sanFrancisco: "-apple-system, 'SF Pro Text', system-ui, sans-serif"
            case .charter: "Charter, 'Bitstream Charter', Georgia, serif"
            case .iowan: "'Iowan Old Style', Palatino, Georgia, serif"
            }
        }
    }

    enum Width: String, CaseIterable, Identifiable {
        case narrow, standard, wide
        var id: String { rawValue }

        var title: String {
            switch self {
            case .narrow: "Narrow"
            case .standard: "Standard"
            case .wide: "Wide"
            }
        }

        var points: Int {
            switch self {
            case .narrow: 560
            case .standard: 680
            case .wide: 820
            }
        }
    }

    /// One step bigger or smaller, within `fontSizes`.
    func fontSize(steppedBy step: Int) -> Int {
        let sizes = Self.fontSizes
        let index = sizes.firstIndex { $0 >= fontSize } ?? sizes.count - 1
        return sizes[min(max(index + step, 0), sizes.count - 1)]
    }

    /// Sets the style on a page built by `ReaderPage.html`, without reloading it.
    var script: String {
        """
        (() => {
          const root = document.documentElement;
          root.dataset.theme = '\(theme.rawValue)';
          root.style.setProperty('--font', "\(font.css)");
          root.style.setProperty('--size', '\(fontSize)px');
          root.style.setProperty('--width', '\(width.points)px');
        })()
        """
    }
}

/// The reader view's page: the article, set in the reader's style.
enum ReaderPage {
    static func html(_ article: ReaderArticle, style: ReaderStyle, sourceHost: String?) -> String {
        let site = article.siteName?.trimmed ?? sourceHost ?? ""
        var meta: [String] = []
        if let byline = article.byline?.trimmed, !byline.isEmpty { meta.append(escape(byline)) }
        meta.append("\(article.minutesToRead) min read")
        let lang = article.lang.map { " lang=\"\(escape($0))\"" } ?? ""
        let dir = article.dir.map { " dir=\"\(escape($0))\"" } ?? ""
        return """
        <!doctype html>
        <html\(lang)\(dir) data-theme="\(style.theme.rawValue)" style="--font: \(style.font.css.replacingOccurrences(of: "\"", with: "'")); --size: \(style.fontSize)px; --width: \(style.width.points)px">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(article.title ?? ""))</title>
        <style>\(css)</style>
        </head>
        <body>
        <main>
        <header>
        \(site.isEmpty ? "" : "<p class=\"site\">\(escape(site))</p>")
        <h1>\(escape(article.title ?? ""))</h1>
        <p class="meta">\(meta.joined(separator: " <span>·</span> "))</p>
        </header>
        <article>\(article.content)</article>
        </main>
        </body>
        </html>
        """
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static var css: String {
        var themes = ""
        for theme in ReaderStyle.Theme.allCases {
            guard let colors = theme.colors else { continue }
            themes += ":root[data-theme=\(theme.rawValue)] { --bg: \(colors.background); --fg: \(colors.text); }\n"
        }
        return """
        :root { color-scheme: light dark; --bg: #ffffff; --fg: #1d1d1f; --accent: #0a64d6; }
        @media (prefers-color-scheme: dark) { :root[data-theme=automatic] { --bg: #1b1b1d; --fg: #dcdcde; } }
        \(themes)
        :root[data-theme=sepia] { --accent: #a0561c; }
        :root[data-theme=gray], :root[data-theme=dark] { --accent: #6cb0ff; }
        @media (prefers-color-scheme: dark) { :root[data-theme=automatic] { --accent: #6cb0ff; } }
        html { background: var(--bg); transition: background .25s ease, color .25s ease; }
        body {
          margin: 0; padding: 88px 32px 120px; color: var(--fg); background: var(--bg);
          font-family: var(--font); font-size: var(--size); line-height: 1.62;
          -webkit-font-smoothing: antialiased; text-rendering: optimizeLegibility;
          font-kerning: normal; hanging-punctuation: first;
        }
        main { max-width: var(--width); margin: 0 auto; }
        header { margin-bottom: 2.2em; }
        .site {
          margin: 0 0 .9em; font: 600 12px/1.2 -apple-system, system-ui, sans-serif;
          letter-spacing: .08em; text-transform: uppercase; color: var(--accent);
        }
        h1 { font-size: 2.05em; line-height: 1.14; letter-spacing: -.012em; margin: 0 0 .45em; font-weight: 700; text-wrap: balance; }
        .meta { margin: 0; font: 500 14px/1.4 -apple-system, system-ui, sans-serif; color: color-mix(in srgb, var(--fg) 58%, transparent); }
        .meta span { margin: 0 .35em; }
        header::after {
          content: ""; display: block; height: 1px; margin-top: 1.8em;
          background: color-mix(in srgb, var(--fg) 14%, transparent);
        }
        article { overflow-wrap: break-word; }
        article p, article ul, article ol, article blockquote, article figure, article pre, article table { margin: 0 0 1.1em; }
        article h2, article h3, article h4 { line-height: 1.25; margin: 1.7em 0 .55em; text-wrap: balance; }
        article h2 { font-size: 1.42em; } article h3 { font-size: 1.2em; } article h4 { font-size: 1.05em; }
        a { color: var(--accent); text-decoration: none; }
        a:hover { text-decoration: underline; text-underline-offset: .15em; }
        img, video, picture, svg { max-width: 100%; height: auto; }
        img { display: block; margin: 1.4em auto; border-radius: 10px; }
        figure { margin-left: 0; margin-right: 0; }
        figure img { margin-bottom: .6em; }
        figcaption, .caption, small {
          font: 13px/1.45 -apple-system, system-ui, sans-serif;
          color: color-mix(in srgb, var(--fg) 60%, transparent);
        }
        blockquote {
          margin-left: 0; padding: .1em 0 .1em 1.1em; font-style: italic;
          border-left: 3px solid color-mix(in srgb, var(--accent) 70%, transparent);
          color: color-mix(in srgb, var(--fg) 85%, transparent);
        }
        pre, code, kbd { font-family: ui-monospace, 'SF Mono', Menlo, monospace; font-size: .86em; }
        code { padding: .12em .35em; border-radius: 5px; background: color-mix(in srgb, var(--fg) 8%, transparent); }
        pre { padding: 1em 1.1em; border-radius: 10px; overflow-x: auto; line-height: 1.5; background: color-mix(in srgb, var(--fg) 6%, transparent); }
        pre code { padding: 0; background: none; }
        hr { border: 0; height: 1px; margin: 2em 0; background: color-mix(in srgb, var(--fg) 14%, transparent); }
        table { border-collapse: collapse; width: 100%; font-size: .9em; display: block; overflow-x: auto; }
        th, td { padding: .5em .7em; border-bottom: 1px solid color-mix(in srgb, var(--fg) 12%, transparent); text-align: left; }
        li { margin-bottom: .35em; }
        ::selection { background: color-mix(in srgb, var(--accent) 30%, transparent); }
        """
    }
}

private extension String {
    var trimmed: String? {
        let text = trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

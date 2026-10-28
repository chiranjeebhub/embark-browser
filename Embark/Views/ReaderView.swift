import AVFoundation
import SwiftUI
import WebKit

/// Reader mode: the page's article alone, set in a clean, adjustable style over the page.
/// The page stays loaded underneath, so leaving reader mode is instant.
struct ReaderView: View {
    let tabID: BrowserTab.ID
    let article: ReaderArticle
    /// The page the article came from, for its links and images.
    let url: URL
    @Environment(PagePool.self) private var pool
    @Environment(BrowserStore.self) private var store

    @AppStorage(PreferenceKey.readerTheme) private var theme = ReaderStyle.Theme.automatic
    @AppStorage(PreferenceKey.readerFont) private var font = ReaderStyle.Font.newYork
    @AppStorage(PreferenceKey.readerFontSize) private var fontSize = ReaderStyle.defaultFontSize
    @AppStorage(PreferenceKey.readerWidth) private var width = ReaderStyle.Width.standard
    @State private var speaker = ReaderSpeaker()
    @State private var showsStyle = false

    private var style: ReaderStyle { ReaderStyle(theme: theme, font: font, fontSize: fontSize, width: width) }

    var body: some View {
        ReaderWebView(article: article, url: url, style: style, open: { open($0, inNewTab: $1) }, close: { close() })
            .overlay(alignment: .top) { toolbar.padding(.top, 14) }
            .onDisappear { speaker.stop() }
    }

    private var toolbar: some View {
        HStack(spacing: 2) {
            Button { showsStyle.toggle() } label: {
                Text("Aa").font(.system(size: 14, weight: .semibold)).frame(width: 34)
            }
            .help("Text and Theme")
            .popover(isPresented: $showsStyle, arrowEdge: .bottom) {
                ReaderStylePanel(theme: $theme, font: $font, fontSize: $fontSize, width: $width)
            }
            Button { listen() } label: {
                Image(systemName: speaker.state == .speaking ? "pause.fill" : "headphones")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 34)
            }
            .help(speaker.state == .speaking ? "Pause" : speaker.state == .paused ? "Resume Listening" : "Listen to Article")
            if speaker.state != .idle {
                Button { speaker.stop() } label: { Image(systemName: "stop.fill").frame(width: 30) }
                    .help("Stop Listening")
                    .transition(.scale.combined(with: .opacity))
            }
            Button { PageSharing.share(url) } label: {
                Image(systemName: "square.and.arrow.up").offset(y: -1).frame(width: 34)
            }
            .help("Share")
            Divider().frame(height: 16).padding(.horizontal, 4)
            Button { close() } label: {
                Label("Exit Reader", systemImage: "xmark").labelStyle(.iconOnly).frame(width: 34)
            }
            .help("Exit Reader (⇧⌘R)")
        }
        .buttonStyle(ReaderToolbarButtonStyle())
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 5)
        .frame(height: 36)
        .glassEffect(.regular, in: .capsule)
        .animation(.snappy(duration: 0.2), value: speaker.state)
    }

    private func listen() {
        switch speaker.state {
        case .idle:
            let text = [article.title, article.textContent].compactMap { $0 }.joined(separator: ".\n\n")
            speaker.speak(text, language: article.lang)
        case .speaking: speaker.pause()
        case .paused: speaker.resume()
        }
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.18)) { pool.tools.closeReader(tabID) }
    }

    /// A link in the article opens in the tab, leaving reader mode; with ⌘, in a new tab.
    private func open(_ link: URL, inNewTab: Bool) {
        if inNewTab {
            store.openTab(link)
        } else {
            close()
            pool.existingPage(for: tabID)?.load(link)
        }
    }
}

private struct ReaderToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(height: 28)
            .contentShape(.capsule)
            .background(Capsule().fill(.primary.opacity(configuration.isPressed ? 0.12 : 0)))
            .foregroundStyle(.primary.opacity(0.85))
    }
}

/// The Aa menu: text size, theme, font and line length.
private struct ReaderStylePanel: View {
    @Binding var theme: ReaderStyle.Theme
    @Binding var font: ReaderStyle.Font
    @Binding var fontSize: Int
    @Binding var width: ReaderStyle.Width

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 0) {
                sizeButton(step: -1, label: Text("A").font(.system(size: 13)))
                Divider().frame(height: 20)
                sizeButton(step: 1, label: Text("A").font(.system(size: 20)))
            }
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 9).fill(.primary.opacity(0.06)))
            .overlay(alignment: .bottom) {
                Text("\(Int((Double(fontSize) / Double(ReaderStyle.defaultFontSize) * 100).rounded()))%")
                    .font(.system(size: 9, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .offset(y: 13)
            }
            .padding(.bottom, 6)

            HStack(spacing: 10) {
                ForEach(ReaderStyle.Theme.allCases) { option in
                    Button { theme = option } label: { ThemeSwatch(theme: option, isSelected: theme == option) }
                        .buttonStyle(.plain)
                        .help(option.title)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 2) {
                ForEach(ReaderStyle.Font.allCases) { option in
                    Button { font = option } label: {
                        HStack {
                            Text(option.title).font(preview(option))
                            Spacer()
                            if font == option { Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)) }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .contentShape(.rect)
                        .background(RoundedRectangle(cornerRadius: 7).fill(font == option ? Color.accentColor.opacity(0.14) : .clear))
                    }
                    .buttonStyle(.plain)
                }
            }

            Picker("Line length", selection: $width) {
                ForEach(ReaderStyle.Width.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(14)
        .frame(width: 252)
    }

    private func sizeButton(step: Int, label: Text) -> some View {
        let style = ReaderStyle(fontSize: fontSize)
        let next = style.fontSize(steppedBy: step)
        return Button { fontSize = next } label: {
            label.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(next == fontSize)
        .help(step < 0 ? "Smaller Text" : "Bigger Text")
    }

    private func preview(_ font: ReaderStyle.Font) -> Font {
        switch font {
        case .newYork: .system(size: 14, design: .serif)
        case .sanFrancisco: .system(size: 14)
        case .charter: .custom("Charter", size: 14)
        case .iowan: .custom("Iowan Old Style", size: 14)
        }
    }
}

private struct ThemeSwatch: View {
    let theme: ReaderStyle.Theme
    let isSelected: Bool

    var body: some View {
        ZStack {
            if let colors = theme.colors {
                Circle().fill(Color(hex: colors.background))
                Text("A").font(.system(size: 12, weight: .semibold, design: .serif)).foregroundStyle(Color(hex: colors.text))
            } else {
                // Automatic: half day, half night.
                Circle().fill(Color(hex: "#ffffff"))
                Circle().fill(Color(hex: "#1b1b1d")).mask(Rectangle().offset(x: 15).frame(width: 30))
                Image(systemName: "circle.lefthalf.filled").font(.system(size: 11)).foregroundStyle(.gray)
            }
        }
        .frame(width: 30, height: 30)
        .overlay(Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
        .padding(3)
        .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2).opacity(isSelected ? 1 : 0))
    }
}

private extension Color {
    init(hex: String) {
        let value = UInt64(hex.dropFirst(), radix: 16) ?? 0
        self.init(red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255, blue: Double(value & 0xff) / 255)
    }
}

/// The article in a web view of its own: no scripts, no cookies, nothing saved.
private struct ReaderWebView: NSViewRepresentable {
    let article: ReaderArticle
    let url: URL
    let style: ReaderStyle
    let open: (URL, Bool) -> Void
    let close: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = true
        // Fades in once laid out, so there's no flash of an unstyled page.
        webView.alphaValue = 0
        context.coordinator.attach(to: webView, close: close)
        context.coordinator.style = style
        webView.loadHTMLString(ReaderPage.html(article, style: style, sourceHost: url.host()), baseURL: url)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.open = open
        coordinator.close = close
        guard coordinator.style != style else { return }
        coordinator.style = style
        webView.evaluateJavaScript(style.script)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var style: ReaderStyle?
        var open: (URL, Bool) -> Void = { _, _ in }
        var close: () -> Void = {}
        private var monitor: Any?
        private weak var webView: WKWebView?

        func attach(to webView: WKWebView, close: @escaping () -> Void) {
            self.webView = webView
            self.close = close
            // Escape leaves reader mode.
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53, let webView = self?.webView, event.window === webView.window,
                      let responder = webView.window?.firstResponder as? NSView, responder.isDescendant(of: webView) else { return event }
                self?.close()
                return nil
            }
        }

        func detach() {
            monitor.map(NSEvent.removeMonitor)
            monitor = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.window?.makeFirstResponder(webView)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                webView.animator().alphaValue = 1
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard action.navigationType == .linkActivated, let target = action.request.url else { return .allow }
            // Footnotes and other jumps within the article stay here.
            func page(_ url: URL?) -> Substring? { url?.absoluteString.split(separator: "#", maxSplits: 1).first }
            if target.fragment != nil, page(target) == page(webView.url) { return .allow }
            open(target, action.modifierFlags.contains(.command))
            return .cancel
        }
    }
}

/// Reads the article aloud with the system's voice for its language.
@MainActor
@Observable
final class ReaderSpeaker {
    enum State { case idle, speaking, paused }
    private(set) var state = State.idle
    private let synthesizer = AVSpeechSynthesizer()
    private let delegate = SpeechDelegate()

    init() {
        synthesizer.delegate = delegate
        delegate.onFinish = { [weak self] in
            Task { @MainActor in self?.state = .idle }
        }
    }

    func speak(_ text: String, language: String?) {
        let utterance = AVSpeechUtterance(string: text)
        if let language, let voice = AVSpeechSynthesisVoice(language: language) { utterance.voice = voice }
        synthesizer.speak(utterance)
        state = .speaking
    }

    func pause() {
        synthesizer.pauseSpeaking(at: .word)
        state = .paused
    }

    func resume() {
        synthesizer.continueSpeaking()
        state = .speaking
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        state = .idle
    }
}

private final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    var onFinish: (@Sendable () -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { onFinish?() }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { onFinish?() }
}

import SwiftUI
@preconcurrency import Translation

/// Reader and Translate buttons in the address bar. They show up only when the page offers
/// them: an article for reader mode, a page in another language for translation.
struct PageActionButtons: View {
    let tabID: BrowserTab.ID
    @Environment(PagePool.self) private var pool
    @State private var showsTranslate = false

    var body: some View {
        let tools = pool.tools
        let traits = tools.traits[tabID]
        let isReading = tools.readers[tabID] != nil
        let isOpening = tools.openingReader.contains(tabID)
        let translation = tools.translations[tabID]
        Group {
            if traits?.isReaderable == true || isReading || isOpening {
                Button { withAnimation(.easeOut(duration: 0.2)) { tools.toggleReader(tabID) } } label: {
                    ZStack {
                        if isOpening {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: isReading ? "doc.plaintext.fill" : "doc.plaintext")
                                .font(.system(size: 13))
                                .foregroundStyle(isReading ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
                        }
                    }
                }
                .help(isReading ? "Exit Reader (⇧⌘R)" : "Show Reader (⇧⌘R)")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            if traits?.foreignLanguage != nil || translation != nil {
                Button { showsTranslate = true } label: {
                    Image(systemName: "translate")
                        .font(.system(size: 13))
                        .foregroundStyle(translation != nil ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
                        .symbolEffect(.pulse, isActive: isTranslating(translation))
                }
                .help(translation == nil ? "Translate Page" : "Translation")
                .popover(isPresented: $showsTranslate, arrowEdge: .bottom) {
                    TranslatePopover(tabID: tabID, isPresented: $showsTranslate)
                }
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.2), value: traits)
        .animation(.snappy(duration: 0.2), value: isOpening)
    }

    private func isTranslating(_ state: PageTools.TranslationState?) -> Bool {
        if case .translating? = state { return true }
        return false
    }
}

/// Translate this page: from and to, always translating a language, and back to the original.
/// Pages are translated on this Mac by Apple's Translation; nothing goes to a server.
struct TranslatePopover: View {
    let tabID: BrowserTab.ID
    @Binding var isPresented: Bool
    @Environment(PagePool.self) private var pool
    @State private var source = ""
    @State private var target = PageLanguage.target
    @State private var availability: LanguageAvailability.Status?

    var body: some View {
        let tools = pool.tools
        let state = tools.translations[tabID]
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "translate")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.gradient))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title(for: state)).font(.system(size: 13, weight: .semibold))
                    Text(subtitle(for: state)).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                languagePicker(selection: $source)
                Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                languagePicker(selection: $target)
            }

            if !source.isEmpty {
                Toggle("Always translate \(PageLanguage.name(source))", isOn: alwaysTranslates)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
            }

            switch state {
            case .translating(_, _, let done, let total) where total > 0:
                ProgressView(value: Double(done), total: Double(total)).controlSize(.small)
            case .failed(_, _, let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            default:
                if availability == .unsupported {
                    Label("Apple's Translation can't translate between these languages yet.", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                if state != nil {
                    Button("Show Original") {
                        tools.showOriginal(tabID)
                        isPresented = false
                    }
                }
                Spacer()
                Button(state == nil || isFailed(state) || state?.languages.to != target ? "Translate" : "Done") {
                    if state?.languages.to != target || state?.languages.from != source || isFailed(state) {
                        UserDefaults.standard.set(target, forKey: PreferenceKey.translateTarget)
                        tools.translate(tabID, from: source, to: target)
                    }
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(source.isEmpty || PageLanguage.key(source) == PageLanguage.key(target) || availability == .unsupported)
            }
        }
        .padding(16)
        .frame(width: 320)
        .task {
            let traits = tools.traits[tabID]
            source = state?.languages.from ?? traits?.foreignLanguage ?? traits?.language ?? ""
            if let to = state?.languages.to { target = to }
            await tools.loadSupportedLanguages()
        }
        .task(id: source + ">" + target) { await checkAvailability() }
    }

    private func languagePicker(selection: Binding<String>) -> some View {
        var languages = pool.tools.supportedLanguages
        for extra in [source, target] where !extra.isEmpty && !languages.contains(extra) { languages.insert(extra, at: 0) }
        return Picker("", selection: selection) {
            ForEach(languages, id: \.self) { Text(PageLanguage.name($0)).tag($0) }
        }
        .labelsHidden()
        .frame(maxWidth: .infinity)
    }

    private var alwaysTranslates: Binding<Bool> {
        Binding {
            PageLanguage.autoTranslated.contains(PageLanguage.key(source))
        } set: { on in
            if on { PageLanguage.autoTranslated.insert(PageLanguage.key(source)) }
            else { PageLanguage.autoTranslated.remove(PageLanguage.key(source)) }
        }
    }

    private func checkAvailability() async {
        guard !source.isEmpty else { availability = nil; return }
        availability = await PageTools.availability(from: source, to: target)
    }

    private func title(for state: PageTools.TranslationState?) -> String {
        switch state {
        case .translating: "Translating…"
        case .translated(_, let to): "Translated to \(PageLanguage.name(to))"
        case .failed: "Couldn't translate this page"
        case nil: source.isEmpty ? "Translate Page" : "This page is in \(PageLanguage.name(source))"
        }
    }

    private func subtitle(for state: PageTools.TranslationState?) -> String {
        if state == nil, availability == .supported {
            return "Languages download once, then translate offline."
        }
        return "Translated privately on this Mac."
    }

    private func isFailed(_ state: PageTools.TranslationState?) -> Bool {
        if case .failed? = state { return true }
        return false
    }
}

/// Runs the translation job for the window in front, with the session Apple's Translation
/// hands to a view. If Translation needs to download languages, it asks in this window.
struct TranslationHost: View {
    @Environment(PagePool.self) private var pool
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        let tools = pool.tools
        Color.clear
            .frame(width: 0, height: 0)
            .translationTask(configuration) { session in
                guard let job = tools.job else { return }
                await TranslationRunner.run(job, session: session, tools: tools)
            }
            .onChange(of: tools.job, initial: true) { _, job in start(job) }
    }

    private func start(_ job: PageTools.Job?) {
        guard let job else { return }
        let source = Locale.Language(identifier: job.source), target = Locale.Language(identifier: job.target)
        if configuration?.source == source, configuration?.target == target {
            configuration?.invalidate()
        } else {
            configuration = .init(source: source, target: target)
        }
    }
}

import Foundation
import Observation
import SwiftUI
@preconcurrency import Translation

/// Reader mode and translation for each tab's page. Pages are probed once they load, so the
/// address bar can offer reader mode for articles and translation for pages in another language.
@MainActor
@Observable
final class PageTools {
    @ObservationIgnored weak var pool: PagePool?

    /// What a loaded page offers.
    struct Traits: Equatable {
        var isReaderable: Bool
        /// The page's language, when it's one the person doesn't read.
        var foreignLanguage: String?
        /// The page's language, foreign or not.
        var language: String?
    }

    private(set) var traits: [BrowserTab.ID: Traits] = [:]
    /// Tabs showing reader mode, with their article.
    private(set) var readers: [BrowserTab.ID: ReaderArticle] = [:]
    /// Tabs whose article is being found.
    private(set) var openingReader: Set<BrowserTab.ID> = []
    /// "Reader isn't available" over a tab's page, briefly.
    private(set) var notice: (tabID: BrowserTab.ID, text: String, count: Int)?

    enum TranslationState: Equatable {
        case translating(from: String, to: String, done: Int, total: Int)
        case translated(from: String, to: String)
        case failed(from: String, to: String, message: String)

        var languages: (from: String, to: String) {
            switch self {
            case .translating(let from, let to, _, _), .translated(let from, let to), .failed(let from, let to, _): (from, to)
            }
        }
    }

    private(set) var translations: [BrowserTab.ID: TranslationState] = [:]

    /// The translation running now. One at a time; the window in front runs it (see
    /// TranslationHost), since Apple's Translation only works from a view.
    struct Job: Equatable {
        let id = UUID()
        let tabID: BrowserTab.ID
        let source: String
        let target: String
    }

    private(set) var job: Job?
    /// Languages Apple's Translation can translate between, once loaded.
    private(set) var supportedLanguages: [String] = []

    @ObservationIgnored private var urls: [BrowserTab.ID: URL] = [:]
    @ObservationIgnored private var probedURLs: [BrowserTab.ID: URL] = [:]
    @ObservationIgnored private var probes: [BrowserTab.ID: Task<Void, Never>] = [:]

    // MARK: Page events (from PagePool)

    /// A new address that's more than a jump within the page starts over.
    func page(_ id: BrowserTab.ID, didChangeURL url: URL) {
        let page = url.withoutFragment
        guard urls[id] != page else { return }
        let hadURL = urls[id] != nil
        urls[id] = page
        guard hadURL else { return }
        traits[id] = nil
        if readers[id] != nil { readers[id] = nil }
        if translations[id] != nil { translations[id] = nil }
        if job?.tabID == id { job = nil }
    }

    func pageFinishedLoading(_ id: BrowserTab.ID) {
        // A reload brings back the page's own text; one that stays translated translates again.
        if let state = translations[id], job?.tabID != id, case .translated = state {
            translate(id, from: state.languages.from, to: state.languages.to)
        }
        probes[id]?.cancel()
        probes[id] = Task {
            // Let the page settle: many fill in their content right after loading.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await probe(id)
        }
    }

    func forget(_ id: BrowserTab.ID) {
        probes.removeValue(forKey: id)?.cancel()
        urls[id] = nil
        probedURLs[id] = nil
        traits[id] = nil
        readers[id] = nil
        translations[id] = nil
        openingReader.remove(id)
        if job?.tabID == id { job = nil }
    }

    private func probe(_ id: BrowserTab.ID) async {
        guard let page = pool?.existingPage(for: id), let url = urls[id], probedURLs[id] != url,
              let json = await page.evaluate(PageScripts.probe),
              let probe = try? JSONDecoder().decode(PageScripts.Probe.self, from: Data(json.utf8)),
              urls[id] == url else { return }
        probedURLs[id] = url
        let language = PageLanguage.detect(sample: probe.sample, declared: probe.lang)
        let foreign = language.flatMap { PageLanguage.isForeign($0) ? $0 : nil }
        traits[id] = Traits(isReaderable: probe.readerable, foreignLanguage: foreign, language: language)
        // Translate ▸ Always translate this language.
        if let foreign, translations[id] == nil, PageLanguage.autoTranslated.contains(PageLanguage.key(foreign)) {
            translate(id, from: foreign, to: PageLanguage.target)
        }
    }

    // MARK: Reader

    func toggleReader(_ id: BrowserTab.ID?) {
        guard let id else { return }
        if readers[id] != nil {
            readers[id] = nil
        } else {
            Task { await openReader(id) }
        }
    }

    func closeReader(_ id: BrowserTab.ID) { readers[id] = nil }

    private func openReader(_ id: BrowserTab.ID) async {
        guard let page = pool?.existingPage(for: id), !openingReader.contains(id) else { return }
        openingReader.insert(id)
        let json = await page.evaluate(PageScripts.readerArticle, timeout: .seconds(15))
        openingReader.remove(id)
        if let json, let article = try? JSONDecoder().decode(ReaderArticle.self, from: Data(json.utf8)), article.isUsable {
            readers[id] = article
        } else {
            show("Reader isn't available for this page", on: id)
        }
    }

    private func show(_ text: String, on id: BrowserTab.ID) {
        let count = (notice?.count ?? 0) + 1
        notice = (id, text, count)
        Task {
            try? await Task.sleep(for: .seconds(2))
            if notice?.count == count { notice = nil }
        }
    }

    // MARK: Translation

    func translate(_ id: BrowserTab.ID, from source: String, to target: String) {
        // Text already translated into another language goes back first.
        if case .translated(_, let previous)? = translations[id], previous != target {
            pool?.existingPage(for: id)?.evaluate(PageScripts.restoreOriginal) { _ in }
        }
        translations[id] = .translating(from: source, to: target, done: 0, total: 0)
        job = Job(tabID: id, source: source, target: target)
    }

    /// Translates a page from the language it was found to be in, or shows it untranslated
    /// again.
    func toggleTranslation(_ id: BrowserTab.ID?) {
        guard let id else { return }
        if translations[id] != nil {
            showOriginal(id)
            return
        }
        let source = traits[id]?.foreignLanguage ?? traits[id]?.language
        guard let source else {
            show("Couldn't tell which language this page is in", on: id)
            return
        }
        translate(id, from: source, to: PageLanguage.target)
    }

    func showOriginal(_ id: BrowserTab.ID) {
        if job?.tabID == id { job = nil }
        translations[id] = nil
        pool?.existingPage(for: id)?.evaluate(PageScripts.restoreOriginal) { _ in }
    }

    func loadSupportedLanguages() async {
        guard supportedLanguages.isEmpty else { return }
        supportedLanguages = Set(await Self.translatableLanguages())
            .sorted { PageLanguage.name($0).localizedStandardCompare(PageLanguage.name($1)) == .orderedAscending }
    }

    nonisolated private static func translatableLanguages() async -> [String] {
        await LanguageAvailability().supportedLanguages.map(\.minimalIdentifier)
    }

    nonisolated static func availability(from source: String, to target: String) async -> LanguageAvailability.Status {
        await LanguageAvailability().status(from: Locale.Language(identifier: source), to: Locale.Language(identifier: target))
    }

    /// The next texts for `job` to translate: nil once the job is over, empty when there's
    /// nothing new yet.
    func nextTexts(for job: Job) async -> [PageScripts.TranslationBatch.Item]? {
        guard self.job == job, let page = pool?.existingPage(for: job.tabID) else { return nil }
        guard let json = await page.evaluate(PageScripts.nextTexts()),
              let batch = try? JSONDecoder().decode(PageScripts.TranslationBatch.self, from: Data(json.utf8)) else { return [] }
        guard self.job == job else { return nil }
        let total = batch.total
        let done = total - batch.remaining - batch.items.count
        if batch.items.isEmpty {
            let translated = TranslationState.translated(from: job.source, to: job.target)
            if translations[job.tabID] != translated { translations[job.tabID] = translated }
        } else if case .translating? = translations[job.tabID] {
            translations[job.tabID] = .translating(from: job.source, to: job.target, done: done, total: total)
        }
        return batch.items
    }

    func apply(_ translated: [Int: String], for job: Job) async {
        guard self.job == job, let page = pool?.existingPage(for: job.tabID) else { return }
        _ = await page.evaluate(PageScripts.applyTranslations(translated))
    }

    func translationFailed(_ job: Job, message: String) {
        guard self.job == job else { return }
        self.job = nil
        translations[job.tabID] = .failed(from: job.source, to: job.target, message: message)
    }

    /// Whether the job is still the one running. The view that runs it checks this between
    /// batches.
    func isRunning(_ job: Job) -> Bool { self.job == job }
}

/// Runs a translation job with the session SwiftUI's `translationTask` hands out, batch by
/// batch, then keeps an eye out for text the page adds (more results, comments, a new view in
/// a web app) until the job ends.
enum TranslationRunner {
    /// On the main actor, where `translationTask` hands the session out: the session isn't
    /// Sendable, so it stays where it was given.
    @MainActor static func run(_ job: PageTools.Job, session: TranslationSession, tools: PageTools) async {
        do {
            try await session.prepareTranslation()
        } catch {
            tools.translationFailed(job, message: message(for: error))
            return
        }
        while !Task.isCancelled {
            guard let items = await tools.nextTexts(for: job) else { return }
            if items.isEmpty {
                try? await Task.sleep(for: .seconds(1.5))
                continue
            }
            // Built here and only handed to the session, never touched again.
            nonisolated(unsafe) let requests = items.map { TranslationSession.Request(sourceText: $0.text, clientIdentifier: String($0.id)) }
            do {
                let responses = try await session.translations(from: requests)
                var translated: [Int: String] = [:]
                for response in responses {
                    if let id = response.clientIdentifier.flatMap(Int.init) { translated[id] = response.targetText }
                }
                await tools.apply(translated, for: job)
            } catch {
                guard !Task.isCancelled, tools.isRunning(job) else { return }
                tools.translationFailed(job, message: message(for: error))
                return
            }
        }
    }

    nonisolated private static func message(for error: Error) -> String {
        if let error = error as? TranslationError, let reason = error.failureReason { return reason }
        return error.localizedDescription
    }
}

private extension URL {
    var withoutFragment: URL {
        guard fragment != nil, var parts = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        parts.fragment = nil
        return parts.url ?? self
    }
}

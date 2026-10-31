import Foundation

/// Scripts Embark runs in pages with `BrowserPage.evaluate`, for reader mode and translation.
/// Each is one JavaScript expression.
enum PageScripts {
    /// After a page loads: whether it reads as an article, and a sample of its text and its
    /// declared language, to tell which language it's in. Decodes as `Probe`.
    static let probe = """
    (() => {
      \(resource("Readability-readerable"))
      const out = { readerable: false, lang: document.documentElement.lang || '', sample: '' };
      try { out.readerable = isProbablyReaderable(document); } catch (e) {}
      const skip = /^(SCRIPT|STYLE|NOSCRIPT|TEMPLATE|CODE|PRE|SVG)$/i;
      const root = document.body || document.documentElement;
      const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
        acceptNode: (n) => skip.test(n.parentNode?.nodeName || '') ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT
      });
      while (out.sample.length < 2000 && walker.nextNode()) {
        const text = walker.currentNode.nodeValue.trim();
        if (text.length > 1) out.sample += text + ' ';
      }
      return out;
    })()
    """

    struct Probe: Decodable {
        var readerable: Bool
        var lang: String
        var sample: String
    }

    /// The page's article, found by Mozilla's Readability in a copy of the page, so the page
    /// itself is untouched. Decodes as `ReaderArticle`, or null when there's none.
    static let readerArticle = """
    (() => {
      \(resource("Readability"))
      const article = new Readability(document.cloneNode(true), { charThreshold: 400 }).parse();
      if (!article) return null;
      const { title, byline, siteName, content, textContent, lang, dir, publishedTime } = article;
      return { title, byline, siteName, content, textContent, lang, dir, publishedTime };
    })()
    """

    // MARK: Translation

    /// The page's text not yet sent for translation, at most `limit` pieces and about
    /// `maxCharacters` at a time, what's on screen first. Text the page adds later is picked up
    /// by later calls. Decodes as `TranslationBatch`.
    static func nextTexts(limit: Int = 60, maxCharacters: Int = 4000) -> String {
        """
        (() => {
          const state = window.__embarkTranslation ??= { nodes: [], originals: [], queue: [], seen: new WeakSet(), dirty: true };
          if (!state.observer) {
            state.observer = new MutationObserver(() => { state.dirty = true; });
            state.observer.observe(document.documentElement, { childList: true, subtree: true, characterData: true });
          }
          if (state.dirty) {
            state.dirty = false;
            const skip = /^(SCRIPT|STYLE|NOSCRIPT|TEMPLATE|CODE|PRE|KBD|SAMP|VAR|TEXTAREA|INPUT|SELECT|OPTION|SVG|MATH|CANVAS|IFRAME)$/i;
            const found = [];
            const walker = document.createTreeWalker(document.body || document.documentElement, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT, {
              acceptNode: (n) => {
                if (n.nodeType === 1) {
                  if (skip.test(n.nodeName) || n.translate === false || n.isContentEditable || n.classList.contains('notranslate')) return NodeFilter.FILTER_REJECT;
                  return NodeFilter.FILTER_SKIP;
                }
                if (state.seen.has(n) || !/\\p{L}/u.test(n.nodeValue)) return NodeFilter.FILTER_SKIP;
                return NodeFilter.FILTER_ACCEPT;
              }
            });
            while (walker.nextNode() && state.nodes.length + found.length < 20000) {
              state.seen.add(walker.currentNode);
              found.push(walker.currentNode);
            }
            const height = window.innerHeight;
            const onScreen = (node) => {
              const rect = node.parentElement?.getBoundingClientRect();
              return rect && rect.bottom > 0 && rect.top < height && rect.width > 0;
            };
            const visible = found.filter(onScreen), shown = new Set(visible);
            for (const node of [...visible, ...found.filter((n) => !shown.has(n))]) {
              state.queue.push(state.nodes.length);
              state.nodes.push(node);
              state.originals.push(node.nodeValue);
            }
          }
          const items = [];
          let characters = 0;
          while (state.queue.length && items.length < \(limit) && characters < \(maxCharacters)) {
            const id = state.queue.shift();
            const text = state.originals[id].replace(/\\s+/g, ' ').trim();
            characters += text.length;
            items.push({ id, text });
          }
          return { items, remaining: state.queue.length, total: state.nodes.length };
        })()
        """
    }

    struct TranslationBatch: Decodable {
        struct Item: Decodable {
            var id: Int
            var text: String
        }
        var items: [Item]
        var remaining: Int
        var total: Int
    }

    /// Puts translations in place of the text `nextTexts` handed out, keeping its spacing.
    static func applyTranslations(_ translations: [Int: String]) -> String {
        let pairs = translations.map { [String($0.key), $0.value] }
        let json = ((try? JSONSerialization.data(withJSONObject: pairs)).map { String(decoding: $0, as: UTF8.self) } ?? "[]")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return """
        (() => {
          const state = window.__embarkTranslation;
          if (!state) return 0;
          const pairs = \(json);
          for (const [id, text] of pairs) {
            const node = state.nodes[Number(id)], original = state.originals[Number(id)];
            if (!node || node.nodeValue !== original) continue;
            const lead = original.match(/^\\s*/)[0], trail = original.match(/\\s*$/)[0];
            node.nodeValue = lead + text + trail;
          }
          return pairs.length;
        })()
        """
    }

    /// Puts the page's own text back and stops picking up new text.
    static let restoreOriginal = """
    (() => {
      const state = window.__embarkTranslation;
      if (!state) return false;
      state.observer?.disconnect();
      state.nodes.forEach((node, id) => { node.nodeValue = state.originals[id]; });
      delete window.__embarkTranslation;
      return true;
    })()
    """

    private static func resource(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            NSLog("Embark: \(name).js is missing from the app")
            return ""
        }
        return source
    }
}

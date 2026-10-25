import Foundation

/// Search suggestions in the command bar, fetched from the search engine chosen in Settings.
/// Every engine here answers in the OpenSearch suggestions format: `["query", ["one", "two"]]`.
extension SearchEngine {
    /// nil for engines without a public suggestions endpoint.
    func suggestionsURL(for query: String) -> URL? {
        let (base, name, extra): (String, String, [URLQueryItem]) = switch self {
        case .google: ("https://suggestqueries.google.com/complete/search", "q", [URLQueryItem(name: "client", value: "firefox")])
        case .duckDuckGo: ("https://duckduckgo.com/ac/", "q", [URLQueryItem(name: "type", value: "list")])
        case .bing: ("https://api.bing.com/osjson.aspx", "query", [])
        case .brave: ("https://search.brave.com/api/suggest", "q", [])
        case .ecosia: ("https://ac.ecosia.org/autocomplete", "q", [URLQueryItem(name: "type", value: "list")])
        case .kagi, .perplexity: ("", "", [])
        }
        guard !base.isEmpty else { return nil }
        var components = URLComponents(string: base)
        components?.queryItems = [URLQueryItem(name: name, value: query)] + extra
        return components?.url
    }
}

enum SearchSuggestions {
    /// The suggestions in an OpenSearch response, without the query itself and without repeats.
    static func parse(_ data: Data, query: String, limit: Int = 4) -> [String] {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [Any], array.count > 1,
              let suggestions = array[1] as? [Any] else { return [] }
        let typed = query.trimmingCharacters(in: .whitespaces).lowercased()
        var seen: Set<String> = [typed]
        var out: [String] = []
        for case let text as String in suggestions {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            out.append(trimmed)
            if out.count == limit { break }
        }
        return out
    }

    /// No cookies or cache, so the engine can't tie suggestions to a signed-in account.
    private static let session = URLSession(configuration: .ephemeral)

    static func fetch(_ query: String, engine: SearchEngine = .current()) async -> [String] {
        guard let url = engine.suggestionsURL(for: query) else { return [] }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return parse(data, query: query)
    }
}

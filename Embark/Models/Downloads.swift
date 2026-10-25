import Foundation

/// A file the engine is saving, or has saved, to the Downloads folder.
struct Download: Identifiable, Equatable {
    enum State: Equatable {
        case inProgress, complete, canceled, failed
    }

    /// The engine's id for the download.
    let id: UInt32
    var url: URL?
    var fileName: String
    /// Where the file is saved once it has a destination.
    var fileURL: URL?
    var receivedBytes: Int64 = 0
    /// Nil while the size is unknown.
    var totalBytes: Int64?
    var bytesPerSecond: Int64 = 0
    var state: State = .inProgress
    var startedAt = Date.now

    /// 0 to 1, or nil while the size is unknown.
    var fraction: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(Double(receivedBytes) / Double(totalBytes), 1)
    }

    /// "12.3 MB of 40 MB · 2 MB/s", "40 MB", "Canceled".
    var status: String {
        switch state {
        case .complete: return Self.bytes(totalBytes ?? receivedBytes)
        case .canceled: return "Canceled"
        case .failed: return "Failed"
        case .inProgress:
            var text = Self.bytes(receivedBytes)
            if let totalBytes { text += " of \(Self.bytes(totalBytes))" }
            if bytesPerSecond > 0 { text += " · \(Self.bytes(bytesPerSecond))/s" }
            return text
        }
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    /// A destination in `directory` that doesn't overwrite an existing file: "report.pdf",
    /// then "report (1).pdf", "report (2).pdf".
    static func destination(for suggestedName: String, in directory: URL,
                            exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL {
        let name = sanitized(suggestedName)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = directory.appending(path: name)
        var number = 1
        while exists(candidate) {
            let numbered = "\(base) (\(number))" + (ext.isEmpty ? "" : ".\(ext)")
            candidate = directory.appending(path: numbered)
            number += 1
        }
        return candidate
    }

    /// Keeps a site's suggested name from escaping the folder or hiding the file.
    static func sanitized(_ name: String) -> String {
        var cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "download" : cleaned
    }
}

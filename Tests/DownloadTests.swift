import Foundation
import Testing

/// Where downloads are saved, and how their progress reads.
struct DownloadTests {
    private let folder = URL(filePath: "/Users/test/Downloads", directoryHint: .isDirectory)

    @Test func aNewNameIsUsedAsIs() {
        let url = Download.destination(for: "report.pdf", in: folder) { _ in false }
        #expect(url.lastPathComponent == "report.pdf")
    }

    @Test func existingFilesAreNotOverwritten() {
        let taken: Set<String> = ["report.pdf", "report (1).pdf"]
        let url = Download.destination(for: "report.pdf", in: folder) { taken.contains($0.lastPathComponent) }
        #expect(url.lastPathComponent == "report (2).pdf")
    }

    @Test func namesWithoutAnExtensionAreNumberedToo() {
        let url = Download.destination(for: "README", in: folder) { $0.lastPathComponent == "README" }
        #expect(url.lastPathComponent == "README (1)")
    }

    @Test func suggestedNamesStayInsideTheFolder() {
        #expect(Download.sanitized("../../etc/passwd") == "-..-etc-passwd")
        #expect(Download.sanitized(".hidden") == "hidden")
        #expect(Download.sanitized("  ") == "download")
        let url = Download.destination(for: "a/b.txt", in: folder) { _ in false }
        #expect(url.deletingLastPathComponent().path() == folder.path())
    }

    @Test func progressNeedsAKnownSize() {
        var download = Download(id: 1, fileName: "a.zip")
        download.receivedBytes = 50
        #expect(download.fraction == nil)
        download.totalBytes = 200
        #expect(download.fraction == 0.25)
        download.receivedBytes = 300
        #expect(download.fraction == 1)
    }

    @Test func statusDescribesEachState() {
        var download = Download(id: 1, fileName: "a.zip", totalBytes: 2_000_000)
        download.receivedBytes = 1_000_000
        #expect(download.status.contains(" of "))
        download.state = .canceled
        #expect(download.status == "Canceled")
        download.state = .complete
        #expect(download.status == Download.bytes(2_000_000))
    }
}

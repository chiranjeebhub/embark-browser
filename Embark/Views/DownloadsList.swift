import SwiftUI
import UniformTypeIdentifiers

/// The sidebar's downloads button, bottom left. It shows overall progress as a ring and
/// opens the list by itself when a new download starts.
struct DownloadsButton: View {
    @Environment(PagePool.self) private var pool
    @State private var showsList = false

    var body: some View {
        Button { showsList = true } label: {
            Image(systemName: pool.activeDownloads.isEmpty ? "arrow.down.circle" : "arrow.down")
                .font(.system(size: pool.activeDownloads.isEmpty ? 15 : 10, weight: .semibold))
                .overlay {
                    if !pool.activeDownloads.isEmpty { ProgressRing(fraction: overallFraction).frame(width: 17, height: 17) }
                }
        }
        .help("Downloads")
        .popover(isPresented: $showsList, arrowEdge: .top) { DownloadsPopover() }
        .onChange(of: pool.downloadStartCount) { showsList = true }
    }

    /// Bytes received over bytes expected, across downloads whose size is known.
    private var overallFraction: Double? {
        let sized = pool.activeDownloads.filter { $0.totalBytes != nil }
        let total = sized.reduce(Int64(0)) { $0 + ($1.totalBytes ?? 0) }
        guard total > 0 else { return nil }
        return Double(sized.reduce(Int64(0)) { $0 + $1.receivedBytes }) / Double(total)
    }
}

/// A thin circular progress track; spins when the size is unknown.
private struct ProgressRing: View {
    let fraction: Double?
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.15), lineWidth: 2)
            Circle()
                .trim(from: 0, to: fraction ?? 0.25)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90 + (fraction == nil && spin ? 360 : 0)))
                .animation(fraction == nil ? .linear(duration: 1).repeatForever(autoreverses: false) : .smooth, value: spin)
                .animation(.smooth, value: fraction)
        }
        .onAppear { spin = true }
    }
}

/// This session's downloads, newest first. Click a finished one to open it, or drag it out.
struct DownloadsPopover: View {
    @Environment(PagePool.self) private var pool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Downloads").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.bottom, 4)
            if pool.downloads.isEmpty {
                Text("No downloads yet").font(.system(size: 13)).foregroundStyle(.secondary)
                    .padding(8)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(pool.downloads) { download in DownloadRow(download: download) }
                    }
                }
                .frame(maxHeight: 360)
                .fixedSize(horizontal: false, vertical: true)
            }
            Divider().padding(.vertical, 4)
            HStack {
                Button("Show in Finder") { NSWorkspace.shared.open(PagePool.downloadsFolder) }
                Spacer()
                Button("Clear") { pool.clearFinishedDownloads() }
                    .disabled(pool.downloads.allSatisfy { $0.state == .inProgress })
                    .opacity(pool.downloads.isEmpty ? 0 : 1)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
            .padding(.horizontal, 8)
        }
        .padding(8)
        .frame(width: 300)
    }
}

private struct DownloadRow: View {
    let download: Download
    @Environment(PagePool.self) private var pool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: icon).resizable().frame(width: 32, height: 32)
                .opacity(download.state == .complete || download.state == .inProgress ? 1 : 0.45)
            VStack(alignment: .leading, spacing: 3) {
                Text(download.fileName).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                if download.state == .inProgress {
                    if let fraction = download.fraction {
                        ProgressView(value: fraction).controlSize(.mini)
                    } else {
                        ProgressView().progressViewStyle(.linear).controlSize(.mini)
                    }
                }
                Text(download.status).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 4)
            action
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(.primary.opacity(hovering && isOpenable ? 0.07 : 0)))
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .onTapGesture { if isOpenable, let file = download.fileURL { NSWorkspace.shared.open(file) } }
        .onDrag {
            guard isOpenable, let file = download.fileURL else { return NSItemProvider() }
            return NSItemProvider(contentsOf: file) ?? NSItemProvider()
        }
        .help(download.url?.host() ?? download.fileName)
    }

    @ViewBuilder private var action: some View {
        switch download.state {
        case .inProgress:
            Button { pool.cancelDownload(download.id) } label: { Image(systemName: "xmark.circle.fill") }
                .help("Cancel")
                .buttonStyle(.borderless).foregroundStyle(.secondary)
        case .complete:
            Button { NSWorkspace.shared.activateFileViewerSelecting([download.fileURL].compactMap { $0 }) } label: {
                Image(systemName: "magnifyingglass")
            }
            .help("Show in Finder")
            .buttonStyle(.borderless).foregroundStyle(.secondary)
            .opacity(hovering ? 1 : 0)
        case .canceled, .failed:
            EmptyView()
        }
    }

    private var isOpenable: Bool {
        download.state == .complete && download.fileURL.map { FileManager.default.fileExists(atPath: $0.path) } == true
    }

    private var icon: NSImage {
        if isOpenable, let file = download.fileURL { return NSWorkspace.shared.icon(forFile: file.path) }
        let ext = (download.fileName as NSString).pathExtension
        return NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
    }
}

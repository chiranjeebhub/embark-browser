import AppKit
import SwiftUI

/// macOS's share menu (AirDrop, Messages, Mail, Notes, Reminders, and apps that add their own)
/// for a page. It opens from the address bar's share button when the sidebar shows, otherwise
/// from the top of the page.
@MainActor
enum PageSharing {
    static func share(_ url: URL, in window: NSWindow? = NSApp.keyWindow) {
        guard let window, let contentView = window.contentView else { return }
        let picker = NSSharingServicePicker(items: [url])
        if let anchor = anchors[ObjectIdentifier(window)]?.view, anchor.window === window, !anchor.isHiddenOrHasHiddenAncestor,
           anchor.visibleRect.width > 0 {
            picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: anchor.isFlipped ? .maxY : .minY)
        } else {
            // Top middle of the window, under the title bar.
            let bounds = contentView.bounds
            let rect = NSRect(x: bounds.midX - 1, y: contentView.isFlipped ? 40 : bounds.maxY - 40, width: 2, height: 2)
            picker.show(relativeTo: rect, of: contentView, preferredEdge: contentView.isFlipped ? .maxY : .minY)
        }
    }

    /// The share button in each window, to open the menu under it.
    fileprivate static var anchors: [ObjectIdentifier: WeakView] = [:]

    fileprivate struct WeakView { weak var view: NSView? }
}

/// The address bar's share button.
struct ShareButton: View {
    let url: URL

    var body: some View {
        Button { PageSharing.share(url) } label: {
            Image(systemName: "square.and.arrow.up").font(.system(size: 13)).offset(y: -1)
        }
        .help("Share")
        .background(ShareAnchor())
    }
}

/// Marks where a window's share menu opens from.
private struct ShareAnchor: NSViewRepresentable {
    final class AnchorView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { PageSharing.anchors[ObjectIdentifier(window)] = .init(view: self) }
        }
    }

    func makeNSView(context: Context) -> AnchorView { AnchorView() }
    func updateNSView(_ view: AnchorView, context: Context) {}
}

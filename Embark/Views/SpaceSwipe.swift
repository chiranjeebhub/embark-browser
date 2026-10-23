import AppKit
import SwiftUI

/// Two-finger horizontal swipes over the sidebar switch spaces, following the fingers like
/// Arc: the space's content slides, the neighbor slides in, and the tint blends. Watches the
/// window's scroll events instead of adding a view, so nothing in the sidebar changes how it
/// scrolls; only mostly horizontal trackpad gestures over the sidebar are taken.
@MainActor
final class SpaceSwipeTracker {
    /// The sidebar's frame in window coordinates (origin top left).
    var frame: CGRect = .zero
    weak var store: BrowserStore?
    private var monitor: Any?
    private var state = State.idle
    private var offset: CGFloat = 0
    private var samples: [(time: TimeInterval, offset: CGFloat)] = []

    private enum State {
        /// No gesture, or one not ours.
        case idle
        /// Fingers down over the sidebar; waiting to see which way they go.
        case undecided
        case tracking
        /// Vertical, or started elsewhere: passed through until it ends.
        case ignoring
        /// Ours ended; momentum events are swallowed so the tab list doesn't scroll.
        case settling
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            // Monitors run on the main thread; NSEvent just isn't Sendable.
            nonisolated(unsafe) let event = event
            nonisolated(unsafe) var result: NSEvent? = event
            MainActor.assumeIsolated { result = self?.handle(event) ?? event }
            return result
        }
    }

    func stop() {
        monitor.map(NSEvent.removeMonitor)
        monitor = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        // Trackpad gestures only, and only with the system's "Swipe between pages" on.
        // Events posted without a window (synthesized ones) carry a screen location instead.
        let window = event.window ?? NSApp.windows.first { $0.isVisible && $0.frame.contains(event.locationInWindow) }
        guard event.hasPreciseScrollingDeltas, NSEvent.isSwipeTrackingFromScrollEventsEnabled,
              let window, let content = window.contentView, let store else { return event }

        if !event.momentumPhase.isEmpty {
            if state == .settling {
                if event.momentumPhase == .ended || event.momentumPhase == .cancelled { state = .idle }
                return nil
            }
            return event
        }

        switch event.phase {
        case .mayBegin, .began:
            let location = event.window == nil ? window.convertPoint(fromScreen: event.locationInWindow) : event.locationInWindow
            let point = CGPoint(x: location.x, y: content.bounds.height - location.y)
            if state == .idle || state == .settling, frame.contains(point), !store.isCreatingSpace {
                state = .undecided
                offset = 0
                samples = []
            }
            return event
        case .changed:
            let dx = fingerDelta(event), dy = event.scrollingDeltaY
            if state == .undecided {
                guard dx != 0 || dy != 0 else { return event }
                state = abs(dx) > abs(dy) * 1.5 ? .tracking : .ignoring
            }
            guard state == .tracking else { return event }
            offset += dx
            samples.append((event.timestamp, offset))
            samples.removeAll { event.timestamp - $0.time > 0.1 }
            store.swipeProgress = progress(for: offset)
            return nil
        case .ended, .cancelled:
            defer { if state != .settling { state = .idle } }
            guard state == .tracking else { return event }
            finish()
            state = .settling
            return nil
        default:
            return event
        }
    }

    /// Movement in the direction the fingers went, whatever the scrolling direction setting.
    private func fingerDelta(_ event: NSEvent) -> CGFloat {
        event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
    }

    /// Positive reveals the previous space. Past the first or last space it resists.
    private func progress(for offset: CGFloat) -> CGFloat {
        guard let store, frame.width > 0 else { return 0 }
        let raw = offset / frame.width
        if store.neighborSpace(towardProgress: raw) == nil {
            return (raw < 0 ? -1 : 1) * min(abs(raw) * 0.25, 0.12)
        }
        return min(max(raw, -1), 1)
    }

    private func finish() {
        guard let store else { return }
        let progress = store.swipeProgress
        let velocity: CGFloat = {
            guard let first = samples.first, let last = samples.last, last.time > first.time else { return 0 }
            return (last.offset - first.offset) / CGFloat(last.time - first.time)
        }()
        let flick = abs(velocity) > 500 && (velocity < 0) == (progress < 0) && abs(progress) > 0.04
        guard let neighbor = store.neighborSpace(towardProgress: progress), abs(progress) > 0.3 || flick else {
            withAnimation(.spring(duration: 0.25)) { store.swipeProgress = 0 }
            return
        }
        withAnimation(.spring(duration: 0.25), completionCriteria: .logicallyComplete) {
            store.swipeProgress = progress < 0 ? -1 : 1
        } completion: {
            // The neighbor is now exactly where the selected space's content goes, so the
            // switch itself must not animate.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                store.selectSpace(neighbor.id)
                store.swipeProgress = 0
            }
        }
    }
}

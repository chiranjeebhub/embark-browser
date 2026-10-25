import Foundation

/// The sidebar drag in progress, as its token ("embark-tab:<id>" and so on). Drop targets show
/// placeholders and highlights only while there is one, and reset their own state whenever
/// `changes` moves on (a drag starting or ending), so nothing can be left behind.
struct DragSession: Equatable {
    private(set) var token: String?
    /// Counts starts and ends.
    private(set) var changes = 0

    var isActive: Bool { token != nil }

    mutating func begin(_ token: String) {
        self.token = token
        changes += 1
    }

    /// Ends the drag, however it ended: dropped, dropped elsewhere or cancelled. Safe to repeat.
    mutating func finish() {
        token = nil
        changes += 1
    }
}

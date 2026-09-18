import SwiftUI
import AppKit

/// Bidirectional scroll bridge between the editor and the preview. Both panes
/// publish the top-visible **source-line number** (1-indexed, computed against
/// the original markdown source) whenever they scroll, and both react to the
/// other pane's updates by scrolling to their local representation of that
/// same source line.
///
/// Line-anchored (not proportional): a page of raw markdown ≠ a page of the
/// rendered version — tables, headings, images all expand or contract the
/// visual footprint — so proportional-offset sync drifts. Using source lines
/// as the common coordinate makes the drift go away.
@MainActor
final class ScrollSync: ObservableObject {
    @Published var sourceLine: Int = 1
    /// Whoever set `sourceLine` most recently. The other pane checks this
    /// before scrolling to avoid feedback loops.
    var owner: ObjectIdentifier?
}

extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self {
        min(max(self, r.lowerBound), r.upperBound)
    }
}

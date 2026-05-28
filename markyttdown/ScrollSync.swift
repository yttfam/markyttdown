import SwiftUI
import AppKit

@MainActor
final class ScrollSync: ObservableObject {
    @Published var progress: Double = 0
    var owner: ObjectIdentifier?
}

extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self {
        min(max(self, r.lowerBound), r.upperBound)
    }
}

@MainActor
enum ScrollSyncHelper {
    static func progress(of sv: NSScrollView) -> Double {
        guard let doc = sv.documentView else { return 0 }
        let scrollable = max(0, doc.frame.height - sv.contentView.bounds.height)
        if scrollable == 0 { return 0 }
        return Double(sv.contentView.bounds.origin.y / scrollable).clamped(to: 0...1)
    }

    static func apply(progress p: Double, to sv: NSScrollView) {
        guard let doc = sv.documentView else { return }
        let scrollable = max(0, doc.frame.height - sv.contentView.bounds.height)
        let y = CGFloat(p) * scrollable
        if abs(sv.contentView.bounds.origin.y - y) < 0.5 { return }
        sv.contentView.scroll(to: NSPoint(x: 0, y: y))
        sv.reflectScrolledClipView(sv.contentView)
    }
}

import SwiftUI

@MainActor
final class Zoom: ObservableObject {
    static let minLevel: Double = 0.5
    static let maxLevel: Double = 3.0
    private static let step: Double = 1.2

    @Published var level: Double {
        didSet {
            UserDefaults.standard.set(level, forKey: Self.storageKey)
        }
    }

    init() {
        let stored = UserDefaults.standard.double(forKey: Self.storageKey)
        let clamped = stored >= Self.minLevel && stored <= Self.maxLevel ? stored : 1.0
        self.level = clamped
    }

    func zoomIn()    { level = min(level * Self.step, Self.maxLevel) }
    func zoomOut()   { level = max(level / Self.step, Self.minLevel) }
    func actualSize() { level = 1.0 }

    private static let storageKey = "previewZoom"
}

private struct ZoomKey: FocusedValueKey {
    typealias Value = Zoom
}

extension FocusedValues {
    var zoom: Zoom? {
        get { self[ZoomKey.self] }
        set { self[ZoomKey.self] = newValue }
    }
}

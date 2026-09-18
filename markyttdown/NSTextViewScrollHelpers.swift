import AppKit

extension NSTextView {
    /// The character offset that lies at the top of the current visible rect,
    /// or 0 if it can't be resolved yet (view not laid out).
    @MainActor
    func topVisibleCharacterIndex() -> Int {
        guard let lm = layoutManager, let tc = textContainer else { return 0 }
        let visible = enclosingScrollView?.contentView.bounds ?? bounds
        // The container is offset by textContainerInset; the layout manager
        // works in container coordinates.
        let containerRect = NSRect(
            x: 0,
            y: max(0, visible.origin.y - textContainerInset.height),
            width: visible.width,
            height: max(1, visible.height)
        )
        let glyphRange = lm.glyphRange(forBoundingRect: containerRect, in: tc)
        guard glyphRange.length > 0 else { return 0 }
        return lm.characterIndexForGlyph(at: glyphRange.location)
    }

    /// Scroll so the given character offset sits at the top of the visible
    /// rect. No-op if we're already close. When `animated: true`, tweens over
    /// ~100 ms with ease-out — used by the follower pane in split view so the
    /// driven scroll doesn't snap.
    @MainActor
    func scrollCharacterToTop(_ characterIndex: Int, animated: Bool = false) {
        guard let lm = layoutManager, let tc = textContainer,
              let clip = enclosingScrollView?.contentView else { return }
        let charIdx = max(0, min(characterIndex, (string as NSString).length))
        // Force layout up to the target so boundingRect returns something real.
        lm.ensureLayout(forCharacterRange: NSRange(location: 0, length: charIdx + 1))
        let glyphRange = lm.glyphRange(
            forCharacterRange: NSRange(location: charIdx, length: 0),
            actualCharacterRange: nil
        )
        let rect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
        let y = rect.origin.y + textContainerInset.height
        if abs(clip.bounds.origin.y - y) < 0.5 { return }
        let target = NSPoint(x: clip.bounds.origin.x, y: y)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.10
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                ctx.allowsImplicitAnimation = true
                clip.animator().setBoundsOrigin(target)
                enclosingScrollView?.reflectScrolledClipView(clip)
            }
        } else {
            clip.scroll(to: target)
            enclosingScrollView?.reflectScrolledClipView(clip)
        }
    }
}

extension String {
    /// 1-indexed line number for a UTF-16 offset, matching NSString semantics.
    /// Returns 1 for offset ≤ 0.
    func lineNumber(forUTF16Offset offset: Int) -> Int {
        let ns = self as NSString
        let bounded = max(0, min(offset, ns.length))
        var line = 1
        var i = 0
        while i < bounded {
            if ns.character(at: i) == 0x0A { line += 1 }
            i += 1
        }
        return line
    }

    /// UTF-16 offset of the first character on the given 1-indexed source line.
    /// Returns 0 for line ≤ 1; length if the line is past the end.
    func utf16Offset(forLineNumber line: Int) -> Int {
        guard line > 1 else { return 0 }
        let ns = self as NSString
        var current = 1
        var i = 0
        while i < ns.length && current < line {
            if ns.character(at: i) == 0x0A { current += 1 }
            i += 1
        }
        return i
    }
}

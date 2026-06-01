import SwiftUI
import AppKit

struct PrintRequest {
    let text: String
    let baseURL: URL?
}

private struct PrintRequestKey: FocusedValueKey {
    typealias Value = PrintRequest
}

extension FocusedValues {
    var printRequest: PrintRequest? {
        get { self[PrintRequestKey.self] }
        set { self[PrintRequestKey.self] = newValue }
    }
}

@MainActor
enum PreviewPrinter {
    /// Render the markdown into an NSTextView and hand it to NSPrintOperation.
    /// AppKit paginates the text view across pages natively.
    static func run(_ request: PrintRequest) {
        let printInfo = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo.shared
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic

        let contentWidth = printInfo.paperSize.width
            - printInfo.leftMargin
            - printInfo.rightMargin

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: 1))
        textView.isEditable = false
        textView.isSelectable = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.size = NSSize(width: contentWidth, height: .greatestFiniteMagnitude)

        let attr = NSAttributedMarkdown.render(request.text, baseURL: request.baseURL)
        textView.textStorage?.setAttributedString(attr)
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let usedHeight = textView.layoutManager?
            .usedRect(for: textView.textContainer!).height ?? contentWidth
        textView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: max(usedHeight, 1))

        let op = NSPrintOperation(view: textView, printInfo: printInfo)
        op.jobTitle = request.baseURL?.deletingPathExtension().lastPathComponent
            ?? "markyttdown"
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        op.run()
    }
}

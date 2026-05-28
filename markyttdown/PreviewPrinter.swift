import SwiftUI
import AppKit
import PDFKit

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
    static func run(_ request: PrintRequest) {
        let printInfo = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo.shared
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36

        let pageSize = printInfo.paperSize
        let contentWidth = pageSize.width - printInfo.leftMargin - printInfo.rightMargin
        let contentHeight = pageSize.height - printInfo.topMargin - printInfo.bottomMargin

        let view = PreviewContent(text: request.text, baseURL: request.baseURL)
            .frame(width: contentWidth, alignment: .leading)

        // Force a layout pass via an offscreen NSHostingView so we know total
        // content height before pagination. SwiftUI ImageRenderer alone won't
        // give us this measurement.
        let probe = NSHostingView(rootView: view)
        probe.translatesAutoresizingMaskIntoConstraints = true
        probe.frame = NSRect(x: 0, y: 0, width: contentWidth, height: 1)
        probe.layoutSubtreeIfNeeded()
        let totalHeight = max(probe.fittingSize.height, contentHeight)

        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: contentWidth, height: totalHeight)

        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else { return }
        var mediaBox = CGRect(x: 0, y: 0, width: pageSize.width, height: pageSize.height)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return }

        let pages = max(1, Int(ceil(totalHeight / contentHeight)))
        for i in 0..<pages {
            ctx.beginPDFPage(nil)
            ctx.saveGState()

            // ImageRenderer already produces output in CG's y-up frame (source
            // top → high y, source bottom → low y). Stay in that frame:
            //   - clip to the content area in page CG coords
            //   - translate so source-y = i*contentHeight lands at the top of
            //     the content area
            ctx.clip(to: CGRect(
                x: printInfo.leftMargin,
                y: printInfo.bottomMargin,
                width: contentWidth,
                height: contentHeight
            ))
            let dy = (printInfo.bottomMargin + contentHeight)
                - (totalHeight - CGFloat(i) * contentHeight)
            ctx.translateBy(x: printInfo.leftMargin, y: dy)

            renderer.render { _, render in render(ctx) }

            ctx.restoreGState()
            ctx.endPDFPage()
        }
        ctx.closePDF()

        guard let doc = PDFDocument(data: pdfData as Data),
              let op = doc.printOperation(for: printInfo,
                                          scalingMode: .pageScaleNone,
                                          autoRotate: false)
        else { return }
        op.jobTitle = request.baseURL?.deletingPathExtension().lastPathComponent ?? "markyttdown"
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        op.run()
    }
}

import SwiftUI
import UniformTypeIdentifiers

@main
struct MarkyttdownApp: App {
    init() {
        // Skip the launch-time GitHub poll under XCTest hosts and UI tests so
        // the test runner can start cleanly and runs stay hermetic.
        let isUnitTest = NSClassFromString("XCTestCase") != nil
        let isUITest = ProcessInfo.processInfo.environment["MARKYTTDOWN_UI_TEST"] == "1"
        guard !isUnitTest && !isUITest else { return }
        Task { @MainActor in
            await UpdateChecker.shared.checkSilentlyIfDue()
        }
    }

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document, baseURL: file.fileURL)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { @MainActor in
                        await UpdateChecker.shared.checkManually()
                    }
                }
            }
            CommandGroup(replacing: .printItem) {
                PrintCommands()
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                FindCommands()
            }
            CommandGroup(after: .toolbar) {
                LayoutCommands()
                Divider()
                ZoomCommands()
            }
        }
    }
}

private struct ZoomCommands: View {
    @FocusedValue(\.zoom) private var zoom: Zoom?

    var body: some View {
        Button("Zoom In")     { zoom?.zoomIn() }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(zoom == nil)
        Button("Zoom Out")    { zoom?.zoomOut() }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(zoom == nil)
        Button("Actual Size") { zoom?.actualSize() }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(zoom == nil)
    }
}

private struct FindCommands: View {
    var body: some View {
        Button("Find…") { fire(.showFindInterface) }
            .keyboardShortcut("f", modifiers: .command)
        Button("Find & Replace…") { fire(.showReplaceInterface) }
            .keyboardShortcut("f", modifiers: [.command, .option])
        Button("Find Next") { fire(.nextMatch) }
            .keyboardShortcut("g", modifiers: .command)
        Button("Find Previous") { fire(.previousMatch) }
            .keyboardShortcut("g", modifiers: [.command, .shift])
        Button("Use Selection for Find") { fire(.setSearchString) }
            .keyboardShortcut("e", modifiers: .command)
    }

    private func fire(_ action: NSTextFinder.Action) {
        let item = NSMenuItem()
        item.tag = action.rawValue
        NSApp.sendAction(
            #selector(NSResponder.performTextFinderAction(_:)),
            to: nil,
            from: item
        )
    }
}

private struct PrintCommands: View {
    @FocusedValue(\.printRequest) private var request: PrintRequest?

    var body: some View {
        Button("Print…") {
            if let request { PreviewPrinter.run(request) }
        }
        .keyboardShortcut("p", modifiers: .command)
        .disabled(request == nil)
    }
}

private struct LayoutCommands: View {
    @AppStorage("layoutMode") private var layoutMode: LayoutMode = .toggle
    @AppStorage("editorPane") private var editorPane: EditorPane = .editor

    var body: some View {
        Picker("Layout", selection: $layoutMode) {
            Text("Toggle Edit / Preview").tag(LayoutMode.toggle)
            Text("Side-by-side").tag(LayoutMode.split)
        }
        Divider()
        Button("Editor") { editorPane = .editor }
            .keyboardShortcut("1", modifiers: .command)
        Button("Preview") { editorPane = .preview }
            .keyboardShortcut("2", modifiers: .command)
    }
}

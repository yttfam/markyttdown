import SwiftUI
import UniformTypeIdentifiers

@main
struct MarkyttdownApp: App {
    init() {
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
            CommandGroup(after: .toolbar) {
                LayoutCommands()
            }
        }
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

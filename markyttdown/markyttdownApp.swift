import SwiftUI
import UniformTypeIdentifiers

@main
struct MarkyttdownApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document)
        }
        .commands {
            CommandGroup(after: .toolbar) {
                LayoutCommands()
            }
        }
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

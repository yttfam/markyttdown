import SwiftUI

enum LayoutMode: String, CaseIterable, Identifiable {
    case toggle, split
    var id: String { rawValue }
}

enum EditorPane: String, CaseIterable, Identifiable {
    case editor, preview
    var id: String { rawValue }
}

struct ContentView: View {
    @Binding var document: MarkdownDocument
    @AppStorage("layoutMode") private var layoutMode: LayoutMode = .toggle
    @AppStorage("editorPane") private var editorPane: EditorPane = .editor
    @StateObject private var sync = ScrollSync()

    var body: some View {
        Group {
            switch layoutMode {
            case .toggle:
                switch editorPane {
                case .editor:  EditorView(text: $document.text, sync: sync)
                case .preview: PreviewView(text: document.text, sync: sync)
                }
            case .split:
                HSplitView {
                    EditorView(text: $document.text, sync: sync)
                        .frame(minWidth: 240)
                    PreviewView(text: document.text, sync: sync)
                        .frame(minWidth: 240)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .toolbar { toolbarContent }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("", selection: $layoutMode) {
                Image(systemName: "rectangle").tag(LayoutMode.toggle)
                Image(systemName: "rectangle.split.2x1").tag(LayoutMode.split)
            }
            .pickerStyle(.segmented)
            .help("Layout: toggle or side-by-side")
        }
        if layoutMode == .toggle {
            ToolbarItem {
                Picker("", selection: $editorPane) {
                    Image(systemName: "square.and.pencil").tag(EditorPane.editor)
                    Image(systemName: "eye").tag(EditorPane.preview)
                }
                .pickerStyle(.segmented)
                .help("Edit or Preview")
            }
        }
    }
}

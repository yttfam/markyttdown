# Contributing to markyttdown

Thanks for your interest. markyttdown is deliberately tiny — the bar for adding
code is "does it pull its weight?". Small, focused PRs land easily.

## Requirements

- macOS 14+ on Apple Silicon (Intel may work but isn't tested)
- Xcode 16+ with the macOS SDK
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Ruby (for fastlane); `bundle install` from the repo root

## Getting started

```sh
git clone https://github.com/yttfam/markyttdown
cd markyttdown
brew install xcodegen
bundle install
xcodegen generate
open markyttdown.xcodeproj
```

Run via Xcode (⌘R) or:

```sh
bundle exec fastlane mac test     # build + tests
```

The generated `markyttdown.xcodeproj` is git-ignored — `project.yml` is the
source of truth. Re-run `xcodegen generate` whenever you change `project.yml`,
add/remove source files, or pull changes that touch the project structure.

## Project layout

```
markyttdown/
├── project.yml                # xcodegen spec
├── markyttdown/               # app sources
│   ├── markyttdownApp.swift   # @main, DocumentGroup, top-level commands
│   ├── MarkdownDocument.swift # FileDocument (UTF-8 string)
│   ├── ContentView.swift      # layout switch (toggle vs split)
│   ├── EditorView.swift       # NSTextView in NSScrollView, scroll-synced
│   ├── PreviewView.swift      # SwiftUI ScrollView + Markdown renderer
│   ├── PreviewPrinter.swift   # ⌘P → ImageRenderer → PDF → PDFKit print
│   ├── ScrollSync.swift       # editor ↔ preview proportional scroll bridge
│   └── UpdateChecker.swift    # GH Releases poll + manual menu item
├── markyttdownTests/          # XCTest unit tests
├── fastlane/                  # test / bump_build / bump_marketing / release
├── scripts/                   # notarize.sh, make_dmg.sh, make_pkg.sh, ...
└── .github/workflows/         # ci.yaml (PR+main), release.yaml (on v* tag)
```

## Style

- Swift 6 strict concurrency. Mark UI types `@MainActor` when they touch
  AppKit/SwiftUI views.
- Prefer plain Swift (`struct`, `enum`, `func`) over framework wrappers when
  framework wrappers don't add anything.
- Default to no comments. Only explain *why* when the why isn't obvious from
  the code.
- No external dependencies unless they remove real complexity. The current
  dep set is one Swift Package: `swift-markdown`.

## Tests

Add XCTest cases under `markyttdownTests/` for any logic worth pinning down
(renderer behaviour, version comparison, etc.). UI code is generally not
unit-tested — verify changes locally and via the release `.dmg`.

```sh
xcodebuild -project markyttdown.xcodeproj -scheme markyttdown \
  -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
```

## PR checklist

Before opening a PR:

- [ ] `xcodegen generate` succeeds
- [ ] `bundle exec fastlane mac test` is green (or the equivalent
      `xcodebuild test` invocation above)
- [ ] No new compiler warnings
- [ ] If you touched the renderer, the app still opens a non-trivial
      `.md` file and shows what you'd expect in both layout modes
- [ ] If you added a user-visible feature, mention it in the PR
      description so it can land in the next release's notes

## Reporting bugs

Open an issue with:

- macOS version (`sw_vers`)
- markyttdown version (visible in the *About* panel)
- A minimal `.md` reproducing the problem, if applicable
- What you expected vs. what happened

## License

By contributing, you agree your contributions are licensed under the
[MIT License](LICENSE) used by this repo.

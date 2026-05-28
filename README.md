# markyttdown

A tiny native macOS markdown editor. The YTT family's writer.

Open a `.md`, edit, preview, save, save-a-copy. That's the brief.

[![Latest Release](https://img.shields.io/github/v/release/yttfam/markyttdown)](https://github.com/yttfam/markyttdown/releases/latest)
[![CI](https://github.com/yttfam/markyttdown/actions/workflows/ci.yaml/badge.svg)](https://github.com/yttfam/markyttdown/actions/workflows/ci.yaml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Features

- **Native SwiftUI** on macOS 14+, Apple Silicon
- **Edit / Preview / Side-by-side** layout, switchable per-window (⌘1 / ⌘2)
- **Proportional scroll sync** between editor and preview in split mode
- **Inline images** in the preview — remote (`https://`) via `AsyncImage`,
  local paths (`./images/foo.png`) resolved against the document directory
- **Print** the rendered preview (⌘P), not the raw source — multi-page PDF via
  PDFKit
- **Auto-update** check against GitHub Releases on launch (24h throttled) and
  a manual *Check for Updates…* menu item
- Standard `NSDocument` plumbing — Open, Save, Save As, Duplicate, Recents
- Developer ID signed + notarized + stapled

## Install

Grab the latest `.dmg` or `.pkg` from
[the releases page](https://github.com/yttfam/markyttdown/releases/latest).

Both artefacts are signed with Apple Developer ID, notarized by Apple, and
stapled — no Gatekeeper warnings, no `xattr -d` dance.

## Build from source

```sh
brew install xcodegen
bundle install
xcodegen generate
open markyttdown.xcodeproj
```

Or, via fastlane:

```sh
bundle exec fastlane mac test     # build + run unit tests
```

## Version policy

- `MARKETING_VERSION` — bumped on demand by the maintainer
  (`bundle exec fastlane mac bump_marketing component:major|minor|patch`)
- `CURRENT_PROJECT_VERSION` (build) — auto-bumped per release commit; source
  of truth is the highest build number across published GitHub Releases for
  this repo, +1

## Releasing

Releases run on `macos-latest` via GitHub Actions. Secrets are mirrored from
Vault by `./scripts/sync-vault-to-gh-secrets.sh`.

To cut a release, bump the marketing version, commit, and push a tag:

```sh
bundle exec fastlane mac bump_marketing component:minor
git commit -am "chore: 0.3.0"
git tag v0.3.0
git push --follow-tags
```

CI then builds, signs (Developer ID Application), notarizes, staples,
wraps in `.dmg` and `.pkg`, and attaches both artefacts to a GitHub Release.

## Family

markyttdown is part of the [YTT family](https://github.com/yttfam) of small,
focused tools. Siblings include
[grytti](https://github.com/yttfam/grytti) (PTY parser / Telegram bridge),
[kytti](https://github.com/yttfam/kytti) (Vault MCP gateway),
[fytti](https://github.com/yttfam/fytti) (GPU runtime),
[wytti](https://github.com/yttfam/wytti) (WASI runtime), and more.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE) © 2026 Nico Bousquet

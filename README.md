# KonuqEditorKit

The block-based rich text editor that powers [Konuq](https://apps.apple.com/app/konuq) on iOS. UIKit under the hood, with a SwiftUI shell for embedding.

## Features

- Block model: paragraphs, headings, checkboxes, bullet and numbered lists, quotes, code, media, and location blocks
- Inline markdown shortcuts (`**bold**`, `*italic*`, `` `code` ``, `~~strike~~`)
- Media blocks with pluggable reference resolution
- Theming and custom fonts (DM Sans, Space Grotesk)
- Localized in 13 languages

## Requirements

- iOS 17+
- Swift 5.10

## Installation

Add the package in Xcode (File → Add Package Dependencies) or in `Package.swift`:

```swift
.package(url: "https://github.com/deruloop/KonuqEditorKit.git", from: "1.0.0")
```

## License

MIT. See [LICENSE](LICENSE).

The bundled DM Sans and Space Grotesk fonts are licensed under the SIL Open Font License 1.1. See [FONT_LICENSES.md](FONT_LICENSES.md).

import Foundation

/// Pasteboard identifiers used for lossless in-app block copy/paste. External apps
/// get either the formatted forms (RTF, HTML, plain string) or, with "copy as
/// markdown", the markdown source as plain text.
enum EditorClipboard {
	static let blocksType = "com.konuq.editor.blocks.v1"
	static let plainText = "public.utf8-plain-text"
	static let rtf = "public.rtf"
	static let html = "public.html"
}

/// What the text forms on the pasteboard look like to other apps.
public enum EditorCopyFormat {
	/// RTF + HTML + a plain string without markup. Bold stays bold, headings stay
	/// headings in apps that read rich text. The default.
	case formatted
	/// The markdown source as plain text (`# Title`, `**bold**`, `- [ ] task`).
	case markdown
}

public enum TextStyle: String, Equatable, Codable {
	case text
	case title
	case description
	case heading3
	case heading4
	case heading5
	case heading6
	case code
	case toggle
	case toggleHeader
	case listBullet
	case checkbox
}

enum MediaBlockKind: String, Equatable {
	case image
	case video
}

public enum MediaBlockDisplayStyle: String, Equatable, Codable {
	case small
	case medium
	case large
}


struct TextBlock: Equatable {
	var text: NSAttributedString
	var style: TextStyle
}

/// One photo of a media block: its file and the caption written under it. The caption
/// is markdown, rendered italic and muted wherever the note is shown.
struct MediaItem: Equatable {
	var id: String
	var reference: String
	var caption: String
}

/// An image block holds one or more photos shown as a carousel; a video block holds
/// one video. The first item carries the block's own id, so a single image persists
/// exactly as before; further photos keep their own ids and become the following
/// image rows when the note is saved.
struct MediaBlock: Equatable {
	var kind: MediaBlockKind
	var items: [MediaItem]
	var displayStyle: MediaBlockDisplayStyle

	init(kind: MediaBlockKind, items: [MediaItem], displayStyle: MediaBlockDisplayStyle) {
		self.kind = kind
		self.items = items
		self.displayStyle = displayStyle
	}

	/// A block with a single item, the shape every existing call site builds.
	init(kind: MediaBlockKind, reference: String, displayStyle: MediaBlockDisplayStyle, caption: String = "", itemId: String = UUID().uuidString) {
		self.kind = kind
		self.items = [MediaItem(id: itemId, reference: reference, caption: caption)]
		self.displayStyle = displayStyle
	}

	/// The first photo's file: what the block "is" for code that handles one media.
	var reference: String { items.first?.reference ?? "" }
	var isGallery: Bool { kind == .image && items.count > 1 }
}

enum BlockContent: Equatable {
	case text(TextBlock)
	case media(MediaBlock)
}

struct Block: Identifiable, Equatable {
	let id: String
	var content: BlockContent
	var parentId: String?
	var children: [String]

	init(
		id: String = UUID().uuidString,
		content: BlockContent = .text(TextBlock(text: NSAttributedString(string: ""), style: .text)),
		parentId: String? = nil,
		children: [String] = []
	) {
		self.id = id
		self.content = content
		self.parentId = parentId
		self.children = children
	}
}

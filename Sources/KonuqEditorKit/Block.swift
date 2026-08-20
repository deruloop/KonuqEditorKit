import Foundation

/// Pasteboard identifiers used for lossless in-app block copy/paste. The plain-text
/// (markdown) representation is written alongside for external apps.
enum EditorClipboard {
	static let blocksType = "com.konuq.editor.blocks.v1"
	static let plainText = "public.utf8-plain-text"
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

struct MediaBlock: Equatable {
	var kind: MediaBlockKind
	var reference: String
	var displayStyle: MediaBlockDisplayStyle
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

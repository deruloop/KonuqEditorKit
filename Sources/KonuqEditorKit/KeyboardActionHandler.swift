import Foundation

final class KeyboardActionHandler {
    private let document: Document
    private let service: BlockActionService
    private let toggleStorage: ToggleStorage
    
    init(document: Document, service: BlockActionService, toggleStorage: ToggleStorage) {
        self.document = document
        self.service = service
        self.toggleStorage = toggleStorage
    }
    
    func handle(blockId: String, action: KeyboardAction) -> String? {
        guard let info = document.block(id: blockId) else { return nil }
        
        switch action {
        case let .markdownTurnInto(style, text):
			guard case .text = info.content else { return nil }
			var updated = info
			updated.content = .text(TextBlock(text: text, style: style))
			document.setBlock(updated)
			return info.id

		case let .insertNewBlockWithText(text):
			let normalized = text
				.replacingOccurrences(of: "\r\n", with: "\n")
				.replacingOccurrences(of: "\r", with: "\n")
			let parts = normalized
				.split(separator: "\n", omittingEmptySubsequences: true)
				.map(String.init)
			let first = parts.first ?? normalized

			let firstBlock = Block(content: .text(TextBlock(text: NSAttributedString(string: first), style: .text)))
			var previousId = service.add(block: firstBlock, targetBlockId: info.id, position: .bottom)

			if parts.count > 1 {
				for idx in 1..<parts.count {
					let block = Block(content: .text(TextBlock(text: NSAttributedString(string: parts[idx]), style: .text)))
					previousId = service.add(block: block, targetBlockId: previousId, position: .bottom)
				}
			}
			return previousId

		case .insertDivider:
			let dividerText = NSAttributedString(string: "----")
			let dividerBlock = Block(content: .text(TextBlock(text: dividerText, style: .text)))
			let newTextBlock = Block(content: .text(TextBlock(text: NSAttributedString(string: ""), style: .text)))

			if case .text(let textBlock) = info.content {
				let trimmed = textBlock.text.string.trimmingCharacters(in: .whitespacesAndNewlines)
				if textBlock.style == .text, trimmed.isEmpty || trimmed == "---" || trimmed == "----" {
					var updated = info
					updated.content = dividerBlock.content
					document.setBlock(updated)
					let newId = service.add(block: newTextBlock, targetBlockId: info.id, position: .bottom)
					return newId
				}
			}

			let dividerId = service.add(block: dividerBlock, targetBlockId: info.id, position: .bottom)
			let newId = service.add(block: newTextBlock, targetBlockId: dividerId, position: .bottom)
			return newId
            
        case .enterForEmpty:
			guard case .text(let textBlock) = info.content else {
				let newBlock = Block(content: .text(TextBlock(text: NSAttributedString(string: ""), style: .text)))
				_ = service.add(block: newBlock, targetBlockId: info.id, position: .bottom)
				return newBlock.id
			}

			if isList(style: textBlock.style) {
				var updated = info
				updated.content = .text(TextBlock(text: textBlock.text, style: .text))
				document.setBlock(updated)
				return nil
			}
			
			if textBlock.style == .code {
				var updated = info
				updated.content = .text(TextBlock(text: textBlock.text, style: .text))
				document.setBlock(updated)
				return nil
			}
			
			return service.split(
				blockId: info.id,
				range: NSRange(location: 0, length: 0),
				newBlockStyle: .text,
				mode: .bottom
			)
            
        case let .enterInside(_, range):
			guard case .text(let textBlock) = info.content else { return nil }
			let newStyle = contentTypeForSplit(style: textBlock.style, blockId: info.id)
			return service.split(
				blockId: info.id,
				range: range,
				newBlockStyle: newStyle,
				mode: .bottom
			)
            
        case let .enterAtTheEnd(string, range):
            if string.string.isEmpty {
                return handle(blockId: info.id, action: .enterForEmpty)
            }

			guard case .text(let textBlock) = info.content else { return nil }
			
			let isToggle = textBlock.style == .toggle || isToggleHeader(style: textBlock.style)
			let _ = isToggle
			
			let type = isList(style: textBlock.style) ? textBlock.style : .text
			return service.split(
				blockId: info.id,
				range: range,
				newBlockStyle: type,
				mode: .bottom
			)
            
        case .enterAtTheBegining:
            let newBlock = Block(content: .text(TextBlock(text: NSAttributedString(string: ""), style: .text)))
            _ = service.add(block: newBlock, targetBlockId: info.id, position: .top)
            return newBlock.id
            
        case .delete:
			guard case .text(let currentTextBlock) = info.content else { return nil }
			if currentTextBlock.style == .text,
			   (currentTextBlock.text.string.trimmingCharacters(in: .whitespacesAndNewlines) == "---"
				|| currentTextBlock.text.string.trimmingCharacters(in: .whitespacesAndNewlines) == "----") {
				let index = document.index(of: info.id)
				document.remove(blockId: info.id)
				if let index, index > 0 {
					return document.order[index - 1]
				}
				return document.order.first
			}
			guard let index = document.index(of: info.id), index > 0 else { return nil }
            let previousId = document.order[index - 1]
            guard var previous = document.block(id: previousId) else { return nil }

			if case .text(let previousTextBlock) = previous.content,
			   currentTextBlock.text.length == 0,
			   previousTextBlock.style == .text,
			   (previousTextBlock.text.string.trimmingCharacters(in: .whitespacesAndNewlines) == "---"
				|| previousTextBlock.text.string.trimmingCharacters(in: .whitespacesAndNewlines) == "----") {
				document.remove(blockId: info.id)
				return previousId
			}

			if case .media = previous.content, currentTextBlock.text.length == 0 {
				document.remove(blockId: previousId)
				return info.id
			}

			guard case .text(let previousTextBlock) = previous.content else { return nil }
			
			if currentTextBlock.text.length == 0 {
				document.remove(blockId: info.id)
				return previousId
			}
			
			let merged = NSMutableAttributedString(attributedString: previousTextBlock.text)
			merged.append(currentTextBlock.text)
			previous.content = .text(TextBlock(text: merged, style: previousTextBlock.style))
			document.setBlock(previous)
			document.remove(blockId: info.id)
			return previousId

		case .pickMedia:
			return nil

		case .presentLinkToNoteSheet:
			return nil

		case let .pasteMultiline(text, range):
			guard case .text(let textBlock) = info.content else { return nil }

			let normalized = text
				.replacingOccurrences(of: "\r\n", with: "\n")
				.replacingOccurrences(of: "\r", with: "\n")
			let parts = normalized
				.split(separator: "\n", omittingEmptySubsequences: true)
				.map(String.init)
			guard !parts.isEmpty else { return nil }

			let total = textBlock.text.length
			let start = max(0, min(range.location, total))
			let end = max(start, min(range.location + range.length, total))

			let before = textBlock.text.attributedSubstring(from: NSRange(location: 0, length: start))
			let after = textBlock.text.attributedSubstring(from: NSRange(location: end, length: total - end))

			let newStyle = contentTypeForSplit(style: textBlock.style, blockId: info.id)

			if parts.count == 1 {
				let updated = NSMutableAttributedString(attributedString: before)
				updated.append(NSAttributedString(string: parts[0]))
				updated.append(after)
				var current = info
				current.content = .text(TextBlock(text: updated, style: textBlock.style))
				document.setBlock(current)
				return info.id
			}

			let updatedCurrent = NSMutableAttributedString(attributedString: before)
			updatedCurrent.append(NSAttributedString(string: parts[0]))

			var current = info
			current.content = .text(TextBlock(text: updatedCurrent, style: textBlock.style))
			document.setBlock(current)

			var previousId = info.id
			for idx in 1..<parts.count {
				let piece = NSMutableAttributedString(string: parts[idx])
				if idx == parts.count - 1 {
					piece.append(after)
				}
				let block = Block(content: .text(TextBlock(text: piece, style: newStyle)))
				let newId = service.add(block: block, targetBlockId: previousId, position: .bottom)
				previousId = newId
			}
			return previousId
        }
    }
    
    private func isList(style: TextStyle) -> Bool {
        style == .listBullet || style == .checkbox
    }
    
    private func isToggleHeader(style: TextStyle) -> Bool {
        style == .toggleHeader
    }
    
    private func contentTypeForSplit(style: TextStyle, blockId: String) -> TextStyle {
        switch style {
        case .title, .description, .heading3, .heading4, .heading5, .heading6:
            return .text
        case .code:
            return .code
        case .toggle, .toggleHeader:
            return toggleStorage.isToggled(blockId: blockId) ? .text : style
        default:
            return style
        }
    }
    
    private func splitMode(info: Block) -> SplitMode { .bottom }
}

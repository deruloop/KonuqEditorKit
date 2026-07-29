import Foundation

enum InsertPosition {
    case top
    case bottom
    case inner
}

enum SplitMode {
    case bottom
    case inner
}

final class BlockActionService {
    private let document: Document
    
    init(document: Document) {
        self.document = document
    }
    
    @discardableResult
    func add(block: Block, targetBlockId: String, position: InsertPosition) -> String {
        switch position {
        case .top:
            guard let idx = document.order.firstIndex(of: targetBlockId) else {
                return document.insert(block, after: nil)
            }
            return document.insert(block, at: idx)
        case .bottom:
            return document.insert(block, after: targetBlockId)
        case .inner:
            return document.insert(block, after: targetBlockId)
        }
    }
    
    func setText(blockId: String, text: NSAttributedString) {
        document.updateText(blockId: blockId, text: text)
    }
    
    @discardableResult
    func split(
        blockId: String,
        range: NSRange,
        newBlockStyle: TextStyle,
        mode: SplitMode
    ) -> String? {
        guard var current = document.block(id: blockId) else { return nil }
		guard case .text(let textBlock) = current.content else { return nil }

		let total = textBlock.text.length
        let splitAt = max(0, min(range.location, total))

        let leftRange = NSRange(location: 0, length: splitAt)
        let rightRange = NSRange(location: splitAt, length: total - splitAt)

		let left = textBlock.text.attributedSubstring(from: leftRange)
		let right = textBlock.text.attributedSubstring(from: rightRange)

		current.content = .text(TextBlock(text: left, style: textBlock.style))
        document.setBlock(current)

        let newId = UUID().uuidString
		let normalizedRight: NSAttributedString = {
			guard newBlockStyle == .checkbox else { return right }
			let ns = right.string as NSString
			if ns.length >= 4 {
				let prefix = ns.substring(with: NSRange(location: 0, length: 4)).lowercased()
				if prefix == "[ ] " || prefix == "[x] " { return right }
			}
			let updated = NSMutableAttributedString(string: "[ ] ")
			updated.append(right)
			return updated
		}()

		let newBlock = Block(
			id: newId,
			content: .text(TextBlock(text: normalizedRight, style: newBlockStyle))
		)

        _ = document.insert(newBlock, after: current.id)

        return newId
    }
    
    func merge(firstBlockId: String, secondBlockId: String) {
        guard let first = document.block(id: firstBlockId), let second = document.block(id: secondBlockId) else { return }
		guard case .text(let firstText) = first.content else { return }
		guard case .text(let secondText) = second.content else { return }
		let merged = NSMutableAttributedString(attributedString: firstText.text)
		if firstText.text.length > 0 && secondText.text.length > 0 {
			merged.append(NSAttributedString(string: " "))
		}
		merged.append(secondText.text)
		document.updateText(blockId: firstBlockId, text: merged)
		document.remove(blockId: secondBlockId)
    }
}

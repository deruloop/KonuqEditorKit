import Foundation

final class Document {
    private(set) var blocks: [String: Block] = [:]
    private(set) var order: [String] = []
    
    func block(id: String) -> Block? {
        blocks[id]
    }
    
    func setBlock(_ block: Block) {
        blocks[block.id] = block
        if !order.contains(block.id) {
            order.append(block.id)
        }
    }
    
    @discardableResult
    func insert(_ block: Block, at index: Int) -> String {
        blocks[block.id] = block
        let clamped = max(0, min(index, order.count))
        order.insert(block.id, at: clamped)
        return block.id
    }
    
    @discardableResult
    func insert(_ block: Block, after targetId: String?) -> String {
        blocks[block.id] = block
        guard let targetId, let idx = order.firstIndex(of: targetId) else {
            order.append(block.id)
            return block.id
        }
        order.insert(block.id, at: idx + 1)
        return block.id
    }
    
    func updateText(blockId: String, text: NSAttributedString) {
        guard var block = blocks[blockId] else { return }
		guard case .text(var textBlock) = block.content else { return }
		textBlock.text = text
		block.content = .text(textBlock)
        blocks[blockId] = block
    }
    
    func remove(blockId: String) {
        blocks.removeValue(forKey: blockId)
        if let idx = order.firstIndex(of: blockId) {
            order.remove(at: idx)
        }
    }
    
    func remove(blockIds: [String]) {
        for id in blockIds {
            blocks.removeValue(forKey: id)
        }
        order.removeAll { blockIds.contains($0) }
    }
    
    func index(of blockId: String) -> Int? {
        order.firstIndex(of: blockId)
    }
    
    func move(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < order.count else { return }
        let item = order.remove(at: sourceIndex)
        let dest = max(0, min(destinationIndex, order.count))
        order.insert(item, at: dest)
    }
    
    func move(blockId: String, to destinationIndex: Int) {
        guard let sourceIndex = index(of: blockId) else { return }
        move(from: sourceIndex, to: destinationIndex)
    }
    
    func swap(_ firstId: String, _ secondId: String) {
        guard let i1 = index(of: firstId), let i2 = index(of: secondId) else { return }
        order.swapAt(i1, i2)
    }

    func replaceAll(blocks newBlocks: [Block], order newOrder: [String]) {
        blocks = Dictionary(uniqueKeysWithValues: newBlocks.map { ($0.id, $0) })
        order = newOrder
    }
}

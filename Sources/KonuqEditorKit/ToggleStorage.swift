import Foundation

final class ToggleStorage {
    private var toggled: Set<String> = []
    
    func toggle(blockId: String) {
        if toggled.contains(blockId) {
            toggled.remove(blockId)
        } else {
            toggled.insert(blockId)
        }
    }
    
    func isToggled(blockId: String) -> Bool {
        toggled.contains(blockId)
    }
}


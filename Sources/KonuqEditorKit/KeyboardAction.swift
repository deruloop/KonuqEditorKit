import Foundation

enum KeyboardAction: Equatable {
    case enterForEmpty
    case enterInside(string: NSAttributedString, range: NSRange)
    case enterAtTheEnd(string: NSAttributedString, range: NSRange)
    case enterAtTheBegining
    case delete
    case markdownTurnInto(style: TextStyle, text: NSAttributedString)
	case pickMedia
	case pasteMultiline(text: String, range: NSRange)
	case insertDivider
	case insertNewBlockWithText(text: String)
	case presentLinkToNoteSheet
    
    static func build(attributedText: NSAttributedString, range: NSRange, replacement: String) -> Self? {
        let text = attributedText.string
        guard let textRange = Range(range, in: text) else { return nil }
        
        if replacement == " " {
            let replacedText = (text as NSString).replacingCharacters(in: range, with: replacement)
            let caretOffset = range.location + (replacement as NSString).length

			let dividerShortcuts = ["--- ", "---- "]
			for dividerShortcut in dividerShortcuts {
				if replacedText.hasPrefix(dividerShortcut), dividerShortcut.count >= caretOffset {
					return .insertDivider
				}
			}
            
            for item in BeginingMarkdownShortcut.all {
                for shortcutText in item.text {
                    if replacedText.hasPrefix(shortcutText), shortcutText.count >= caretOffset {
                        let replaced = NSMutableAttributedString(attributedString: attributedText)
                        replaced.replaceCharacters(in: range, with: replacement)
                        replaced.mutableString.deleteCharacters(in: NSMakeRange(0, min(shortcutText.count, replaced.string.count)))
						if item.style == .checkbox {
							let ns = replaced.string as NSString
							if ns.length < 4 || !(ns.hasPrefix("[ ] ") || ns.substring(with: NSRange(location: 0, length: 4)).lowercased() == "[x] ") {
								replaced.mutableString.insert("[ ] ", at: 0)
							}
						}
                        return .markdownTurnInto(style: item.style, text: replaced)
                    }
                }
            }
        }
        
        let emptyRange = textRange.isEmpty && textRange.lowerBound == text.startIndex
        
        if replacement == "\n" {
            if emptyRange && text.isEmpty {
                return .enterForEmpty
            }
            
            if text.endIndex == textRange.upperBound {
                return .enterAtTheEnd(string: attributedText, range: range)
            }
            
            if text.startIndex == textRange.lowerBound {
                return .enterAtTheBegining
            }
            
            return .enterInside(string: attributedText, range: range)
        }
        
        if replacement.isEmpty, emptyRange {
            return .delete
        }
        
        return nil
    }
}

private struct BeginingMarkdownShortcut {
    let text: [String]
    let style: TextStyle
}

private extension BeginingMarkdownShortcut {
    static let all: [BeginingMarkdownShortcut] = [
        .init(text: ["###> ", "##> ", "#> "], style: .toggleHeader),
        .init(text: ["###### "], style: .heading6),
        .init(text: ["##### "], style: .heading5),
        .init(text: ["#### "], style: .heading4),
        .init(text: ["### "], style: .heading3),
        .init(text: ["## "], style: .description),
        .init(text: ["# "], style: .title),
        .init(text: ["``` "], style: .code),
		.init(text: ["* "], style: .checkbox),
        .init(text: ["- "], style: .listBullet),
        .init(text: ["> "], style: .toggle)
    ]
}

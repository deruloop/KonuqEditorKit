import UIKit

private extension NSAttributedString.Key {
	static let appInlineBold = NSAttributedString.Key("app.inline.bold")
	static let appInlineItalic = NSAttributedString.Key("app.inline.italic")
	static let appInlineCode = NSAttributedString.Key("app.inline.code")
	static let appInlineStrike = NSAttributedString.Key("app.inline.strike")
	static let appInlineTagName = NSAttributedString.Key("app.inline.tag.name")
	static let appInlineTagFinal = NSAttributedString.Key("app.inline.tag.final")
	static let appInlineLinkUrl = NSAttributedString.Key("app.inline.link.url")
	static let appInlineLinkHidden = NSAttributedString.Key("app.inline.link.hidden")
	static let appInlineNoteLinkId = NSAttributedString.Key("app.inline.note.link.id")
	static let appInlineCheckboxHidden = NSAttributedString.Key("app.inline.checkbox.hidden")
	static let appInlineCheckboxDimmed = NSAttributedString.Key("app.inline.checkbox.dimmed")
	static let appInlineCheckboxAutoStrike = NSAttributedString.Key("app.inline.checkbox.auto.strike")
}

final class BlocksEditorTextView: UITextView {
	weak var ownerCell: BlockCell?

	override var keyCommands: [UIKeyCommand]? {
		var commands: [UIKeyCommand] = []

		let bold = UIKeyCommand(input: "b", modifierFlags: .command, action: #selector(handleCommandBold))
		bold.discoverabilityTitle = "Bold"
		if #available(iOS 15.0, *) { bold.wantsPriorityOverSystemBehavior = true }
		commands.append(bold)

		let italic = UIKeyCommand(input: "i", modifierFlags: .command, action: #selector(handleCommandItalic))
		italic.discoverabilityTitle = "Italic"
		if #available(iOS 15.0, *) { italic.wantsPriorityOverSystemBehavior = true }
		commands.append(italic)

		if isMacRuntime() {
			let textBlock = UIKeyCommand(input: "b", modifierFlags: [.command, .shift], action: #selector(handleCommandMakeTextBlock))
			textBlock.discoverabilityTitle = "Text block"
			commands.append(textBlock)

			let titleBlock = UIKeyCommand(input: "t", modifierFlags: [.command, .shift], action: #selector(handleCommandMakeTitleBlock))
			titleBlock.discoverabilityTitle = "Title block"
			commands.append(titleBlock)

			let headerBlock = UIKeyCommand(input: "h", modifierFlags: [.command, .shift], action: #selector(handleCommandMakeHeaderBlock))
			headerBlock.discoverabilityTitle = "Header block"
			commands.append(headerBlock)

			let paragraphBlock = UIKeyCommand(input: "j", modifierFlags: [.command, .shift], action: #selector(handleCommandMakeParagraphBlock))
			paragraphBlock.discoverabilityTitle = "Paragraph block"
			commands.append(paragraphBlock)

			let sel = selectedRange
			if sel.length == 0 {
				if sel.location == 0 {
					let up = UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(handleUpArrow))
					if #available(iOS 15.0, *) { up.wantsPriorityOverSystemBehavior = true }
					commands.append(up)
				}
				if sel.location == attributedText.length {
					let down = UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(handleDownArrow))
					if #available(iOS 15.0, *) { down.wantsPriorityOverSystemBehavior = true }
					commands.append(down)
				}
			}
		}

		return commands
	}

	@objc private func handleCommandBold() { ownerCell?.toggleBold() }
	@objc private func handleCommandItalic() { ownerCell?.toggleItalic() }
	@objc private func handleCommandMakeTextBlock() { ownerCell?.applyBlockStyleCommand(.text) }
	@objc private func handleCommandMakeTitleBlock() { ownerCell?.applyBlockStyleCommand(.title) }
	@objc private func handleCommandMakeHeaderBlock() { ownerCell?.applyBlockStyleCommand(.description) }
	@objc private func handleCommandMakeParagraphBlock() { ownerCell?.applyBlockStyleCommand(.heading3) }
	@objc private func handleUpArrow() { ownerCell?.requestMoveFocusUp() }
	@objc private func handleDownArrow() { ownerCell?.requestMoveFocusDown() }

	override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
		guard isMacRuntime() else {
			super.pressesBegan(presses, with: event)
			return
		}

		for press in presses {
			switch press.type {
			case .upArrow:
				let sel = selectedRange
				if sel.length == 0, sel.location == 0 {
					ownerCell?.requestMoveFocusUp()
					return
				}
			case .downArrow:
				let sel = selectedRange
				if sel.length == 0, sel.location == attributedText.length {
					ownerCell?.requestMoveFocusDown()
					return
				}
			default:
				break
			}
		}

		super.pressesBegan(presses, with: event)
	}

	private func isMacRuntime() -> Bool {
		if #available(iOS 14.0, *) { return ProcessInfo.processInfo.isiOSAppOnMac }
		return false
	}
}

enum BlockFocusMoveDirection {
	case up
	case down
}

protocol BlockCellDelegate: AnyObject {
    func blockCell(_ cell: BlockCell, didChangeText text: NSAttributedString)
    func blockCell(_ cell: BlockCell, didTrigger action: KeyboardAction)
	func blockCell(_ cell: BlockCell, didTapURL url: URL)
	func blockCell(_ cell: BlockCell, didChangeInlineTypingModeBold isBold: Bool, italic isItalic: Bool)
	func blockCell(_ cell: BlockCell, didRequestMoveFocus direction: BlockFocusMoveDirection)
}

protocol BlockSelectableCell: AnyObject {
	var isSelectionMode: Bool { get set }
}

final class BlockCell: UITableViewCell, UITextViewDelegate, UITextDropDelegate, BlockSelectableCell {
    static let reuseId = "BlockCell"
    
    weak var delegate: BlockCellDelegate?
    private(set) var blockId: String = ""
    private var style: TextStyle = .text
    private var lastTextWasEmpty = true
    private var isFirstBlock = false
    
    private let cardView = UIView()
    private let prefixContainer = UIView()
    private let prefixLabel = UILabel()
	private let checkboxButton = UIButton(type: .system)
    private let stack = UIStackView()
    private var prefixWidthConstraint: NSLayoutConstraint?
	private var prefixHeightConstraint: NSLayoutConstraint?
    private var minTextViewHeightConstraint: NSLayoutConstraint?
    let textView = BlocksEditorTextView()
	private let dividerView = UIView()
    private let placeholderLabel = UILabel()
    private var keyboardAccessoryView: KeyboardActionAccessoryView?
	private var pasteboardObservers: [NSObjectProtocol] = []
    private var transientBoldMode = false
    private var transientItalicMode = false
	private var isApplyingInlineTagAttributes = false
	private var isApplyingInlineLinkAttributes = false
	private var isApplyingInlineChecklistAttributes = false
	private var isApplyingBaseTextAttributes = false

	private static let tagRegex = try! NSRegularExpression(
		pattern: "(?<![\\p{L}\\p{N}_])#([\\p{L}\\p{N}_\\-\\p{So}\\p{Sk}\\p{Mn}\\p{Mc}\\p{Cf}]+)",
		options: []
	)
	private static let markdownLinkRegex = try! NSRegularExpression(
		pattern: "\\[([^\\]]+)\\]\\(([^\\s\\)]+)\\)",
		options: []
	)
	private static let linkDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    var isSelectionMode: Bool = false {
        didSet {
            textView.isEditable = !isSelectionMode
            textView.isUserInteractionEnabled = !isSelectionMode
            updateSelectionAppearance()
            updatePlaceholderVisibility()
			updateDividerVisibility()
        }
    }
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        
        contentView.addSubview(cardView)
        cardView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 1),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -1),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12)
        ])
        
        cardView.layer.cornerRadius = 12
        cardView.layer.masksToBounds = true
        cardView.backgroundColor = .clear
        
		prefixLabel.font = UIFont.preferredFont(forTextStyle: .body)
		prefixLabel.adjustsFontForContentSizeCategory = true
		prefixLabel.textColor = .secondaryLabel
		prefixLabel.textAlignment = .center

		prefixContainer.translatesAutoresizingMaskIntoConstraints = false
		prefixContainer.addSubview(prefixLabel)
		prefixLabel.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			prefixLabel.centerXAnchor.constraint(equalTo: prefixContainer.centerXAnchor),
			prefixLabel.centerYAnchor.constraint(equalTo: prefixContainer.centerYAnchor),
			prefixLabel.leadingAnchor.constraint(greaterThanOrEqualTo: prefixContainer.leadingAnchor),
			prefixLabel.trailingAnchor.constraint(lessThanOrEqualTo: prefixContainer.trailingAnchor),
			prefixLabel.topAnchor.constraint(greaterThanOrEqualTo: prefixContainer.topAnchor),
			prefixLabel.bottomAnchor.constraint(lessThanOrEqualTo: prefixContainer.bottomAnchor),
		])

		checkboxButton.translatesAutoresizingMaskIntoConstraints = false
		checkboxButton.tintColor = .appAccent
		checkboxButton.contentHorizontalAlignment = .center
		checkboxButton.contentVerticalAlignment = .center
		checkboxButton.addTarget(self, action: #selector(didTapCheckbox), for: .touchUpInside)
		prefixContainer.addSubview(checkboxButton)
		NSLayoutConstraint.activate([
			checkboxButton.centerXAnchor.constraint(equalTo: prefixContainer.centerXAnchor),
			checkboxButton.centerYAnchor.constraint(equalTo: prefixContainer.centerYAnchor),
			checkboxButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 22),
			checkboxButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 22),
		])
        
        stack.axis = .horizontal
        stack.alignment = .top
        stack.spacing = 8
        stack.addArrangedSubview(prefixContainer)
        stack.addArrangedSubview(textView)
        
        cardView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
        ])
        let prefixWidth = prefixContainer.widthAnchor.constraint(equalToConstant: 0)
        prefixWidth.isActive = true
        prefixWidthConstraint = prefixWidth
		let prefixHeight = prefixContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 0)
		prefixHeight.isActive = true
		prefixHeightConstraint = prefixHeight

        let minHeight = textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 0)
        minHeight.isActive = true
        minTextViewHeightConstraint = minHeight

		dividerView.backgroundColor = .separator
		dividerView.layer.cornerRadius = 0.5
		dividerView.layer.masksToBounds = true
		dividerView.isHidden = true
		dividerView.translatesAutoresizingMaskIntoConstraints = false
		cardView.addSubview(dividerView)
		NSLayoutConstraint.activate([
			dividerView.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
			dividerView.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
			dividerView.centerYAnchor.constraint(equalTo: stack.centerYAnchor),
			dividerView.heightAnchor.constraint(equalToConstant: 1)
		])
        
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
		textView.textColor = baseTextColor()
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
		textView.smartDashesType = .no
		textView.smartQuotesType = .no
		textView.smartInsertDeleteType = .no
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = self
        textView.returnKeyType = .default
        textView.textDropDelegate = self
		textView.isSelectable = true
		textView.ownerCell = self
		textView.linkTextAttributes = [
			.foregroundColor: UIColor.appAccent,
			.underlineStyle: NSUnderlineStyle.single.rawValue
		]

		let tap = UITapGestureRecognizer(target: self, action: #selector(didTapTextView(_:)))
		tap.delegate = self
		tap.cancelsTouchesInView = false
		textView.addGestureRecognizer(tap)

        placeholderLabel.text = String(localized: "note.editor.placeholder.start_typing")
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.numberOfLines = 1
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor),
        ])

        let keyboardAccessoryView = KeyboardActionAccessoryView(
			onMedia: { [weak self] in
				guard let self else { return }
				self.delegate?.blockCell(self, didTrigger: .pickMedia)
			},
			onPaste: { [weak self] in
				guard let self else { return }
				guard UIPasteboard.general.hasStrings else { return }
				self.textView.paste(nil)
			},
            onHash: { [weak self] in
                self?.textView.insertText("#")
            },
            onBold: { [weak self] in
                self?.toggleBold()
            },
            onItalic: { [weak self] in
                self?.toggleItalic()
            },
			onCodeBlock: { [weak self] in
				guard let self else { return }
				guard self.style != .code else { return }
				let text = self.textView.attributedText ?? NSAttributedString(string: "")
				self.delegate?.blockCell(self, didTrigger: .markdownTurnInto(style: .code, text: text))
			},
			onCheckbox: { [weak self] in
				guard let self else { return }
				guard self.style != .code else { return }
				let current = self.textView.attributedText ?? NSAttributedString(string: "")
				let updated = NSMutableAttributedString(attributedString: current)
				let ns = updated.string as NSString
				if ns.length < 4 || !(ns.hasPrefix("[ ] ") || ns.substring(with: NSRange(location: 0, length: 4)).lowercased() == "[x] ") {
					updated.replaceCharacters(in: NSRange(location: 0, length: 0), with: "[ ] ")
				}
				self.delegate?.blockCell(self, didTrigger: .markdownTurnInto(style: .checkbox, text: updated))
			},
			onDivider: { [weak self] in
				guard let self else { return }
				self.delegate?.blockCell(self, didTrigger: .insertDivider)
			},
			onLinkToNote: { [weak self] in
				guard let self else { return }
				self.delegate?.blockCell(self, didTrigger: .presentLinkToNoteSheet)
			},
			onDone: { [weak self] in
				self?.textView.resignFirstResponder()
			}
        )
        textView.inputAccessoryView = keyboardAccessoryView
        self.keyboardAccessoryView = keyboardAccessoryView

		let nc = NotificationCenter.default
		pasteboardObservers.append(
			nc.addObserver(forName: UIPasteboard.changedNotification, object: nil, queue: .main) { [weak self] _ in
				self?.updateKeyboardAccessoryState()
			}
		)
		pasteboardObservers.append(
			nc.addObserver(forName: UIPasteboard.removedNotification, object: nil, queue: .main) { [weak self] _ in
				self?.updateKeyboardAccessoryState()
			}
		)
        
        updateSelectionAppearance()
    }

	deinit {
		let nc = NotificationCenter.default
		for token in pasteboardObservers {
			nc.removeObserver(token)
		}
	}
    
    func textDroppableView(_ textDroppableView: UIView & UITextDroppable, proposalForDrop drop: UITextDropRequest) -> UITextDropProposal {
        UITextDropProposal(operation: .cancel)
    }
    
    func textDroppableView(_ textDroppableView: UIView & UITextDroppable, performDrop drop: UITextDropRequest) {
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    func configure(blockId: String, text: NSAttributedString, style: TextStyle, isFirstBlock: Bool) {
        self.blockId = blockId
        self.style = style
        self.isFirstBlock = isFirstBlock
		if isFirstBlock {
			textView.accessibilityIdentifier = "note.editor.firstBlock"
		} else {
			textView.accessibilityIdentifier = nil
		}
		let sanitizedText: NSAttributedString = {
			guard text.length > 0 else { return text }
			let updated = NSMutableAttributedString(attributedString: text)
			updated.removeAttribute(.foregroundColor, range: NSRange(location: 0, length: updated.length))
			return updated
		}()
        if textView.attributedText != sanitizedText {
            textView.attributedText = sanitizedText
		}
        lastTextWasEmpty = text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        applyStyle()
		applyInlineChecklistAttributesIfNeeded(preservingSelection: textView.selectedRange)
		applyInlineTagAttributesIfNeeded(preservingSelection: textView.selectedRange)
		applyInlineLinkAttributesIfNeeded(preservingSelection: textView.selectedRange)
		applyBaseTextAttributesIfNeeded()
        updateSelectionAppearance()
        updatePlaceholderVisibility()
		updateDividerVisibility()
        updateKeyboardAccessoryState()
    }

	func didExternallySetText(preservingSelection selection: NSRange? = nil) {
		if let selection {
			textView.selectedRange = selection
		}
		applyInlineChecklistAttributesIfNeeded(preservingSelection: textView.selectedRange)
		applyInlineTagAttributesIfNeeded(preservingSelection: textView.selectedRange)
		applyInlineLinkAttributesIfNeeded(preservingSelection: textView.selectedRange)
		applyBaseTextAttributesIfNeeded()
		lastTextWasEmpty = textView.attributedText.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		updatePlaceholderVisibility()
		updateDividerVisibility()
		updateKeyboardAccessoryState()
	}
    
    func textViewDidChange(_ textView: UITextView) {
		if isApplyingInlineTagAttributes { return }
		if isApplyingInlineLinkAttributes { return }
		if isApplyingInlineChecklistAttributes { return }
		if isApplyingBaseTextAttributes { return }
		applyInlineChecklistAttributesIfNeeded(preservingSelection: textView.selectedRange)
		applyInlineTagAttributesIfNeeded(preservingSelection: textView.selectedRange)
		applyInlineLinkAttributesIfNeeded(preservingSelection: textView.selectedRange)
		applyBaseTextAttributesIfNeeded()
        let newIsEmpty = textView.attributedText.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        lastTextWasEmpty = newIsEmpty
        updatePlaceholderVisibility()
		updateDividerVisibility()
        updateKeyboardAccessoryState()
        delegate?.blockCell(self, didChangeText: textView.attributedText)
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        updateKeyboardAccessoryState()
        if let keyboardAccessoryView {
            textView.inputAccessoryView = keyboardAccessoryView
        }
		applyStyle()
		applyInlineChecklistAttributesIfNeeded(preservingSelection: textView.selectedRange)
		if isInlineTypingActive() {
			applyTransientTypingAttributes()
		} else {
			var typing = textView.typingAttributes
			typing[.font] = resolvedBaseFontForCurrentStyle()
			textView.typingAttributes = typing
		}
        textView.reloadInputViews()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        if let keyboardAccessoryView {
            textView.inputAccessoryView = nil
        }
		if isApplyingInlineTagAttributes { return }
		if isApplyingInlineLinkAttributes { return }
		if isApplyingInlineChecklistAttributes { return }
		applyInlineChecklistAttributesIfNeeded(preservingSelection: textView.selectedRange)
		applyInlineTagAttributesIfNeeded(preservingSelection: textView.selectedRange)
		applyInlineLinkAttributesIfNeeded(preservingSelection: textView.selectedRange)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        if style == .code { return }
        if isSelectionMode { return }
		if isApplyingInlineChecklistAttributes { return }
		if isApplyingInlineTagAttributes { return }
		if isApplyingInlineLinkAttributes { return }
		if isApplyingBaseTextAttributes { return }
		if style == .checkbox {
			let length = textView.attributedText.length
			let clamped = NSRange(location: min(max(textView.selectedRange.location, 4), length), length: 0)
			if textView.selectedRange != clamped {
				textView.selectedRange = clamped
				return
			}

			let shouldRefreshInlineChecklist = textView.attributedText.length >= 4
				&& textView.attributedText.attribute(.appInlineCheckboxHidden, at: 0, effectiveRange: nil) == nil
			if shouldRefreshInlineChecklist {
				applyInlineChecklistAttributesIfNeeded(preservingSelection: textView.selectedRange)
			}

			let ns = textView.attributedText.string as NSString
			let isChecked: Bool = {
				guard ns.length >= 2 else { return false }
				return ns.substring(with: NSRange(location: 1, length: 1)).lowercased() == "x"
			}()

			let baseFont = textView.font ?? UIFont.preferredFont(forTextStyle: .body)
			var typing = textView.typingAttributes
			typing[.font] = baseFont
			typing.removeValue(forKey: .foregroundColor)
			textView.typingAttributes = typing
			updateKeyboardAccessoryState()
			return
		}

        let length = textView.attributedText.length
		if length == 0 {
			var typing = textView.typingAttributes
			typing[.font] = resolvedBaseFontForCurrentStyle()
			textView.typingAttributes = typing
			if isInlineTypingActive() {
				applyTransientTypingAttributes()
			} else {
				enforcePlainTypingAfterWhitespaceIfNeeded()
			}
			updateKeyboardAccessoryState()
			return
		}

        let sel = textView.selectedRange
        let index = min(max(sel.location, 0), max(length - 1, 0))
		var linkEffectiveRange = NSRange(location: NSNotFound, length: 0)
        let attrs = textView.attributedText.attributes(at: index, effectiveRange: &linkEffectiveRange)

        var typing = textView.typingAttributes
        if let font = attrs[.font] as? UIFont {
            typing[.font] = font
        } else if let font = textView.font {
            typing[.font] = font
        }

		let hasLinkHere = attrs[.link] != nil || attrs[.appInlineLinkUrl] != nil || attrs[.appInlineNoteLinkId] != nil
		let isCaretAtLinkBoundary: Bool = {
			guard sel.length == 0 else { return false }
			guard linkEffectiveRange.location != NSNotFound else { return false }
			let upper = linkEffectiveRange.location + linkEffectiveRange.length
			return sel.location == linkEffectiveRange.location || sel.location == upper
		}()

        func carry(_ key: NSAttributedString.Key) {
            if let v = attrs[key] {
                typing[key] = v
            } else {
                typing.removeValue(forKey: key)
            }
        }

		if hasLinkHere && isCaretAtLinkBoundary {
			typing.removeValue(forKey: .link)
			typing.removeValue(forKey: .appInlineLinkUrl)
			typing.removeValue(forKey: .appInlineNoteLinkId)
		} else {
			carry(.link)
			carry(.appInlineLinkUrl)
			carry(.appInlineNoteLinkId)
		}

        carry(.appInlineBold)
        carry(.appInlineItalic)
        carry(.appInlineCode)
        carry(.appInlineStrike)

        textView.typingAttributes = typing
        if isInlineTypingActive() {
            applyTransientTypingAttributes()
        } else {
            enforcePlainTypingAfterWhitespaceIfNeeded()
        }
        updateKeyboardAccessoryState()
    }
    
    func textView(
        _ textView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText text: String
    ) -> Bool {
		if isDividerBlock() {
			if text == "\n" {
				delegate?.blockCell(self, didTrigger: .enterAtTheEnd(string: textView.attributedText, range: range))
				return false
			}
			if text.isEmpty {
				delegate?.blockCell(self, didTrigger: .delete)
				return false
			}
			delegate?.blockCell(self, didTrigger: .insertNewBlockWithText(text: text))
			return false
		}

		if style == .checkbox, text.isEmpty {
			let full = textView.attributedText.string as NSString
			let prefixLen = 4
			let remainder: String = {
				if full.length <= prefixLen { return "" }
				return full.substring(from: prefixLen)
			}()
			let isEffectivelyEmpty = remainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			if range.location < prefixLen {
				if isEffectivelyEmpty {
					style = .text
					let baseFont = textView.font ?? UIFont.preferredFont(forTextStyle: .body)
					textView.attributedText = NSAttributedString(string: "", attributes: [.font: baseFont])
					textView.selectedRange = NSRange(location: 0, length: 0)
					var typing = textView.typingAttributes
					typing[.font] = baseFont
					typing.removeValue(forKey: .foregroundColor)
					textView.typingAttributes = typing
					applyStyle()
					lastTextWasEmpty = true
					updatePlaceholderVisibility()
					updateDividerVisibility()
					updateKeyboardAccessoryState()
					delegate?.blockCell(self, didTrigger: .markdownTurnInto(style: .text, text: NSAttributedString(string: "")))
				}
				return false
			}
		}

		if style != .code, text == "-" {
			let updated = NSMutableAttributedString(attributedString: textView.attributedText)
			updated.replaceCharacters(in: range, with: "-")
			let trimmed = updated.string.trimmingCharacters(in: .whitespacesAndNewlines)
			if trimmed == "---" || trimmed == "----" {
				textView.attributedText = updated
				textView.selectedRange = NSRange(location: range.location + 1, length: 0)
				updateKeyboardAccessoryState()
				delegate?.blockCell(self, didTrigger: .insertDivider)
				return false
			}
		}

        if (style == .title || style == .description || style == .heading3 || style == .heading4 || style == .heading5 || style == .heading6),
           text.isEmpty,
           range.location == 0,
           range.length == 0,
           textView.attributedText.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            lastTextWasEmpty = true
            delegate?.blockCell(self, didTrigger: .markdownTurnInto(style: .text, text: NSAttributedString(string: "")))
            return false
        }

        if style == .code, text == "\n" {
            let full = textView.attributedText.string as NSString
            let isAtEnd = range.location == full.length
            let prevNewlineRange = full.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: range.location))
            let lineStart = prevNewlineRange.location != NSNotFound ? prevNewlineRange.location + prevNewlineRange.length : 0
            let isCurrentLineEmpty = range.location == lineStart
            
            if isAtEnd && isCurrentLineEmpty {
                delegate?.blockCell(self, didTrigger: .enterAtTheEnd(string: textView.attributedText, range: range))
                return false
            }
            
            let updated = NSMutableAttributedString(attributedString: textView.attributedText)
            updated.replaceCharacters(in: range, with: "\n")
            applyCodeAttributes(to: updated)
            
            textView.attributedText = updated
            textView.selectedRange = NSRange(location: range.location + 1, length: 0)
            updateKeyboardAccessoryState()
            delegate?.blockCell(self, didChangeText: updated)
            return false
        }

		if style != .code, text != "\n", (text.contains("\n") || text.contains("\r")) {
			delegate?.blockCell(self, didTrigger: .pasteMultiline(text: text, range: range))
			return false
		}
        
        if let change = inlineMarkdownChange(textView: textView, replacementText: text, range: range) {
            textView.attributedText = change.text
            textView.selectedRange = change.focusRange
			applyInlineChecklistAttributesIfNeeded(preservingSelection: change.focusRange)
			applyInlineTagAttributesIfNeeded(preservingSelection: change.focusRange)
			applyInlineLinkAttributesIfNeeded(preservingSelection: change.focusRange)
            updateKeyboardAccessoryState()
            delegate?.blockCell(self, didChangeText: change.text)
            return false
        }
        if let action = KeyboardAction.build(attributedText: textView.attributedText, range: range, replacement: text) {
            delegate?.blockCell(self, didTrigger: action)
            return false
        }

		if shouldExitLinkTypingOnWhitespace(range: range, replacementText: text) {
			clearLinkTypingAttributes()
		}

		if style != .code, text != "\n", text.isEmpty == false, (isInlineTypingActive() || isHeadingStyle(style)) {
			applyManualInsert(text: text, range: range)
			return false
		}

        return true
    }

	private func isHeadingStyle(_ style: TextStyle) -> Bool {
		switch style {
		case .title, .description, .heading3, .heading4, .heading5, .heading6:
			return true
		default:
			return false
		}
	}

	private func resolvedBaseFontForCurrentStyle() -> UIFont {
		func scaled(_ font: UIFont, textStyle: UIFont.TextStyle) -> UIFont {
			UIFontMetrics(forTextStyle: textStyle).scaledFont(for: font)
		}

		switch style {
		case .title:
			return scaled(UIFont.appSpaceGrotesk(size: 32, weight: .bold), textStyle: .largeTitle)
		case .description:
			return scaled(UIFont.appSpaceGrotesk(size: 26, weight: .bold), textStyle: .title2)
		case .heading3:
			return scaled(UIFont.appSpaceGrotesk(size: 22, weight: .semibold), textStyle: .title3)
		case .heading4:
			return scaled(UIFont.appSpaceGrotesk(size: 19, weight: .semibold), textStyle: .headline)
		case .heading5:
			return scaled(UIFont.appSpaceGrotesk(size: 17, weight: .medium), textStyle: .subheadline)
		case .heading6:
			return scaled(UIFont.appSpaceGrotesk(size: 15, weight: .medium), textStyle: .callout)
		case .code:
			return UIFontMetrics(forTextStyle: .body).scaledFont(for: UIFont.monospacedSystemFont(ofSize: 17, weight: .regular))
		default:
			return scaled(UIFont.appDMSans(size: 17, weight: .regular), textStyle: .body)
		}
	}

	private func applyManualInsert(text: String, range: NSRange) {
		let current = textView.attributedText ?? NSAttributedString(string: "")
		let updated = NSMutableAttributedString(attributedString: current)

		var attrs = textView.typingAttributes
		let baseFont = resolvedBaseFontForCurrentStyle()
		var desiredTraits: UIFontDescriptor.SymbolicTraits = []
		if transientBoldMode { desiredTraits.insert(.traitBold) }
		if transientItalicMode { desiredTraits.insert(.traitItalic) }
		attrs[.font] = desiredTraits.isEmpty ? baseFont : baseFont.withTraits(desiredTraits)
		attrs[.appInlineBold] = transientBoldMode ? true : nil
		attrs[.appInlineItalic] = transientItalicMode ? true : nil

		updated.replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: attrs))
		textView.attributedText = updated
		let newLocation = range.location + (text as NSString).length
		textView.selectedRange = NSRange(location: newLocation, length: 0)
		didExternallySetText(preservingSelection: textView.selectedRange)
		delegate?.blockCell(self, didChangeText: textView.attributedText)
	}
    
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        updateSelectionAppearance()
    }

	@objc
	private func didTapTextView(_ recognizer: UITapGestureRecognizer) {
		guard recognizer.state == .ended else { return }
		guard isSelectionMode == false else { return }

		let location = recognizer.location(in: textView)
		let index = characterIndex(at: location)
		guard index != NSNotFound else { return }
		guard index >= 0, index < textView.attributedText.length else { return }

		let attrs = textView.attributedText.attributes(at: index, effectiveRange: nil)
		if let urlValue = attrs[.link] {
			let url: URL? = {
				if let u = urlValue as? URL { return u }
				if let s = urlValue as? String { return URL(string: s) }
				return nil
			}()
			guard let url else { return }
			delegate?.blockCell(self, didTapURL: url)
			return
		}

		if style == .checkbox {
			textView.becomeFirstResponder()
			let end = NSRange(location: textView.attributedText.length, length: 0)
			textView.selectedRange = end
			updateKeyboardAccessoryState()
		}
	}

	@objc
	private func didTapCheckbox() {
		guard isSelectionMode == false else { return }
		guard style == .checkbox else { return }

		let current = textView.attributedText ?? NSAttributedString(string: "")
		let updated = NSMutableAttributedString(attributedString: current)
		var sel = textView.selectedRange

		if let baseFont = textView.font {
			var missingFontRanges: [NSRange] = []
			updated.enumerateAttribute(.font, in: NSRange(location: 0, length: updated.length), options: []) { value, range, _ in
				if value == nil {
					missingFontRanges.append(range)
				}
			}
			for range in missingFontRanges {
				updated.addAttribute(.font, value: baseFont, range: range)
			}
		}

		let ns = updated.string as NSString
		if ns.length >= 6, (ns.hasPrefix("- ") || ns.hasPrefix("* ")) {
			let checkboxPrefix = ns.substring(with: NSRange(location: 2, length: 4)).lowercased()
			if checkboxPrefix == "[ ] " || checkboxPrefix == "[x] " {
				updated.deleteCharacters(in: NSRange(location: 0, length: 2))
				sel = NSRange(location: max(sel.location - 2, 0), length: 0)
			}
		}

		let ns2 = updated.string as NSString
		let prefixLen = 4
		if ns2.length < prefixLen || !(ns2.hasPrefix("[ ] ") || ns2.lowercased.hasPrefix("[x] ")) {
			updated.replaceCharacters(in: NSRange(location: 0, length: 0), with: "[ ] ")
			sel = NSRange(location: sel.location + prefixLen, length: 0)
		}

		if updated.length >= 2 {
			let flagRange = NSRange(location: 1, length: 1)
			let flag = (updated.string as NSString).substring(with: flagRange).lowercased()
			updated.replaceCharacters(in: flagRange, with: flag == "x" ? " " : "x")
		}

		textView.attributedText = updated
		textView.selectedRange = NSRange(location: max(sel.location, prefixLen), length: 0)
		applyInlineChecklistAttributesIfNeeded(preservingSelection: textView.selectedRange)
		applyInlineTagAttributesIfNeeded(preservingSelection: textView.selectedRange)
		applyInlineLinkAttributesIfNeeded(preservingSelection: textView.selectedRange)
		updateKeyboardAccessoryState()
		delegate?.blockCell(self, didChangeText: textView.attributedText)
	}

	override func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
		guard isSelectionMode == false else { return false }

		let location = touch.location(in: textView)
		let index = characterIndex(at: location)
		guard index != NSNotFound else { return false }
		guard index >= 0, index < textView.attributedText.length else { return false }

		let attrs = textView.attributedText.attributes(at: index, effectiveRange: nil)
		guard let urlValue = attrs[.link] else { return false }

		let url: URL? = {
			if let u = urlValue as? URL { return u }
			if let s = urlValue as? String { return URL(string: s) }
			return nil
		}()
		return url != nil
	}

	override func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
		true
	}

	private func characterIndex(at location: CGPoint) -> Int {
		let manager = textView.layoutManager
		let container = textView.textContainer
		var point = location
		point.x -= textView.textContainerInset.left
		point.y -= textView.textContainerInset.top

		let glyphIndex = manager.glyphIndex(for: point, in: container)
		let rect = manager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: container)
		guard rect.contains(point) else { return NSNotFound }
		return manager.characterIndexForGlyph(at: glyphIndex)
	}
    
    private func updateSelectionAppearance() {
        if isSelectionMode && isSelected {
            cardView.layer.borderWidth = 2
            cardView.layer.borderColor = UIColor.appAccent.cgColor
            cardView.backgroundColor = UIColor.appAccent.withAlphaComponent(0.06)
        } else {
            cardView.layer.borderWidth = 0
            cardView.layer.borderColor = nil
            if style == .code {
                cardView.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.8)
            } else {
                cardView.backgroundColor = .clear
            }
        }
    }
    
    private func applyStyle() {
        func scaled(_ font: UIFont, textStyle: UIFont.TextStyle) -> UIFont {
            UIFontMetrics(forTextStyle: textStyle).scaledFont(for: font)
        }
        
        switch style {
        case .title:
            let font = scaled(UIFont.appSpaceGrotesk(size: 32, weight: .bold), textStyle: .largeTitle)
            textView.font = font
            textView.typingAttributes[.font] = font
            prefixLabel.text = ""
			prefixLabel.isHidden = true
			checkboxButton.isHidden = true
			prefixContainer.isHidden = true
            prefixWidthConstraint?.constant = 0
        case .description:
            let font = scaled(UIFont.appSpaceGrotesk(size: 26, weight: .bold), textStyle: .title2)
            textView.font = font
            textView.typingAttributes[.font] = font
            prefixLabel.text = ""
			prefixLabel.isHidden = true
			checkboxButton.isHidden = true
			prefixContainer.isHidden = true
            prefixWidthConstraint?.constant = 0
        case .heading3:
            let font = scaled(UIFont.appSpaceGrotesk(size: 22, weight: .semibold), textStyle: .title3)
            textView.font = font
            textView.typingAttributes[.font] = font
            prefixLabel.text = ""
			prefixLabel.isHidden = true
			checkboxButton.isHidden = true
			prefixContainer.isHidden = true
            prefixWidthConstraint?.constant = 0
        case .heading4:
            let font = scaled(UIFont.appSpaceGrotesk(size: 19, weight: .semibold), textStyle: .headline)
            textView.font = font
            textView.typingAttributes[.font] = font
            prefixLabel.text = ""
			prefixLabel.isHidden = true
			checkboxButton.isHidden = true
			prefixContainer.isHidden = true
            prefixWidthConstraint?.constant = 0
        case .heading5:
            let font = scaled(UIFont.appSpaceGrotesk(size: 17, weight: .medium), textStyle: .subheadline)
            textView.font = font
            textView.typingAttributes[.font] = font
            prefixLabel.text = ""
			prefixLabel.isHidden = true
			checkboxButton.isHidden = true
			prefixContainer.isHidden = true
            prefixWidthConstraint?.constant = 0
        case .heading6:
            let font = scaled(UIFont.appSpaceGrotesk(size: 15, weight: .medium), textStyle: .callout)
            textView.font = font
            textView.typingAttributes[.font] = font
            prefixLabel.text = ""
			prefixLabel.isHidden = true
			checkboxButton.isHidden = true
			prefixContainer.isHidden = true
            prefixWidthConstraint?.constant = 0
        case .code:
            let mono = scaled(UIFont.monospacedSystemFont(ofSize: 17, weight: .regular), textStyle: .body)
            textView.font = mono
            textView.typingAttributes[.font] = mono
            if let attr = textView.attributedText, attr.length > 0 {
                let updated = NSMutableAttributedString(attributedString: attr)
                applyCodeAttributes(to: updated)
                textView.attributedText = updated
            }
            prefixLabel.text = ""
			prefixLabel.isHidden = true
			checkboxButton.isHidden = true
			prefixContainer.isHidden = true
            prefixWidthConstraint?.constant = 0
        case .listBullet:
            let font = scaled(UIFont.appDMSans(size: 17, weight: .regular), textStyle: .body)
            textView.font = font
            textView.typingAttributes[.font] = font
            prefixLabel.text = "•"
			prefixLabel.isHidden = false
			checkboxButton.isHidden = true
			prefixContainer.isHidden = false
            prefixWidthConstraint?.constant = 22
        case .toggle, .toggleHeader:
            let font = scaled(UIFont.appDMSans(size: 17, weight: .regular), textStyle: .body)
            textView.font = font
            textView.typingAttributes[.font] = font
            prefixLabel.text = "▸"
			prefixLabel.isHidden = false
			checkboxButton.isHidden = true
			prefixContainer.isHidden = false
            prefixWidthConstraint?.constant = 22
        case .text:
            let font = scaled(UIFont.appDMSans(size: 17, weight: .regular), textStyle: .body)
            textView.font = font
            textView.typingAttributes[.font] = font
            prefixLabel.text = ""
			prefixLabel.isHidden = true
			checkboxButton.isHidden = true
			prefixContainer.isHidden = true
            prefixWidthConstraint?.constant = 0
		case .checkbox:
			let font = scaled(UIFont.appDMSans(size: 17, weight: .regular), textStyle: .body)
			textView.font = font
			textView.typingAttributes[.font] = font
			prefixLabel.text = ""
			prefixLabel.isHidden = true
			checkboxButton.isHidden = false
			prefixContainer.isHidden = false
			prefixWidthConstraint?.constant = 26
			if let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold) as UIImage.SymbolConfiguration? {
				checkboxButton.setPreferredSymbolConfiguration(config, forImageIn: .normal)
			}
        }
        
        if style != .code {
            rebaseInlineFonts()
        }
        prefixLabel.font = textView.font
        placeholderLabel.font = textView.font
        if let font = textView.font {
            minTextViewHeightConstraint?.constant = ceil(font.lineHeight + 2)
			prefixHeightConstraint?.constant = ceil(font.lineHeight + 2)
        }
        updateKeyboardAccessoryState()
    }

    private func rebaseInlineFonts() {
        guard let current = textView.attributedText, current.length > 0 else { return }
        guard let baseFont = textView.font else { return }

        func boolAttr(_ attrs: [NSAttributedString.Key: Any], _ key: NSAttributedString.Key) -> Bool {
            if let b = attrs[key] as? Bool { return b }
            if let n = attrs[key] as? NSNumber { return n.boolValue }
            return false
        }

        func isMonospaced(_ font: UIFont) -> Bool {
            let traits = font.fontDescriptor.symbolicTraits
            if traits.contains(.traitMonoSpace) { return true }
            let name = (font.fontName + " " + font.familyName).lowercased()
            return name.contains("mono")
        }

		func weightValue(_ font: UIFont) -> CGFloat {
			let traits = font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
			if let n = traits?[.weight] as? NSNumber { return CGFloat(truncating: n) }
			if let c = traits?[.weight] as? CGFloat { return c }
			return UIFont.Weight.regular.rawValue
		}

		func slantValue(_ font: UIFont) -> CGFloat {
			let traits = font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
			if let n = traits?[.slant] as? NSNumber { return CGFloat(truncating: n) }
			if let c = traits?[.slant] as? CGFloat { return c }
			return 0
		}

        let fullRange = NSRange(location: 0, length: current.length)
        let updated = NSMutableAttributedString(attributedString: current)

        updated.enumerateAttributes(in: fullRange, options: []) { attrs, range, _ in
            let existing = (attrs[.font] as? UIFont) ?? baseFont

            let named = existing.fontName.lowercased()
            let traits = existing.fontDescriptor.symbolicTraits
			let weight = weightValue(existing)
			let slant = slantValue(existing)

            let inlineCode = boolAttr(attrs, .appInlineCode) || isMonospaced(existing)
            let inlineBold = boolAttr(attrs, .appInlineBold) || traits.contains(.traitBold) || named.contains("bold") || named.contains("semibold") || named.contains("demibold") || named.contains("heavy") || named.contains("black") || weight >= UIFont.Weight.semibold.rawValue
            let inlineItalic = boolAttr(attrs, .appInlineItalic) || traits.contains(.traitItalic) || named.contains("italic") || named.contains("oblique") || abs(slant) > 0.01

            if inlineCode {
                let mono = UIFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
                updated.addAttribute(.font, value: mono, range: range)
                return
            }

            var desiredTraits: UIFontDescriptor.SymbolicTraits = []
            if inlineBold { desiredTraits.insert(.traitBold) }
            if inlineItalic { desiredTraits.insert(.traitItalic) }
            updated.addAttribute(.font, value: baseFont.withTraits(desiredTraits), range: range)
        }

        textView.attributedText = updated
    }

    private func updatePlaceholderVisibility() {
        let isEmpty = textView.attributedText.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        placeholderLabel.isHidden = !isFirstBlock || !isEmpty || isSelectionMode
    }

	private func isDividerBlock() -> Bool {
		guard style == .text else { return false }
		let trimmed = textView.attributedText.string.trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmed == "---" || trimmed == "----"
	}

	private func updateDividerVisibility() {
		let isDivider = isDividerBlock()
		dividerView.isHidden = !isDivider
		if isDivider {
			dividerView.backgroundColor = traitCollection.userInterfaceStyle == .dark
				? UIColor.white.withAlphaComponent(0.22)
				: UIColor.separator
		} else {
			dividerView.backgroundColor = .separator
		}
		textView.isHidden = false
		textView.alpha = isDivider ? 0.01 : 1
		textView.tintColor = isDivider ? .clear : .appAccent
		if isDivider {
			minTextViewHeightConstraint?.constant = 0
		} else if let font = textView.font {
			minTextViewHeightConstraint?.constant = ceil(font.lineHeight + 2)
		}
		stack.alignment = .top
		if isDivider {
			placeholderLabel.isHidden = true
		}

		textView.isEditable = !isSelectionMode
		textView.isUserInteractionEnabled = !isSelectionMode
	}

    private func boolAttr(_ attrs: [NSAttributedString.Key: Any], _ key: NSAttributedString.Key) -> Bool {
        if let b = attrs[key] as? Bool { return b }
        if let n = attrs[key] as? NSNumber { return n.boolValue }
        return false
    }

    private func isInlineTypingActive() -> Bool {
        if style == .code { return false }
        return transientBoldMode || transientItalicMode
    }

	func toggleBold() {
		guard style != .code else { return }
		let selection = textView.selectedRange
		if selection.length == 0 {
			toggleInlineTypingBold()
			return
		}
		toggleInlineMarkup(kind: .bold, selection: selection)
	}

	func toggleItalic() {
		guard style != .code else { return }
		let selection = textView.selectedRange
		if selection.length == 0 {
			toggleInlineTypingItalic()
			return
		}
		toggleInlineMarkup(kind: .italic, selection: selection)
	}

	func setInlineTypingModes(bold: Bool, italic: Bool) {
		guard style != .code else { return }
		transientBoldMode = bold
		transientItalicMode = italic
		applyTransientTypingAttributes()
		delegate?.blockCell(self, didChangeInlineTypingModeBold: transientBoldMode, italic: transientItalicMode)
	}

	func inlineTypingModes() -> (bold: Bool, italic: Bool) {
		(transientBoldMode, transientItalicMode)
	}

	func applyBlockStyleCommand(_ style: TextStyle) {
		guard isSelectionMode == false else { return }
		let text = textView.attributedText ?? NSAttributedString(string: "")
		delegate?.blockCell(self, didTrigger: .markdownTurnInto(style: style, text: text))
	}

	func requestMoveFocusUp() {
		guard isSelectionMode == false else { return }
		delegate?.blockCell(self, didRequestMoveFocus: .up)
	}

	func requestMoveFocusDown() {
		guard isSelectionMode == false else { return }
		delegate?.blockCell(self, didRequestMoveFocus: .down)
	}

    private func toggleInlineTypingBold() {
        guard style != .code else { return }
        transientBoldMode.toggle()
        applyTransientTypingAttributes()
		delegate?.blockCell(self, didChangeInlineTypingModeBold: transientBoldMode, italic: transientItalicMode)
    }

    private func toggleInlineTypingItalic() {
        guard style != .code else { return }
        transientItalicMode.toggle()
        applyTransientTypingAttributes()
		delegate?.blockCell(self, didChangeInlineTypingModeBold: transientBoldMode, italic: transientItalicMode)
    }

	private func isMonospaced(_ font: UIFont) -> Bool {
		let traits = font.fontDescriptor.symbolicTraits
		if traits.contains(.traitMonoSpace) { return true }
		let name = (font.fontName + " " + font.familyName).lowercased()
		return name.contains("mono")
	}

	private func inlineIsCode(_ attrs: [NSAttributedString.Key: Any], font: UIFont) -> Bool {
		boolAttr(attrs, .appInlineCode) || isMonospaced(font)
	}

	private func inlineIsBold(_ attrs: [NSAttributedString.Key: Any], font: UIFont) -> Bool {
		if boolAttr(attrs, .appInlineBold) { return true }
		let traitsDict = font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
		let weight: CGFloat = {
			if let n = traitsDict?[.weight] as? NSNumber { return CGFloat(truncating: n) }
			if let c = traitsDict?[.weight] as? CGFloat { return c }
			return UIFont.Weight.regular.rawValue
		}()
		if weight >= UIFont.Weight.semibold.rawValue { return true }
		let named = font.fontName.lowercased()
		let traits = font.fontDescriptor.symbolicTraits
		return traits.contains(.traitBold) || named.contains("bold") || named.contains("semibold") || named.contains("demibold") || named.contains("heavy") || named.contains("black")
	}

	private func inlineIsItalic(_ attrs: [NSAttributedString.Key: Any], font: UIFont) -> Bool {
		if boolAttr(attrs, .appInlineItalic) { return true }
		let traitsDict = font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
		let slant: CGFloat = {
			if let n = traitsDict?[.slant] as? NSNumber { return CGFloat(truncating: n) }
			if let c = traitsDict?[.slant] as? CGFloat { return c }
			return 0
		}()
		if abs(slant) > 0.01 { return true }
		let named = font.fontName.lowercased()
		let traits = font.fontDescriptor.symbolicTraits
		return traits.contains(.traitItalic) || named.contains("italic") || named.contains("oblique")
	}

	private func toggleInlineMarkup(kind: InlineKind, selection: NSRange) {
		guard let current = textView.attributedText else { return }
		guard current.length > 0 else { return }
		guard selection.length > 0 else { return }

		let baseFont = resolvedBaseFontForCurrentStyle()
		let bounded = NSIntersectionRange(selection, NSRange(location: 0, length: current.length))
		guard bounded.length > 0 else { return }

		var hasAnyFormatting = false
		var allEnabled = true
		current.enumerateAttributes(in: bounded, options: []) { attrs, range, stop in
			let font = (attrs[.font] as? UIFont) ?? baseFont
			if inlineIsCode(attrs, font: font) { return }
			hasAnyFormatting = true
			switch kind {
			case .bold:
				if inlineIsBold(attrs, font: font) == false { allEnabled = false }
			case .italic:
				if inlineIsItalic(attrs, font: font) == false { allEnabled = false }
			default:
				break
			}
		}

		guard hasAnyFormatting else { return }
		let enable = !allEnabled
		let updated = NSMutableAttributedString(attributedString: current)
		updated.enumerateAttributes(in: bounded, options: []) { attrs, range, _ in
			let font = (attrs[.font] as? UIFont) ?? baseFont
			if inlineIsCode(attrs, font: font) { return }

			let currentBold = inlineIsBold(attrs, font: font)
			let currentItalic = inlineIsItalic(attrs, font: font)

			let nextBold: Bool
			let nextItalic: Bool
			switch kind {
			case .bold:
				nextBold = enable
				nextItalic = currentItalic
			case .italic:
				nextBold = currentBold
				nextItalic = enable
			default:
				return
			}

			var desiredTraits: UIFontDescriptor.SymbolicTraits = []
			if nextBold { desiredTraits.insert(.traitBold) }
			if nextItalic { desiredTraits.insert(.traitItalic) }

			let nextFont = baseFont.withTraits(desiredTraits)
			updated.addAttribute(.font, value: nextFont, range: range)

			if nextBold {
				updated.addAttribute(.appInlineBold, value: true, range: range)
			} else {
				updated.removeAttribute(.appInlineBold, range: range)
			}
			if nextItalic {
				updated.addAttribute(.appInlineItalic, value: true, range: range)
			} else {
				updated.removeAttribute(.appInlineItalic, range: range)
			}
		}

		textView.attributedText = updated
		textView.selectedRange = bounded
		lastTextWasEmpty = updated.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		updatePlaceholderVisibility()
		updateKeyboardAccessoryState()
		refreshTextRendering(around: bounded.location)
		delegate?.blockCell(self, didChangeText: updated)
	}

    private func applyTransientTypingAttributes() {
        var attrs = textView.typingAttributes
        attrs[.appInlineBold] = transientBoldMode ? true : nil
        attrs[.appInlineItalic] = transientItalicMode ? true : nil

		let baseFont = resolvedBaseFontForCurrentStyle()
		var desiredTraits: UIFontDescriptor.SymbolicTraits = []
		if transientBoldMode { desiredTraits.insert(.traitBold) }
		if transientItalicMode { desiredTraits.insert(.traitItalic) }
		attrs[.font] = desiredTraits.isEmpty ? baseFont : baseFont.withTraits(desiredTraits)

        textView.typingAttributes = attrs
        updateKeyboardAccessoryState()
    }

    private func enforcePlainTypingAfterWhitespaceIfNeeded() {
        guard style != .code else { return }
        guard transientBoldMode == false, transientItalicMode == false else { return }

        let pos = textView.selectedRange.location
        guard pos > 0 else { return }

        let full = textView.attributedText.string
        guard pos <= full.count else { return }

        let i = full.index(full.startIndex, offsetBy: pos - 1)
        let ch = full[i]
        guard ch.isWhitespace || ch.isNewline else { return }

        var attrs = textView.typingAttributes
        attrs[.appInlineBold] = nil
        attrs[.appInlineItalic] = nil
        attrs[.link] = nil
        attrs[.appInlineLinkUrl] = nil
        attrs[.appInlineNoteLinkId] = nil
        let baseFont = textView.font ?? UIFont.preferredFont(forTextStyle: .body)
        attrs[.font] = baseFont
        textView.typingAttributes = attrs
        refreshTextRendering(around: pos)
    }

	private func shouldExitLinkTypingOnWhitespace(range: NSRange, replacementText text: String) -> Bool {
		guard style != .code else { return false }
		guard range.length == 0 else { return false }
		guard text.isEmpty == false, text.allSatisfy({ $0.isWhitespace && !$0.isNewline }) else { return false }

		let current = textView.attributedText ?? NSAttributedString(string: "")
		guard current.length > 0, range.location > 0, range.location <= current.length else { return false }

		var effectiveRange = NSRange(location: NSNotFound, length: 0)
		let attrs = current.attributes(at: range.location - 1, effectiveRange: &effectiveRange)
		let hasLink = attrs[.link] != nil || attrs[.appInlineLinkUrl] != nil || attrs[.appInlineNoteLinkId] != nil
		guard hasLink, effectiveRange.location != NSNotFound else { return false }

		let upper = effectiveRange.location + effectiveRange.length
		return range.location == upper
	}

	private func clearLinkTypingAttributes() {
		var attrs = textView.typingAttributes
		attrs[.link] = nil
		attrs[.appInlineLinkUrl] = nil
		attrs[.appInlineNoteLinkId] = nil
		textView.typingAttributes = attrs
	}

    private func refreshTextRendering(around location: Int) {
        let length = textView.attributedText.length
        guard length > 0 else { return }
        let start = max(0, location - 4)
        let end = min(length, location + 4)
        let range = NSRange(location: start, length: max(0, end - start))
        textView.layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
        textView.layoutManager.invalidateDisplay(forCharacterRange: range)
        textView.setNeedsDisplay()
    }

    private func updateKeyboardAccessoryState() {
        guard let keyboardAccessoryView else { return }
		let isDivider = isDividerBlock()
        keyboardAccessoryView.setState(
            isBoldSelected: transientBoldMode,
            isItalicSelected: transientItalicMode,
            isFormattingEnabled: style != .code && !isDivider,
			isPasteEnabled: UIPasteboard.general.hasStrings,
			isCodeBlockEnabled: style != .code && !isDivider,
			isCheckboxEnabled: style != .code && !isDivider,
			isDividerEnabled: true
        )
    }
    
    private func applyCodeAttributes(to text: NSMutableAttributedString) {
        let mono = UIFontMetrics(forTextStyle: .body).scaledFont(for: UIFont.monospacedSystemFont(ofSize: 17, weight: .regular))
        text.addAttribute(.font, value: mono, range: NSRange(location: 0, length: text.length))
    }
    
    private struct InlineChange {
        let text: NSAttributedString
        let focusRange: NSRange
    }
    
    private func inlineMarkdownChange(textView: UITextView, replacementText: String, range: NSRange) -> InlineChange? {
        if replacementText.count != 1 { return nil }
        guard replacementText == "`" || replacementText == "_" || replacementText == "*" || replacementText == "~" else {
            return nil
        }
        
        let replacedAttributedText = NSMutableAttributedString(attributedString: textView.attributedText)
        replacedAttributedText.replaceCharacters(in: range, with: replacementText)
        let replacedText = replacedAttributedText.string
        
        var best: (shortcutCount: Int, text: NSMutableAttributedString, focusRange: NSRange)?
        
        for pattern in InlinePattern.all {
            for shortcut in pattern.shortcuts {
                guard replacedText.count >= shortcut.count else { continue }
                guard let endRange = replacedText.findUniqueRangeFor(pattern: shortcut.end, endIndex: replacedText.endIndex) else { continue }
                guard let startRange = replacedText.findUniqueRangeFor(pattern: shortcut.start, endIndex: endRange.lowerBound) else { continue }
                
                let endNSRange = NSRange(endRange, in: replacedText)
                let startNSRange = NSRange(startRange, in: replacedText)
                
                let finalText = NSMutableAttributedString(attributedString: replacedAttributedText)
                finalText.replaceCharacters(in: endNSRange, with: "")
                finalText.replaceCharacters(in: startNSRange, with: "")
                
                let finalRange = NSRange(
                    location: startNSRange.location,
                    length: endNSRange.location - startNSRange.location - startNSRange.length
                )
                
                applyMarkup(pattern: pattern, to: finalText, range: finalRange, baseFont: textView.font)
                
                let focusRange = NSRange(location: finalRange.upperBound, length: 0)
                let candidate = (shortcutCount: shortcut.count, text: finalText, focusRange: focusRange)
                
                if let currentBest = best {
                    if shortcut.count < currentBest.shortcutCount {
                        best = candidate
                    }
                } else {
                    best = candidate
                }
            }
        }
        
        guard let best else { return nil }
        return InlineChange(text: best.text, focusRange: best.focusRange)
    }
    
    private func applyMarkup(pattern: InlinePattern, to text: NSMutableAttributedString, range: NSRange, baseFont: UIFont?) {
        let font = baseFont ?? UIFont.preferredFont(forTextStyle: .body)
        switch pattern.kind {
        case .keyboard:
            let mono = UIFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
            text.addAttribute(.font, value: mono, range: range)
            text.addAttribute(.appInlineCode, value: true, range: range)
        case .italic:
            text.addAttribute(.font, value: font.withTraits(.traitItalic), range: range)
            text.addAttribute(.appInlineItalic, value: true, range: range)
        case .bold:
            text.addAttribute(.font, value: font.withTraits(.traitBold), range: range)
            text.addAttribute(.appInlineBold, value: true, range: range)
        case .strikethrough:
            text.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            text.addAttribute(.appInlineStrike, value: true, range: range)
        }
    }
    
    private struct InlineShortcut {
        let start: String
        let end: String
        var count: Int { start.count + end.count }
    }
    
    private enum InlineKind {
        case keyboard
        case italic
        case bold
        case strikethrough
    }
    
    private struct InlinePattern {
        let shortcuts: [InlineShortcut]
        let kind: InlineKind
        
        static let all: [InlinePattern] = [
            InlinePattern(shortcuts: [InlineShortcut(start: "`", end: "`")], kind: .keyboard),
            InlinePattern(shortcuts: [InlineShortcut(start: "_", end: "_"), InlineShortcut(start: "*", end: "*")], kind: .italic),
            InlinePattern(shortcuts: [InlineShortcut(start: "__", end: "__"), InlineShortcut(start: "**", end: "**")], kind: .bold),
            InlinePattern(shortcuts: [InlineShortcut(start: "~~", end: "~~")], kind: .strikethrough)
        ]
    }

	private static func tagColorIndex(for tag: String) -> Int {
		var hash: UInt32 = 2166136261
		for byte in tag.utf8 {
			hash ^= UInt32(byte)
			hash = hash &* 16777619
		}
		return Int(hash % 6) + 1
	}

	private static func tagColor(for tag: String) -> UIColor {
		let idx = tagColorIndex(for: tag)
		return UIColor(named: "tag\(idx)Color", in: .module, compatibleWith: nil) ?? UIColor.secondarySystemBackground
	}

	private static func tagTextColor(for backgroundColor: UIColor) -> UIColor {
		var r: CGFloat = 0
		var g: CGFloat = 0
		var b: CGFloat = 0
		var a: CGFloat = 0
		guard backgroundColor.getRed(&r, green: &g, blue: &b, alpha: &a) else {
			return UIColor(named: "secondaryTextColor", in: .module, compatibleWith: nil) ?? UIColor.secondaryLabel
		}

		let luminance = (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
		if luminance < 0.42 {
			return UIColor.white.withAlphaComponent(0.90)
		}
		return backgroundColor.darker(by: 55) ?? (UIColor(named: "secondaryTextColor", in: .module, compatibleWith: nil) ?? UIColor.secondaryLabel)
	}

	private func baseTextColor() -> UIColor {
		UIColor(named: "primaryTextColor", in: .module, compatibleWith: nil) ?? UIColor.label
	}

	private func applyBaseTextAttributesIfNeeded() {
		let baseColor = baseTextColor()
		if textView.textColor != baseColor {
			textView.textColor = baseColor
		}

		let current = textView.attributedText ?? NSAttributedString(string: "")
		guard current.length > 0 else { return }
		let selection = textView.selectedRange

		let updated = NSMutableAttributedString(attributedString: current)
		let full = NSRange(location: 0, length: updated.length)

		var needsUpdate = false
		updated.enumerateAttribute(.foregroundColor, in: full, options: []) { value, range, _ in
			if value == nil {
				updated.addAttribute(.foregroundColor, value: baseColor, range: range)
				needsUpdate = true
			}
		}
		guard needsUpdate else { return }

		isApplyingBaseTextAttributes = true
		textView.attributedText = updated
		let clampedLocation = min(max(selection.location, 0), updated.length)
		let clampedLength = min(max(selection.length, 0), max(updated.length - clampedLocation, 0))
		let clamped = NSRange(location: clampedLocation, length: clampedLength)
		if textView.selectedRange != clamped {
			textView.selectedRange = clamped
		}
		isApplyingBaseTextAttributes = false
	}

	private func applyInlineTagAttributesIfNeeded(preservingSelection selection: NSRange) {
		guard style != .code else { return }
		guard let current = textView.attributedText else { return }
		guard current.length > 0 else { return }

		let updated = NSMutableAttributedString(attributedString: current)
		let fullRange = NSRange(location: 0, length: updated.length)

		var rangesToClear: [NSRange] = []
		updated.enumerateAttribute(.appInlineTagName, in: fullRange, options: []) { value, range, _ in
			if value != nil {
				rangesToClear.append(range)
			}
		}
		for range in rangesToClear {
			updated.removeAttribute(.backgroundColor, range: range)
			updated.removeAttribute(.underlineStyle, range: range)
			updated.removeAttribute(.underlineColor, range: range)
			updated.removeAttribute(.foregroundColor, range: range)
			updated.removeAttribute(.appInlineTagName, range: range)
			updated.removeAttribute(.appInlineTagFinal, range: range)
		}

		let ns = updated.string as NSString
		let terminators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
		let matches = BlockCell.tagRegex.matches(in: updated.string, options: [], range: NSRange(location: 0, length: ns.length))
		for match in matches {
			guard match.numberOfRanges > 1 else { continue }
			let full = match.range(at: 0)
			let tag = ns.substring(with: match.range(at: 1))

			let end = full.location + full.length
			let isFinal: Bool = {
				if !textView.isFirstResponder { return true }
				if end < ns.length {
					let next = ns.substring(with: NSRange(location: end, length: 1))
					return next.unicodeScalars.allSatisfy { terminators.contains($0) }
				}
				let isCursorInsideTag = selection.location >= full.location && selection.location <= (full.location + full.length)
				return !isCursorInsideTag
			}()

			let color = BlockCell.tagColor(for: tag)
			let textColor = BlockCell.tagTextColor(for: color)
			if isFinal {
				updated.addAttribute(.backgroundColor, value: color.withAlphaComponent(0.80), range: full)
			} else {
				updated.addAttribute(.backgroundColor, value: color.withAlphaComponent(0.36), range: full)
				updated.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: full)
				updated.addAttribute(.underlineColor, value: color.withAlphaComponent(0.85), range: full)
			}
			updated.addAttribute(.foregroundColor, value: textColor, range: full)
			updated.addAttribute(.appInlineTagName, value: tag, range: full)
			updated.addAttribute(.appInlineTagFinal, value: isFinal, range: full)
		}

		if updated.isEqual(current) { return }

		isApplyingInlineTagAttributes = true
		textView.attributedText = updated
		let clampedLocation = min(max(selection.location, 0), updated.length)
		let clampedLength = min(max(selection.length, 0), max(updated.length - clampedLocation, 0))
		let clamped = NSRange(location: clampedLocation, length: clampedLength)
		if textView.selectedRange != clamped {
			textView.selectedRange = clamped
		}
		isApplyingInlineTagAttributes = false
	}
}

private final class KeyboardActionAccessoryView: UIInputView {
	private let onMedia: () -> Void
	private let onPaste: () -> Void
    private let onHash: () -> Void
    private let onBold: () -> Void
    private let onItalic: () -> Void
	private let onCodeBlock: () -> Void
	private let onCheckbox: () -> Void
	private let onDivider: () -> Void
	private let onLinkToNote: () -> Void
	private let onDone: () -> Void

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    private let hashButton = UIButton(type: .system)
    private let boldButton = UIButton(type: .system)
    private let italicButton = UIButton(type: .system)
	private let codeButton = UIButton(type: .system)
	private let checkboxButton = UIButton(type: .system)
	private let dividerButton = UIButton(type: .system)
	private let linkToNoteButton = UIButton(type: .system)
	private let mediaButton = UIButton(type: .system)
	private let pasteButton = UIButton(type: .system)
	private let doneButton = UIButton(type: .system)

    init(
		onMedia: @escaping () -> Void,
		onPaste: @escaping () -> Void,
        onHash: @escaping () -> Void,
        onBold: @escaping () -> Void,
        onItalic: @escaping () -> Void,
		onCodeBlock: @escaping () -> Void,
		onCheckbox: @escaping () -> Void,
		onDivider: @escaping () -> Void,
		onLinkToNote: @escaping () -> Void,
		onDone: @escaping () -> Void
    ) {
		self.onMedia = onMedia
		self.onPaste = onPaste
        self.onHash = onHash
        self.onBold = onBold
        self.onItalic = onItalic
		self.onCodeBlock = onCodeBlock
		self.onCheckbox = onCheckbox
		self.onDivider = onDivider
		self.onLinkToNote = onLinkToNote
		self.onDone = onDone
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 50), inputViewStyle: .keyboard)
        autoresizingMask = [.flexibleWidth]
        backgroundColor = .clear

        addSubview(blurView)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

		blurView.contentView.addSubview(doneButton)
		doneButton.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			doneButton.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor, constant: -12),
			doneButton.centerYAnchor.constraint(equalTo: blurView.contentView.centerYAnchor),
			doneButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 34)
		])

        blurView.contentView.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: blurView.contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: blurView.contentView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: doneButton.leadingAnchor, constant: -8)
        ])

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.contentInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        scrollView.contentInsetAdjustmentBehavior = .never

        scrollView.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        let centerConstraint = stackView.centerXAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerXAnchor)
        centerConstraint.priority = .defaultLow
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            centerConstraint
        ])

        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 4

		configureButton(mediaButton, title: nil, systemImageName: "photo.on.rectangle", action: #selector(didTapMedia))
		configureButton(pasteButton, title: nil, systemImageName: "doc.on.clipboard", action: #selector(didTapPaste))
        configureButton(hashButton, title: "#", systemImageName: nil, action: #selector(didTapHash))
        configureButton(boldButton, title: "B", systemImageName: nil, action: #selector(didTapBold))
        configureButton(italicButton, title: "I", systemImageName: nil, action: #selector(didTapItalic))
		configureButton(codeButton, title: nil, systemImageName: "chevron.left.forwardslash.chevron.right", action: #selector(didTapCodeBlock))
		configureButton(checkboxButton, title: nil, systemImageName: "checkmark.square", action: #selector(didTapCheckbox))
		configureButton(dividerButton, title: nil, systemImageName: "minus", action: #selector(didTapDivider))
		configureButton(linkToNoteButton, title: nil, systemImageName: "drop", action: #selector(didTapLinkToNote))

        let base = UIFont.appSpaceGrotesk(size: 20, weight: .semibold)
        let baseScaled = UIFontMetrics(forTextStyle: .headline).scaledFont(for: base)
        let boldBase = UIFont.appSpaceGrotesk(size: 20, weight: .bold)
        let boldScaled = UIFontMetrics(forTextStyle: .headline).scaledFont(for: boldBase)
        hashButton.titleLabel?.font = baseScaled
        boldButton.titleLabel?.font = baseScaled
        if let italicDescriptor = baseScaled.fontDescriptor.withSymbolicTraits([.traitItalic]) {
            italicButton.titleLabel?.font = UIFont(descriptor: italicDescriptor, size: baseScaled.pointSize)
        } else {
            italicButton.titleLabel?.font = baseScaled
        }
        hashButton.titleLabel?.adjustsFontForContentSizeCategory = true
        boldButton.titleLabel?.adjustsFontForContentSizeCategory = true
        italicButton.titleLabel?.adjustsFontForContentSizeCategory = true

		if let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold) as UIImage.SymbolConfiguration? {
			mediaButton.setPreferredSymbolConfiguration(config, forImageIn: .normal)
			pasteButton.setPreferredSymbolConfiguration(config, forImageIn: .normal)
			codeButton.setPreferredSymbolConfiguration(config, forImageIn: .normal)
			checkboxButton.setPreferredSymbolConfiguration(config, forImageIn: .normal)
			dividerButton.setPreferredSymbolConfiguration(config, forImageIn: .normal)
			linkToNoteButton.setPreferredSymbolConfiguration(config, forImageIn: .normal)
		}

		doneButton.setTitle(String(localized: "note.editor.keyboard.done"), for: .normal)
		doneButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
		doneButton.titleLabel?.adjustsFontForContentSizeCategory = true
		doneButton.setTitleColor(.appAccent, for: .normal)
		doneButton.tintColor = .appAccent
		doneButton.backgroundColor = UIColor.secondarySystemFill
		doneButton.layer.cornerRadius = 12
		doneButton.layer.masksToBounds = true
		doneButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
		doneButton.setContentCompressionResistancePriority(.required, for: .horizontal)
		doneButton.setContentHuggingPriority(.required, for: .horizontal)
		doneButton.addTarget(self, action: #selector(didTapDone), for: .touchUpInside)

		stackView.addArrangedSubview(mediaButton)
        stackView.addArrangedSubview(hashButton)
        stackView.addArrangedSubview(boldButton)
        stackView.addArrangedSubview(italicButton)
		stackView.addArrangedSubview(codeButton)
		stackView.addArrangedSubview(checkboxButton)
		stackView.addArrangedSubview(dividerButton)
		stackView.addArrangedSubview(linkToNoteButton)
		stackView.addArrangedSubview(pasteButton)

        setState(
			isBoldSelected: false,
			isItalicSelected: false,
			isFormattingEnabled: true,
			isPasteEnabled: UIPasteboard.general.hasStrings,
			isCodeBlockEnabled: true,
			isCheckboxEnabled: true,
			isDividerEnabled: true
		)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 50)
    }

    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        CGSize(width: targetSize.width, height: 50)
    }

    func setState(isBoldSelected: Bool, isItalicSelected: Bool, isFormattingEnabled: Bool, isPasteEnabled: Bool, isCodeBlockEnabled: Bool, isCheckboxEnabled: Bool, isDividerEnabled: Bool) {
        boldButton.isEnabled = isFormattingEnabled
        italicButton.isEnabled = isFormattingEnabled
		codeButton.isEnabled = isCodeBlockEnabled
		checkboxButton.isEnabled = isCheckboxEnabled
		dividerButton.isEnabled = isDividerEnabled
		pasteButton.isEnabled = isPasteEnabled
        applySelectionStyle(to: boldButton, selected: isBoldSelected)
        applySelectionStyle(to: italicButton, selected: isItalicSelected)
		applySelectionStyle(to: codeButton, selected: false)
		applySelectionStyle(to: checkboxButton, selected: false)
		applySelectionStyle(to: dividerButton, selected: false)
		applySelectionStyle(to: pasteButton, selected: false)
    }

    private func configureButton(_ button: UIButton, title: String?, systemImageName: String?, action: Selector) {
		if let title {
			button.setTitle(title, for: .normal)
		}
		if let systemImageName {
			button.setImage(UIImage(systemName: systemImageName), for: .normal)
		}
        button.addTarget(self, action: action, for: .touchUpInside)
		if systemImageName != nil, title == nil {
			button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
		} else {
			button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
		}
        button.titleLabel?.textAlignment = .center
        button.contentHorizontalAlignment = .center
        button.contentVerticalAlignment = .center
        button.layer.cornerRadius = 12
        button.layer.masksToBounds = true
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        applySelectionStyle(to: button, selected: false)
    }

    private func applySelectionStyle(to button: UIButton, selected: Bool) {
        if selected {
            button.backgroundColor = UIColor.secondarySystemFill
            button.tintColor = UIColor.label
            button.setTitleColor(UIColor.label, for: .normal)
        } else {
            button.backgroundColor = UIColor.clear
            button.tintColor = UIColor.label
            button.setTitleColor(UIColor.label, for: .normal)
        }
        if !button.isEnabled {
            button.backgroundColor = UIColor.clear
            button.setTitleColor(UIColor.secondaryLabel, for: .normal)
        }
    }

    @objc
	private func didTapMedia() {
		onMedia()
	}

	@objc
	private func didTapPaste() {
		onPaste()
	}

	@objc
    private func didTapHash() {
        onHash()
    }

    @objc
    private func didTapBold() {
        onBold()
    }

    @objc
    private func didTapItalic() {
        onItalic()
    }

	@objc
	private func didTapCodeBlock() {
		onCodeBlock()
	}

	@objc
	private func didTapCheckbox() {
		onCheckbox()
	}

	@objc
	private func didTapDivider() {
		onDivider()
	}

	@objc
	private func didTapLinkToNote() {
		onLinkToNote()
	}

	@objc
	private func didTapDone() {
		onDone()
	}
}

private extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        let newTraits = fontDescriptor.symbolicTraits.union(traits)
        guard let descriptor = fontDescriptor.withSymbolicTraits(newTraits) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

private extension StringProtocol {
    func findUniqueRangeFor(pattern: String, endIndex: String.Index) -> Range<String.Index>? {
        guard let firstRange = range(of: pattern, options: [.backwards], range: startIndex..<endIndex) else {
            return nil
        }
        
        guard let secondRange = range(of: pattern, options: [.backwards], range: startIndex..<firstRange.lowerBound) else {
            return firstRange
        }
        
        guard distance(from: secondRange.upperBound, to: firstRange.lowerBound) != 0 else {
            return nil
        }
        
        return firstRange
    }
}

private extension BlockCell {
	func applyInlineChecklistAttributesIfNeeded(preservingSelection selection: NSRange) {
		guard let current = textView.attributedText else { return }
		if current.length == 0 {
			guard style == .checkbox else { return }
			let baseFont = textView.font ?? UIFont.preferredFont(forTextStyle: .body)
			let seed = NSMutableAttributedString(string: "[ ] ", attributes: [.font: baseFont])
			let tinyFont = baseFont.withSize(0.1)
			let tinyCount = min(3, seed.length)
			if tinyCount > 0 {
				let r = NSRange(location: 0, length: tinyCount)
				seed.addAttribute(.font, value: tinyFont, range: r)
				seed.addAttribute(.foregroundColor, value: UIColor.clear, range: r)
				seed.addAttribute(.appInlineCheckboxHidden, value: true, range: r)
			}
			if seed.length >= 4 {
				let r = NSRange(location: 3, length: 1)
				seed.addAttribute(.font, value: baseFont, range: r)
				seed.addAttribute(.foregroundColor, value: UIColor.clear, range: r)
				seed.addAttribute(.appInlineCheckboxHidden, value: true, range: r)
			}
			isApplyingInlineChecklistAttributes = true
			textView.attributedText = seed
			textView.selectedRange = NSRange(location: 4, length: 0)
			var typing = textView.typingAttributes
			typing[.font] = baseFont
			typing.removeValue(forKey: .foregroundColor)
			textView.typingAttributes = typing
			checkboxButton.setImage(UIImage(systemName: "square"), for: .normal)
			checkboxButton.tintColor = .appAccent
			isApplyingInlineChecklistAttributes = false
			return
		}

		let updated = NSMutableAttributedString(attributedString: current)
		let fullRange = NSRange(location: 0, length: updated.length)
		var newSelection = selection

		var rangesToClearHidden: [NSRange] = []
		updated.enumerateAttribute(.appInlineCheckboxHidden, in: fullRange, options: []) { value, range, _ in
			if value != nil {
				rangesToClearHidden.append(range)
			}
		}
		for range in rangesToClearHidden {
			updated.removeAttribute(.font, range: range)
			updated.removeAttribute(.foregroundColor, range: range)
			updated.removeAttribute(.appInlineCheckboxHidden, range: range)
		}

		var rangesToClearDimmed: [NSRange] = []
		updated.enumerateAttribute(.appInlineCheckboxDimmed, in: fullRange, options: []) { value, range, _ in
			if value != nil {
				rangesToClearDimmed.append(range)
			}
		}
		for range in rangesToClearDimmed {
			updated.removeAttribute(.foregroundColor, range: range)
			updated.removeAttribute(.appInlineCheckboxDimmed, range: range)
		}

		var rangesToClearAutoStrike: [NSRange] = []
		updated.enumerateAttribute(.appInlineCheckboxAutoStrike, in: fullRange, options: []) { value, range, _ in
			if value != nil {
				rangesToClearAutoStrike.append(range)
			}
		}
		for range in rangesToClearAutoStrike {
			updated.removeAttribute(.strikethroughStyle, range: range)
			updated.removeAttribute(.appInlineCheckboxAutoStrike, range: range)
		}

		guard style == .checkbox else {
			if updated.isEqual(current) { return }
			isApplyingInlineChecklistAttributes = true
			textView.attributedText = updated
			textView.selectedRange = selection
			isApplyingInlineChecklistAttributes = false
			return
		}

		if let baseFont = textView.font {
			var missingFontRanges: [NSRange] = []
			updated.enumerateAttribute(.font, in: NSRange(location: 0, length: updated.length), options: []) { value, range, _ in
				if value == nil {
					missingFontRanges.append(range)
				}
			}
			for range in missingFontRanges {
				updated.addAttribute(.font, value: baseFont, range: range)
			}
		}

		let ns = updated.string as NSString
		let prefixLen = 4

		if ns.length >= 6, (ns.hasPrefix("- ") || ns.hasPrefix("* ")) {
			let checkboxPrefix = ns.substring(with: NSRange(location: 2, length: 4)).lowercased()
			if checkboxPrefix == "[ ] " || checkboxPrefix == "[x] " {
				updated.deleteCharacters(in: NSRange(location: 0, length: 2))
				newSelection = NSRange(location: max(newSelection.location - 2, 0), length: 0)
			}
		}

		let hasCheckboxPrefix: Bool = {
			let ns2 = updated.string as NSString
			guard ns2.length >= prefixLen else { return false }
			let prefix = ns2.substring(with: NSRange(location: 0, length: prefixLen)).lowercased()
			return prefix == "[ ] " || prefix == "[x] "
		}()

		if hasCheckboxPrefix == false {
			updated.replaceCharacters(in: NSRange(location: 0, length: 0), with: "[ ] ")
			newSelection = NSRange(location: selection.location + prefixLen, length: 0)
		}

		let ns2 = updated.string as NSString
		let isChecked: Bool = {
			guard ns2.length >= 2 else { return false }
			return ns2.substring(with: NSRange(location: 1, length: 1)).lowercased() == "x"
		}()

		let prefixRange = NSRange(location: 0, length: min(prefixLen, updated.length))

		if prefixRange.length > 0 {
			let baseFont = textView.font ?? UIFont.systemFont(ofSize: 17)
			let tinyFont = baseFont.withSize(0.1)

			let tinyCount = min(3, prefixRange.length)
			if tinyCount > 0 {
				let r = NSRange(location: 0, length: tinyCount)
				updated.addAttribute(.font, value: tinyFont, range: r)
				updated.addAttribute(.foregroundColor, value: UIColor.clear, range: r)
				updated.addAttribute(.appInlineCheckboxHidden, value: true, range: r)
			}

			if prefixRange.length >= 4 {
				let r = NSRange(location: 3, length: 1)
				updated.addAttribute(.font, value: baseFont, range: r)
				updated.addAttribute(.foregroundColor, value: UIColor.clear, range: r)
				updated.addAttribute(.appInlineCheckboxHidden, value: true, range: r)
			}
		}

		if updated.length > prefixLen {
			let visibleRange = NSRange(location: prefixLen, length: updated.length - prefixLen)
			if isChecked {
				updated.enumerateAttributes(in: visibleRange, options: []) { attrs, range, _ in
					if attrs[.link] != nil { return }
					if attrs[.appInlineTagName] != nil { return }
					if attrs[.strikethroughStyle] == nil {
						updated.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
						updated.addAttribute(.appInlineCheckboxAutoStrike, value: true, range: range)
					}
				}
			}
		}

		let imageName = isChecked ? "checkmark.square.fill" : "square"
		checkboxButton.setImage(UIImage(systemName: imageName), for: .normal)
		checkboxButton.tintColor = .appAccent

		let clampedLoc = min(max(newSelection.location, prefixLen), updated.length)
		newSelection = NSRange(location: clampedLoc, length: 0)

		let baseFont = textView.font ?? UIFont.preferredFont(forTextStyle: .body)
		var typing = textView.typingAttributes
		typing[.font] = baseFont
		typing.removeValue(forKey: .foregroundColor)

		if updated.isEqual(current) {
			if textView.selectedRange != newSelection {
				textView.selectedRange = newSelection
			}
			textView.typingAttributes = typing
			return
		}

		isApplyingInlineChecklistAttributes = true
		textView.attributedText = updated
		textView.selectedRange = newSelection
		textView.typingAttributes = typing
		isApplyingInlineChecklistAttributes = false
	}

	func applyInlineLinkAttributesIfNeeded(preservingSelection selection: NSRange) {
		guard style != .code else { return }
		guard let current = textView.attributedText else { return }
		guard current.length > 0 else { return }

		let updated = NSMutableAttributedString(attributedString: current)
		let fullRange = NSRange(location: 0, length: updated.length)
		var newSelection = selection

		func remapSelectionForReplacement(in replacedRange: NSRange, replacementLength: Int) {
			let replacedUpperBound = replacedRange.location + replacedRange.length
			let delta = replacementLength - replacedRange.length

			func remap(_ location: Int) -> Int {
				if location <= replacedRange.location { return location }
				if location >= replacedUpperBound { return location + delta }
				let offset = location - replacedRange.location
				return replacedRange.location + min(offset, replacementLength)
			}

			let start = remap(newSelection.location)
			let end = remap(newSelection.location + newSelection.length)
			newSelection = NSRange(location: start, length: max(0, end - start))
		}

		func noteId(from url: URL) -> String? {
			guard url.scheme?.lowercased() == "konuq" else { return nil }
			guard url.host?.lowercased() == "note" else { return nil }
			let parts = url.pathComponents.filter { $0 != "/" }
			guard let first = parts.first, !first.isEmpty else { return nil }
			return first
		}

		var rangesToClear: [NSRange] = []
		updated.enumerateAttribute(.appInlineLinkUrl, in: fullRange, options: []) { value, range, _ in
			if value != nil {
				rangesToClear.append(range)
			}
		}
		for range in rangesToClear {
			if updated.attribute(.appInlineLinkHidden, at: max(min(range.location, updated.length - 1), 0), effectiveRange: nil) != nil {
				updated.removeAttribute(.font, range: range)
				updated.removeAttribute(.appInlineLinkHidden, range: range)
			}
			updated.removeAttribute(.link, range: range)
			updated.removeAttribute(.foregroundColor, range: range)
			updated.removeAttribute(.underlineStyle, range: range)
			updated.removeAttribute(.underlineColor, range: range)
			updated.removeAttribute(.appInlineLinkUrl, range: range)
		}

		updated.enumerateAttribute(.appInlineNoteLinkId, in: NSRange(location: 0, length: updated.length), options: []) { value, range, _ in
			guard let value else { return }
			let id: String? = {
				if let s = value as? String { return s }
				if let n = value as? NSNumber { return n.stringValue }
				return nil
			}()
			guard let id, !id.isEmpty else { return }
			guard let url = URL(string: "konuq://note/\(id)") else { return }
			updated.addAttribute(.link, value: url, range: range)
			updated.addAttribute(.appInlineLinkUrl, value: url.absoluteString, range: range)
		}

		if let baseFont = textView.font {
			var missingFontRanges: [NSRange] = []
			updated.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
				if value == nil {
					missingFontRanges.append(range)
				}
			}
			for range in missingFontRanges {
				updated.addAttribute(.font, value: baseFont, range: range)
			}
		}

		let ns = updated.string as NSString
		let matches = BlockCell.markdownLinkRegex.matches(in: updated.string, options: [], range: NSRange(location: 0, length: ns.length))
		for match in matches.reversed() {
			guard match.numberOfRanges >= 3 else { continue }
			let full = match.range(at: 0)
			let labelRange = match.range(at: 1)
			let urlRange = match.range(at: 2)
			guard labelRange.location != NSNotFound, labelRange.length > 0 else { continue }
			guard urlRange.location != NSNotFound, urlRange.length > 0 else { continue }

			let urlString = ns.substring(with: urlRange)
			let url = URL(string: urlString) ?? URL(string: "https://\(urlString)")
			guard let url else { continue }

			let replacement = NSMutableAttributedString(attributedString: updated.attributedSubstring(from: labelRange))
			let replacementRange = NSRange(location: full.location, length: replacement.length)
			updated.replaceCharacters(in: full, with: replacement)
			updated.addAttribute(.link, value: url, range: replacementRange)
			updated.addAttribute(.appInlineLinkUrl, value: url.absoluteString, range: replacementRange)
			if let id = noteId(from: url) {
				updated.addAttribute(.appInlineNoteLinkId, value: id, range: replacementRange)
			}
			remapSelectionForReplacement(in: full, replacementLength: replacement.length)
		}

		let detected = BlockCell.linkDetector.matches(in: updated.string, options: [], range: NSRange(location: 0, length: updated.length))
		for match in detected {
			guard let url = match.url else { continue }
			let range = match.range
			guard range.location != NSNotFound, range.length > 0 else { continue }
			if updated.attribute(.appInlineLinkUrl, at: range.location, effectiveRange: nil) != nil { continue }
			updated.addAttribute(.link, value: url, range: range)
			updated.addAttribute(.appInlineLinkUrl, value: url.absoluteString, range: range)
		}

		if updated.isEqual(current) { return }

		isApplyingInlineLinkAttributes = true
		textView.attributedText = updated
		let clampedLocation = min(max(newSelection.location, 0), updated.length)
		let clampedLength = min(max(newSelection.length, 0), max(updated.length - clampedLocation, 0))
		let clamped = NSRange(location: clampedLocation, length: clampedLength)
		if textView.selectedRange != clamped {
			textView.selectedRange = clamped
		}
		isApplyingInlineLinkAttributes = false
	}
}

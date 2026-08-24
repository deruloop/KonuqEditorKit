import UIKit
import QuartzCore
import AVKit
import Photos
import PhotosUI
import UniformTypeIdentifiers

private extension NSAttributedString.Key {
	static let appInlineBold = NSAttributedString.Key("app.inline.bold")
	static let appInlineItalic = NSAttributedString.Key("app.inline.italic")
	static let appInlineCode = NSAttributedString.Key("app.inline.code")
	static let appInlineStrike = NSAttributedString.Key("app.inline.strike")
	static let appInlineLinkUrl = NSAttributedString.Key("app.inline.link.url")
	static let appInlineNoteLinkId = NSAttributedString.Key("app.inline.note.link.id")
}

final class BlocksEditorViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITableViewDragDelegate, UITableViewDropDelegate, UIGestureRecognizerDelegate, BlockCellDelegate, MediaBlockCellDelegate, PHPickerViewControllerDelegate {
    private let tableView = UITableView(frame: .zero, style: .plain)
    
    private let initialEmptyStyle: TextStyle
    private let document = Document()
    private lazy var service = BlockActionService(document: document)
    private let toggleStorage = ToggleStorage()
    private lazy var keyboardHandler = KeyboardActionHandler(document: document, service: service, toggleStorage: toggleStorage)
    
    private var pendingFocusBlockId: String?
    /// Caret placement used when pendingFocusBlockId is focused. Enter/split sets
    /// .start so the caret sits before the carried text; everything else keeps .end.
    private var pendingFocusCursor: FocusCursorPlacement = .end
	private var pendingMediaInsertAfterBlockId: String?
	private var pendingFullScreenImageReference: String?
	private var pendingFullScreenImageAttempts = 0
	private var pendingFullScreenVideoReference: String?
	private var pendingFullScreenVideoAttempts = 0
	private var keyboardObservers: [NSObjectProtocol] = []
    var autoFocusOnAppear: Bool = true
    private var isSelectionMode = false
    /// Anchor row of an in-progress "drag text selection beyond the row" gesture
    /// that auto-switched into multi-block selection.
    private var dragSelectionAnchorRow: Int?
    /// True while dictation text is being applied programmatically, so the manual-edit
    /// interrupt logic in didChangeText doesn't fire (it would restart the recognizer
    /// on every partial result and kill the session).
    private var isApplyingDictationText = false

    /// Mac runtime: hosts the keyboard accessory bar docked at the bottom of the
    /// editor pane (inputAccessoryView would span the whole window there).
    private let accessoryDockContainer = UIView()
    private var isAccessoryDocked = false

    /// Dedicated undo manager for block-level operations (delete/restore). Text
    /// editing keeps using each UITextView's own undo manager; this one is active
    /// while the controller is first responder (i.e. in block-selection mode).
    private let blockUndoManager = UndoManager()
    override var undoManager: UndoManager? { blockUndoManager }
    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        guard isSelectionMode else { return nil }
        let copy = UIKeyCommand(input: "c", modifierFlags: .command, action: #selector(handleSelectionCopyCommand))
        let cut = UIKeyCommand(input: "x", modifierFlags: .command, action: #selector(handleSelectionCutCommand))
        // Plain backspace: in selection mode no text view is editing, so it can't
        // clash with typing.
        let del = UIKeyCommand(input: "\u{8}", modifierFlags: [], action: #selector(handleSelectionDeleteCommand))
        let selectAll = UIKeyCommand(input: "a", modifierFlags: .command, action: #selector(handleSelectionSelectAllCommand))
        let undo = UIKeyCommand(input: "z", modifierFlags: .command, action: #selector(handleUndoCommand))
        let redo = UIKeyCommand(input: "z", modifierFlags: [.command, .shift], action: #selector(handleRedoCommand))
        for command in [copy, cut, del, selectAll, undo, redo] {
            if #available(iOS 15.0, *) { command.wantsPriorityOverSystemBehavior = true }
        }
        return [copy, cut, del, selectAll, undo, redo]
    }

    // The shortcuts mirror the selection-toolbar buttons exactly: act, exit
    // selection mode, then fire the same feedback the buttons trigger (toast).
    @objc private func handleSelectionCopyCommand() {
        copySelectedBlocksToPasteboard()
        setSelectionMode(false)
        onCopyShortcut?()
    }
    @objc private func handleSelectionCutCommand() {
        cutSelectedBlocksToPasteboard()
        setSelectionMode(false)
        onCutShortcut?()
    }
    @objc private func handleSelectionDeleteCommand() {
        deleteSelectedBlocks()
        if isSelectionMode { setSelectionMode(false) }
    }
    @objc private func handleSelectionSelectAllCommand() { selectAllBlocks() }
    @objc private func handleUndoCommand() { blockUndoManager.undo() }
    @objc private func handleRedoCommand() { blockUndoManager.redo() }
	private var blocksChangedWorkItem: DispatchWorkItem?
	private var keyboardHeight: CGFloat = 0
	private var dictationTargetBlockId: String?
	private var dictationPrefix: NSAttributedString?
	private var dictationRange: NSRange?
	private var persistentInlineBoldMode = false
	private var persistentInlineItalicMode = false
    
    var onSelectionStateChange: ((Bool, Int) -> Void)?
    var onBlocksChanged: (([EditorBlockSnapshot]) -> Void)?
	var onLinkToNote: (() -> Void)?
	var onOpenURL: ((URL) -> Void)?
	var onInsertLocation: (() -> Void)?
	/// Fired when the user manually edits the dictation target block mid-recording,
	/// so the speech controller can reset its cumulative transcript.
	var onDictationInterrupted: (() -> Void)?
	/// Feedback hooks fired by the ⌘C/⌘X selection shortcuts, wired to the same
	/// closures as the selection-toolbar buttons (e.g. the "Copied" toast).
	var onCopyShortcut: (() -> Void)?
	var onCutShortcut: (() -> Void)?

	var keyboardTrailingButtonMode: KeyboardTrailingButtonMode {
		if onLinkToNote != nil { return .linkToNote }
		return .hidden
	}

	var keyboardLocationButtonEnabled: Bool { onInsertLocation != nil }

    init(initialEmptyStyle: TextStyle = .text) {
        self.initialEmptyStyle = initialEmptyStyle
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

	deinit {
		let nc = NotificationCenter.default
		for token in keyboardObservers {
			nc.removeObserver(token)
		}
	}
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .systemBackground
        title = "Note"
        
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.keyboardDismissMode = .interactive
        tableView.estimatedRowHeight = 44
        tableView.rowHeight = UITableView.automaticDimension
        tableView.register(BlockCell.self, forCellReuseIdentifier: BlockCell.reuseId)
		tableView.register(MediaBlockCell.self, forCellReuseIdentifier: MediaBlockCell.reuseId)
        tableView.allowsSelection = false
        tableView.allowsMultipleSelection = false
        tableView.dragInteractionEnabled = true
        tableView.dragDelegate = self
        tableView.dropDelegate = self
		tableView.contentInsetAdjustmentBehavior = .automatic
        
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        accessoryDockContainer.translatesAutoresizingMaskIntoConstraints = false
        accessoryDockContainer.isHidden = true
        view.addSubview(accessoryDockContainer)
        NSLayoutConstraint.activate([
            accessoryDockContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            accessoryDockContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            accessoryDockContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        
        if document.order.isEmpty {
			let initial = Block(content: .text(TextBlock(text: NSAttributedString(string: ""), style: initialEmptyStyle)))
			document.setBlock(initial)
			if autoFocusOnAppear {
				pendingFocusBlockId = initial.id
			} else {
				pendingFocusBlockId = nil
			}
        }
        
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.delegate = self
        longPress.minimumPressDuration = 0.25
        longPress.allowableMovement = 8
        tableView.addGestureRecognizer(longPress)

        // Dragging a text selection past the row's bounds auto-switches into
        // multi-block selection (see handleSelectionEscapePan).
        let selectionPan = UIPanGestureRecognizer(target: self, action: #selector(handleSelectionEscapePan(_:)))
        selectionPan.delegate = self
        selectionPan.cancelsTouchesInView = false
        tableView.addGestureRecognizer(selectionPan)

        let backgroundTap = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap(_:)))
        backgroundTap.delegate = self
        backgroundTap.cancelsTouchesInView = false
        tableView.addGestureRecognizer(backgroundTap)

		let nc = NotificationCenter.default
		keyboardObservers.append(
			nc.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] notification in
				guard let self else { return }
				let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0
				DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
					self?.attemptPresentPendingFullScreenImage()
					self?.attemptPresentPendingFullScreenVideo()
				}
			}
		)
		keyboardObservers.append(
			nc.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) { [weak self] _ in
				self?.attemptPresentPendingFullScreenImage()
				self?.attemptPresentPendingFullScreenVideo()
			}
		)
		keyboardObservers.append(
			nc.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] notification in
				guard let self else { return }
				guard let frame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
				let endFrame = self.view.convert(frame, from: nil)
				let height = max(0, self.view.bounds.maxY - endFrame.minY)
				self.keyboardHeight = height
				self.updateEditorInsets()
			}
		)
        
        notifySelectionState()
    }

	private func isMacRuntime() -> Bool {
		if #available(iOS 14.0, *) { return ProcessInfo.processInfo.isiOSAppOnMac }
		return false
	}

	@objc private func handleCommandBold() {
		guard isSelectionMode == false else { return }
		let root: UIView = view.window ?? view
		guard let textView = findFirstResponder(in: root) as? UITextView else { return }
		guard let cell = enclosingBlockCell(for: textView) else { return }
		cell.toggleBold()
	}

	@objc private func handleCommandItalic() {
		guard isSelectionMode == false else { return }
		let root: UIView = view.window ?? view
		guard let textView = findFirstResponder(in: root) as? UITextView else { return }
		guard let cell = enclosingBlockCell(for: textView) else { return }
		cell.toggleItalic()
	}

	@objc private func handleCommandMakeTextBlock() { applyBlockStyle(.text) }
	@objc private func handleCommandMakeTitleBlock() { applyBlockStyle(.title) }
	@objc private func handleCommandMakeHeaderBlock() { applyBlockStyle(.description) }
	@objc private func handleCommandMakeParagraphBlock() { applyBlockStyle(.heading3) }

	private func applyBlockStyle(_ style: TextStyle) {
		guard isSelectionMode == false else { return }
		let root: UIView = view.window ?? view
		guard let textView = findFirstResponder(in: root) as? UITextView else { return }
		guard let cell = enclosingBlockCell(for: textView) else { return }
		let text = textView.attributedText ?? NSAttributedString(string: "")

		_ = keyboardHandler.handle(blockId: cell.blockId, action: .markdownTurnInto(style: style, text: text))

		if let row = document.order.firstIndex(of: cell.blockId),
		   let block = document.block(id: cell.blockId),
		   case .text(let textBlock) = block.content {
			cell.configure(
				blockId: cell.blockId,
				text: textBlock.text,
				style: textBlock.style,
				isFirstBlock: row == 0
			)
			tableView.beginUpdates()
			tableView.endUpdates()
		}

		scheduleBlocksChanged(immediate: true)
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		updateEditorInsets()
	}

	private func updateEditorInsets() {
		let topInset: CGFloat = 14
		let extra = max(220, view.bounds.height * 0.35)
		let bottomInset = keyboardHeight + extra
		if tableView.contentInset.top != topInset {
			tableView.contentInset.top = topInset
		}
		if tableView.contentInset.bottom != bottomInset {
			tableView.contentInset.bottom = bottomInset
		}
		if tableView.scrollIndicatorInsets.top != topInset {
			tableView.scrollIndicatorInsets.top = topInset
		}
		if tableView.scrollIndicatorInsets.bottom != keyboardHeight {
			tableView.scrollIndicatorInsets.bottom = keyboardHeight
		}
	}
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
		reapplyInlineAttributesForVisibleCells()
        if autoFocusOnAppear {
            focusIfNeeded()
        } else {
            pendingFocusBlockId = nil
        }
    }

	private func reapplyInlineAttributesForVisibleCells() {
		for cell in tableView.visibleCells {
			(cell as? BlockCell)?.didExternallySetText()
		}
	}
    
    func setSelectionMode(_ enabled: Bool) {
        isSelectionMode = enabled
        tableView.allowsSelection = enabled
        tableView.allowsMultipleSelection = enabled
        tableView.dragInteractionEnabled = !enabled
        if !enabled, let selected = tableView.indexPathsForSelectedRows {
            for ip in selected {
                tableView.deselectRow(at: ip, animated: false)
            }
        }
		for cell in tableView.visibleCells {
			(cell as? BlockSelectableCell)?.isSelectionMode = enabled
		}
        // Become first responder so ⌘C / ⌘⌫ / ⌘Z reach this controller in
        // selection mode (no text view is editing then).
        if enabled {
            becomeFirstResponder()
        } else {
            resignFirstResponder()
        }
        notifySelectionState()
    }

	func selectAllBlocks() {
		guard isSelectionMode else { return }
		guard document.order.isEmpty == false else { return }
		tableView.endEditing(true)

		for row in 0..<document.order.count {
			tableView.selectRow(at: IndexPath(row: row, section: 0), animated: false, scrollPosition: .none)
		}
		notifySelectionState()
	}

	func focusLastTextBlock() {
		let id = document.order.reversed().first(where: { blockId in
			guard let block = document.block(id: blockId) else { return false }
			if case .text = block.content { return true }
			return false
		})
		guard let id else { return }
		pendingFocusBlockId = id
		focus(blockId: id)
	}

	private func enclosingBlockCell(for view: UIView) -> BlockCell? {
		var current: UIView? = view
		while let c = current {
			if let cell = c as? BlockCell { return cell }
			current = c.superview
		}
		return nil
	}

	private func lastTextBlockId() -> String? {
		document.order.reversed().first(where: { blockId in
			guard let block = document.block(id: blockId) else { return false }
			if case .text = block.content { return true }
			return false
		})
	}

	private func dictationFont(for style: TextStyle) -> UIFont {
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
			return scaled(UIFont.monospacedSystemFont(ofSize: 17, weight: .regular), textStyle: .body)
		case .listBullet, .toggle, .toggleHeader, .checkbox, .text:
			return scaled(UIFont.appDMSans(size: 17, weight: .regular), textStyle: .body)
		}
	}

	private func updateTextBlockUI(blockId: String) {
		guard let row = document.order.firstIndex(of: blockId) else { return }
		guard let block = document.block(id: blockId) else { return }
		guard case .text(let textBlock) = block.content else { return }

		let indexPath = IndexPath(row: row, section: 0)
		if let cell = tableView.cellForRow(at: indexPath) as? BlockCell {
			cell.configure(
				blockId: blockId,
				text: textBlock.text,
				style: textBlock.style,
				isFirstBlock: row == 0
			)
		}
		tableView.beginUpdates()
		tableView.endUpdates()
	}

	func insertNewBlockAtCursor() {
		guard isSelectionMode == false else { return }
		let root: UIView = view.window ?? view

		guard let textView = findFirstResponder(in: root) as? UITextView else {
			let afterId = dictationTargetBlockId ?? lastTextBlockId()
			let new = Block(content: .text(TextBlock(text: NSAttributedString(string: ""), style: initialEmptyStyle)))
			let newId = document.insert(new, after: afterId)
			if let row = document.order.firstIndex(of: newId) {
				tableView.beginUpdates()
				tableView.insertRows(at: [IndexPath(row: row, section: 0)], with: .none)
				tableView.endUpdates()
			} else {
				tableView.reloadData()
			}
			scheduleBlocksChanged(immediate: true)
			dictationTargetBlockId = newId
			dictationPrefix = NSAttributedString(string: "")
			dictationRange = nil
			return
		}

		guard let cell = enclosingBlockCell(for: textView) else {
			textView.insertText("\n")
			resetDictationState()
			return
		}

		let range = textView.selectedRange
		if let action = KeyboardAction.build(attributedText: textView.attributedText, range: range, replacement: "\n") {
			blockCell(cell, didTrigger: action)
		} else {
			textView.insertText("\n")
		}
		resetDictationState()
	}

	/// Inserts the given snapshots as ordinary editor rows after the block that currently
	/// holds the cursor (or at the end when nothing is focused).
	func insertBlocksAtCursor(_ snapshots: [EditorBlockSnapshot]) {
		guard isSelectionMode == false, !snapshots.isEmpty else { return }

		let root: UIView = view.window ?? view
		var afterId: String? = lastTextBlockId()
		if let textView = findFirstResponder(in: root) as? UITextView,
		   let cell = enclosingBlockCell(for: textView) {
			afterId = cell.blockId
			textView.resignFirstResponder()
		}

		let newBlocks: [Block] = snapshots
			.sorted { $0.position < $1.position }
			.map { block(from: $0) }

		var previousId = afterId
		var lastInsertedTextId: String?
		for block in newBlocks {
			document.insert(block, after: previousId)
			previousId = block.id
			if case .text = block.content { lastInsertedTextId = block.id }
		}

		tableView.reloadData()
		scheduleBlocksChanged(immediate: true)

		if let focusId = lastInsertedTextId ?? previousId, let row = document.order.firstIndex(of: focusId) {
			tableView.scrollToRow(at: IndexPath(row: row, section: 0), at: .middle, animated: true)
		}
		// Refocus the editor: we resigned the first responder above, and without this
		// the keyboard stays dismissed after a paste. Caret at the end of the last
		// pasted text block.
		if let focusId = lastInsertedTextId {
			pendingFocusBlockId = focusId
			pendingFocusCursor = .end
			tableView.layoutIfNeeded()
			focusIfNeeded()
		}
	}

	private func block(from snapshot: EditorBlockSnapshot) -> Block {
		switch snapshot.kind {
		case let .text(text, style):
			let attributed = style == .code ? NSAttributedString(string: text) : parseInlineMarkdown(text)
			return Block(id: snapshot.id, content: .text(TextBlock(text: attributed, style: style)), parentId: nil, children: [])
		case let .image(reference, displayStyle):
			return Block(id: snapshot.id, content: .media(MediaBlock(kind: .image, reference: reference, displayStyle: displayStyle)), parentId: nil, children: [])
		case let .video(reference, displayStyle):
			return Block(id: snapshot.id, content: .media(MediaBlock(kind: .video, reference: reference, displayStyle: displayStyle)), parentId: nil, children: [])
		}
	}

	func replaceDictationText(_ text: String) {
		guard isSelectionMode == false else { return }
		let root: UIView = view.window ?? view

		guard let textView = findFirstResponder(in: root) as? UITextView else {
			guard let targetId = dictationTargetBlockId ?? lastTextBlockId() else { return }
			guard let block = document.block(id: targetId) else { return }
			guard case .text(let textBlock) = block.content else { return }

			if dictationTargetBlockId != targetId {
				dictationTargetBlockId = targetId
				dictationPrefix = textBlock.text
				dictationRange = nil
			}

			let prefix = dictationPrefix ?? textBlock.text
			let updated = NSMutableAttributedString(attributedString: prefix)
			let prefixString = prefix.string
			let needsSpace: Bool = {
				guard prefixString.isEmpty == false else { return false }
				guard let last = prefixString.last, last.isWhitespace == false else { return false }
				guard text.isEmpty == false else { return false }
				guard let first = text.first, first.isWhitespace == false else { return false }
				return true
			}()

			let baseFont = dictationFont(for: textBlock.style)
			let dictationColor = UIColor.label
			var attrs: [NSAttributedString.Key: Any] = [
				.font: baseFont,
				.foregroundColor: dictationColor
			]
			if prefix.length > 0, let paragraph = prefix.attribute(.paragraphStyle, at: max(prefix.length - 1, 0), effectiveRange: nil) as? NSParagraphStyle {
				attrs[.paragraphStyle] = paragraph
			}

			if needsSpace {
				updated.append(NSAttributedString(string: " ", attributes: attrs))
			}
			let dictationStart = updated.length
			updated.append(NSAttributedString(string: text, attributes: attrs))
			dictationRange = NSRange(location: dictationStart, length: max(0, updated.length - dictationStart))

			document.updateText(blockId: targetId, text: updated)
			updateTextBlockUI(blockId: targetId)
			scheduleBlocksChanged()
			return
		}

		guard let cell = enclosingBlockCell(for: textView) else {
			textView.text = text
			return
		}

		if dictationTargetBlockId == nil {
			dictationTargetBlockId = cell.blockId
			dictationPrefix = textView.attributedText
			dictationRange = nil
		} else if dictationTargetBlockId != cell.blockId {
			// Focus moved to a different block mid-dictation (e.g. the user pressed
			// return or tapped elsewhere). Drop this stale cumulative result and reset
			// the transcript so speech resumes cleanly on the new block.
			dictationTargetBlockId = cell.blockId
			dictationPrefix = textView.attributedText
			dictationRange = nil
			onDictationInterrupted?()
			return
		}

		let prefix = dictationPrefix ?? NSAttributedString(string: "")
		let updated = NSMutableAttributedString(attributedString: prefix)
		let prefixString = prefix.string
		let needsSpace: Bool = {
			guard prefixString.isEmpty == false else { return false }
			guard let last = prefixString.last, last.isWhitespace == false else { return false }
			guard text.isEmpty == false else { return false }
			guard let first = text.first, first.isWhitespace == false else { return false }
			return true
		}()
		let typing = textView.typingAttributes
		let baseFont = (typing[.font] as? UIFont) ?? textView.font ?? UIFont.preferredFont(forTextStyle: .body)
		let paragraph = typing[.paragraphStyle] as? NSParagraphStyle
		let dictationColor = UIColor.label
		var attrs: [NSAttributedString.Key: Any] = [
			.font: baseFont,
			.foregroundColor: dictationColor
		]
		if let paragraph {
			attrs[.paragraphStyle] = paragraph
		}

		if needsSpace {
			updated.append(NSAttributedString(string: " ", attributes: attrs))
		}
		let dictationStart = updated.length
		updated.append(NSAttributedString(string: text, attributes: attrs))
		dictationRange = NSRange(location: dictationStart, length: max(0, updated.length - dictationStart))

		isApplyingDictationText = true
		textView.attributedText = updated
		let selection = NSRange(location: updated.length, length: 0)
		textView.selectedRange = selection
		cell.didExternallySetText(preservingSelection: selection)
		blockCell(cell, didChangeText: updated)
		isApplyingDictationText = false
	}

	func endDictation() {
		resetDictationState()
	}

	private func resetDictationState() {
		dictationTargetBlockId = nil
		dictationPrefix = nil
		dictationRange = nil
	}

	func insertText(_ text: String) {
		guard isSelectionMode == false else { return }
		guard text.isEmpty == false else { return }
		let root: UIView = view.window ?? view
		if let textView = findFirstResponder(in: root) as? UITextView {
			textView.insertText(text)
			return
		}
		focusLastTextBlock()
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
			guard let self else { return }
			let root: UIView = self.view.window ?? self.view
			if let textView = self.findFirstResponder(in: root) as? UITextView {
				textView.insertText(text)
			}
		}
	}
    
    func deleteSelectedBlocks() {
        guard let indexPaths = tableView.indexPathsForSelectedRows, !indexPaths.isEmpty else { return }
        let removed: [RemovedBlock] = indexPaths
            .map { $0.row }
            .sorted()
            .compactMap { row in
                guard row >= 0, row < document.order.count else { return nil }
                guard let block = document.block(id: document.order[row]) else { return nil }
                return RemovedBlock(block: block, index: row)
            }
        let ids = removed.map { $0.block.id }
        registerRestoreUndo(for: removed)
        document.remove(blockIds: ids)

        if document.order.isEmpty {
			let initial = Block(content: .text(TextBlock(text: NSAttributedString(string: ""), style: initialEmptyStyle)))
            document.setBlock(initial)
            pendingFocusBlockId = initial.id
            setSelectionMode(false)
            tableView.reloadData()
			scheduleBlocksChanged(immediate: true)
            focusIfNeeded()
            return
        }
        
        tableView.reloadData()
		scheduleBlocksChanged(immediate: true)
        notifySelectionState()
    }

	private struct RemovedBlock {
		let block: Block
		let index: Int
	}

	private func registerRestoreUndo(for removed: [RemovedBlock]) {
		guard !removed.isEmpty else { return }
		blockUndoManager.registerUndo(withTarget: self) { target in
			target.restoreRemovedBlocks(removed)
		}
		blockUndoManager.setActionName("Delete")
	}

	private func restoreRemovedBlocks(_ removed: [RemovedBlock]) {
		// Delete-all inserts a single empty placeholder block; drop it before restoring.
		if document.order.count == 1,
		   let onlyId = document.order.first,
		   removed.contains(where: { $0.block.id == onlyId }) == false,
		   isEmptyTextBlock(onlyId) {
			document.remove(blockId: onlyId)
		}
		for entry in removed.sorted(by: { $0.index < $1.index }) {
			let clamped = min(max(entry.index, 0), document.order.count)
			_ = document.insert(entry.block, at: clamped)
		}
		blockUndoManager.registerUndo(withTarget: self) { target in
			target.reDeleteBlocks(removed)
		}
		tableView.reloadData()
		scheduleBlocksChanged(immediate: true)
		if isSelectionMode { notifySelectionState() }
	}

	private func reDeleteBlocks(_ removed: [RemovedBlock]) {
		document.remove(blockIds: removed.map { $0.block.id })
		if document.order.isEmpty {
			let initial = Block(content: .text(TextBlock(text: NSAttributedString(string: ""), style: initialEmptyStyle)))
			document.setBlock(initial)
		}
		blockUndoManager.registerUndo(withTarget: self) { target in
			target.restoreRemovedBlocks(removed)
		}
		tableView.reloadData()
		scheduleBlocksChanged(immediate: true)
		if isSelectionMode { notifySelectionState() }
	}

	private func isEmptyTextBlock(_ id: String) -> Bool {
		guard let block = document.block(id: id), case let .text(textBlock) = block.content else { return false }
		return textBlock.text.length == 0
	}

	func selectedBlockSnapshots() -> [EditorBlockSnapshot] {
		guard let indexPaths = tableView.indexPathsForSelectedRows, !indexPaths.isEmpty else { return [] }
		let sorted = indexPaths.sorted { a, b in
			if a.section != b.section { return a.section < b.section }
			return a.row < b.row
		}
		return sorted.compactMap { indexPath in
			guard indexPath.row >= 0, indexPath.row < document.order.count else { return nil }
			let blockId = document.order[indexPath.row]
			guard let block = document.block(id: blockId) else { return nil }

			let kind: EditorBlockKind = {
				switch block.content {
				case let .text(textBlock):
					return .text(
						text: serializeInlineMarkdown(from: textBlock.text, style: textBlock.style),
						style: textBlock.style
					)
				case let .media(media):
					switch media.kind {
					case .image:
						return .image(reference: media.reference, displayStyle: media.displayStyle)
					case .video:
						return .video(reference: media.reference, displayStyle: media.displayStyle)
					}
				}
			}()

			return EditorBlockSnapshot(
				id: block.id,
				kind: kind,
				parentId: nil,
				position: indexPath.row
			)
		}
	}

	func copySelectedBlocksToPasteboard() {
		let snapshots = selectedBlockSnapshots()
		guard !snapshots.isEmpty else { return }
		writeSnapshotsToPasteboard(snapshots)
	}

	/// Write BOTH a structured (lossless) block representation and a plain markdown
	/// string. Internal paste uses the structured form to rebuild blocks exactly
	/// (checkbox state, inline bold/italic/strike); external apps get the markdown.
	private func writeSnapshotsToPasteboard(_ snapshots: [EditorBlockSnapshot]) {
		let markdown = makeMarkdown(from: snapshots)
		var item: [String: Any] = [EditorClipboard.plainText: markdown]
		if let data = try? JSONEncoder().encode(snapshots) {
			item[EditorClipboard.blocksType] = data
		}
		UIPasteboard.general.setItems([item], options: [:])
	}

	func cutSelectedBlocksToPasteboard() {
		copySelectedBlocksToPasteboard()
		deleteSelectedBlocks()
	}
    
    func setBlocks(_ snapshots: [EditorBlockSnapshot]) {
        blockUndoManager.removeAllActions()
        let sorted = snapshots.sorted { a, b in
            if a.position != b.position { return a.position < b.position }
            return a.id < b.id
        }
        let blocks = sorted.map { s in
			switch s.kind {
			case let .text(text, style):
				let attributed = style == .code ? NSAttributedString(string: text) : parseInlineMarkdown(text)
				return Block(
					id: s.id,
					content: .text(TextBlock(text: attributed, style: style)),
					parentId: nil,
					children: []
				)
			case let .image(reference, displayStyle):
				return Block(
					id: s.id,
					content: .media(MediaBlock(kind: .image, reference: reference, displayStyle: displayStyle)),
					parentId: nil,
					children: []
				)
			case let .video(reference, displayStyle):
				return Block(
					id: s.id,
					content: .media(MediaBlock(kind: .video, reference: reference, displayStyle: displayStyle)),
					parentId: nil,
					children: []
				)
			}
        }
        let orderIds = blocks.map { $0.id }
        document.replaceAll(blocks: blocks, order: orderIds)

		if autoFocusOnAppear {
			if document.order.isEmpty {
				let initial = Block(content: .text(TextBlock(text: NSAttributedString(string: ""), style: initialEmptyStyle)))
				document.setBlock(initial)
				pendingFocusBlockId = initial.id
			} else {
				pendingFocusBlockId = document.order.first(where: { id in
					guard let block = document.block(id: id) else { return false }
					if case .text = block.content { return true }
					return false
				}) ?? document.order.first
			}
		} else {
			pendingFocusBlockId = nil
		}

        if isSelectionMode {
            setSelectionMode(false)
        }

        tableView.reloadData()
		scheduleBlocksChanged(immediate: true)
		if autoFocusOnAppear {
			focusIfNeeded()
		}
    }

    func snapshotBlocks() -> [EditorBlockSnapshot] {
        document.order.enumerated().compactMap { index, blockId in
            guard let block = document.block(id: blockId) else { return nil }
			let kind: EditorBlockKind = {
				switch block.content {
				case let .text(textBlock):
					return .text(
						text: serializeInlineMarkdown(from: textBlock.text, style: textBlock.style),
						style: textBlock.style
					)
				case let .media(media):
					switch media.kind {
					case .image:
						return .image(reference: media.reference, displayStyle: media.displayStyle)
					case .video:
						return .video(reference: media.reference, displayStyle: media.displayStyle)
					}
				}
			}()
			return EditorBlockSnapshot(
				id: block.id,
				kind: kind,
				parentId: nil,
				position: index
			)
        }
    }

	private func scheduleBlocksChanged(immediate: Bool = false) {
		blocksChangedWorkItem?.cancel()
		if immediate {
			onBlocksChanged?(snapshotBlocks())
			return
		}
		let workItem = DispatchWorkItem { [weak self] in
			guard let self else { return }
			self.onBlocksChanged?(self.snapshotBlocks())
		}
		blocksChangedWorkItem = workItem
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
	}

	private func makeMarkdown(from snapshots: [EditorBlockSnapshot]) -> String {
		let sorted = snapshots.sorted { a, b in
			if a.position != b.position { return a.position < b.position }
			return a.id < b.id
		}

		var parts: [String] = []
		parts.reserveCapacity(sorted.count)

		for block in sorted {
			switch block.kind {
			case let .text(text, style):
				let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
				guard !trimmed.isEmpty else { continue }
				switch style {
				case .title:
					parts.append("# \(trimmed)")
				case .description:
					parts.append("## \(trimmed)")
				case .heading3:
					parts.append("### \(trimmed)")
				case .heading4:
					parts.append("#### \(trimmed)")
				case .heading5:
					parts.append("##### \(trimmed)")
				case .heading6:
					parts.append("###### \(trimmed)")
				case .code:
					parts.append("```\n\(trimmed)\n```")
				case .listBullet:
					parts.append("- \(trimmed)")
				case .checkbox:
					if trimmed.hasPrefix("[") {
						parts.append("- \(trimmed)")
					} else {
						parts.append("- [ ] \(trimmed)")
					}
				default:
					parts.append(trimmed)
				}
			case let .image(reference, _):
				let ref = reference.trimmingCharacters(in: .whitespacesAndNewlines)
				guard !ref.isEmpty else { continue }
				parts.append("![](\(ref))")
			case let .video(reference, _):
				let ref = reference.trimmingCharacters(in: .whitespacesAndNewlines)
				guard !ref.isEmpty else { continue }
				parts.append("[](\(ref))")
			}
		}

		return parts.joined(separator: "\n\n")
	}

    private enum InlineKind {
        case bold
        case italic
        case strike
        case code
    }

    private struct InlineToken {
        let literal: String
        let kind: InlineKind
    }

    private struct OpenMarker {
        let token: InlineToken
        let startUtf16: Int
    }

    private func parseInlineMarkdown(_ markdown: String) -> NSAttributedString {
        let tokens: [InlineToken] = [
            InlineToken(literal: "~~", kind: .strike),
            InlineToken(literal: "**", kind: .bold),
            InlineToken(literal: "__", kind: .bold),
            InlineToken(literal: "`", kind: .code),
            InlineToken(literal: "*", kind: .italic),
            InlineToken(literal: "_", kind: .italic)
        ]

        let chars = Array(markdown)
        func matches(_ token: InlineToken, at i: Int) -> Bool {
            let t = Array(token.literal)
            guard i + t.count <= chars.count else { return false }
            for j in 0..<t.count where chars[i + j] != t[j] { return false }
            return true
        }

        func hasClosing(_ token: InlineToken, after i: Int) -> Bool {
            let t = Array(token.literal)
            guard i < chars.count else { return false }
            if t.isEmpty { return false }
            var k = i
            while k + t.count <= chars.count {
                var ok = true
                for j in 0..<t.count where chars[k + j] != t[j] { ok = false; break }
                if ok { return true }
                k += 1
            }
            return false
        }

        var output = ""
        var outputUtf16 = 0
        var stack: [OpenMarker] = []
        var closed: [(kind: InlineKind, range: NSRange)] = []

        func appendLiteral(_ s: String) {
            output.append(contentsOf: s)
            outputUtf16 += s.utf16.count
        }

        var i = 0
        while i < chars.count {
            if let token = tokens.first(where: { matches($0, at: i) }) {
                if let openIndex = stack.lastIndex(where: { $0.token.literal == token.literal }) {
                    let open = stack.remove(at: openIndex)
                    let range = NSRange(location: open.startUtf16, length: outputUtf16 - open.startUtf16)
                    if range.length > 0 {
                        closed.append((kind: token.kind, range: range))
                    }
                    i += token.literal.count
                    continue
                } else if hasClosing(token, after: i + token.literal.count) {
                    stack.append(OpenMarker(token: token, startUtf16: outputUtf16))
                    i += token.literal.count
                    continue
                } else {
                    appendLiteral(token.literal)
                    i += token.literal.count
                    continue
                }
            }

            let c = chars[i]
            let s = String(c)
            appendLiteral(s)
            i += 1
        }

        let attributed = NSMutableAttributedString(string: output)
        let base = UIFont.preferredFont(forTextStyle: .body)
        let mono = UIFont.monospacedSystemFont(ofSize: base.pointSize, weight: .regular)

        func applyTraits(_ traits: UIFontDescriptor.SymbolicTraits, to range: NSRange) {
            let current = attributed.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont ?? base
            attributed.addAttribute(.font, value: current.withTraits(traits), range: range)
        }

        for change in closed {
            switch change.kind {
            case .bold:
                applyTraits(.traitBold, to: change.range)
                attributed.addAttribute(.appInlineBold, value: true, range: change.range)
            case .italic:
                applyTraits(.traitItalic, to: change.range)
                attributed.addAttribute(.appInlineItalic, value: true, range: change.range)
            case .strike:
                attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: change.range)
                attributed.addAttribute(.appInlineStrike, value: true, range: change.range)
            case .code:
                attributed.addAttribute(.font, value: mono, range: change.range)
                attributed.addAttribute(.appInlineCode, value: true, range: change.range)
            }
        }

        return attributed
    }

    private func serializeInlineMarkdown(from attributed: NSAttributedString, style: TextStyle) -> String {
        if style == .code { return attributed.string }

        struct Key: Equatable {
            let isMono: Bool
            let isBold: Bool
            let isItalic: Bool
            let isStrike: Bool
        }

        func boolAttr(_ attrs: [NSAttributedString.Key: Any], _ key: NSAttributedString.Key) -> Bool {
            if let b = attrs[key] as? Bool { return b }
            if let n = attrs[key] as? NSNumber { return n.boolValue }
            return false
        }

        func baseFont(for style: TextStyle) -> UIFont {
            switch style {
            case .title:
                return UIFont.appSpaceGrotesk(size: 32, weight: .bold)
            case .description:
                return UIFont.appSpaceGrotesk(size: 26, weight: .bold)
            case .heading3:
                return UIFont.appSpaceGrotesk(size: 22, weight: .semibold)
            case .heading4:
                return UIFont.appSpaceGrotesk(size: 19, weight: .semibold)
            case .heading5:
                return UIFont.appSpaceGrotesk(size: 17, weight: .medium)
            case .heading6:
                return UIFont.appSpaceGrotesk(size: 15, weight: .medium)
            case .code:
                return UIFont.monospacedSystemFont(ofSize: 17, weight: .regular)
            case .listBullet, .toggle, .toggleHeader, .checkbox, .text:
                return UIFont.appDMSans(size: 17, weight: .regular)
            }
        }

        let base = baseFont(for: style)
        let baseTraits = base.fontDescriptor.symbolicTraits
        let baseName = base.fontName.lowercased()

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

        func isNamedBold(_ fontName: String) -> Bool {
            let n = fontName.lowercased()
            return n.contains("bold") || n.contains("semibold") || n.contains("demibold") || n.contains("heavy") || n.contains("black")
        }

        func isNamedItalic(_ fontName: String) -> Bool {
            let n = fontName.lowercased()
            return n.contains("italic") || n.contains("oblique")
        }

        func wrap(_ text: String, key: Key) -> String {
            guard !text.isEmpty else { return text }

            var start = text.startIndex
            var end = text.endIndex
            while start < end, text[start].isWhitespace {
                start = text.index(after: start)
            }
            while end > start, text[text.index(before: end)].isWhitespace {
                end = text.index(before: end)
            }

            let leading = String(text[..<start])
            let core = String(text[start..<end])
            let trailing = String(text[end...])

            if core.isEmpty { return text }

            if key.isMono {
                return leading + "`" + core + "`" + trailing
            }

            var prefix = ""
            var suffix = ""

            if key.isBold && key.isItalic {
                prefix += "***"
                suffix = "***" + suffix
            } else {
                if key.isBold {
                    prefix += "**"
                    suffix = "**" + suffix
                }
                if key.isItalic {
                    prefix += "*"
                    suffix = "*" + suffix
                }
            }

            if key.isStrike {
                prefix = "~~" + prefix
                suffix += "~~"
            }

            return leading + prefix + core + suffix + trailing
        }

        var result = ""
        var buffer = ""
        var lastKey: Key?

		func flushBufferedText() {
			guard let currentKey = lastKey else { return }
			result += wrap(buffer, key: currentKey)
			buffer = ""
			lastKey = nil
		}

		func escapedLinkLabel(_ text: String) -> String {
			text
				.replacingOccurrences(of: "[", with: "\\[")
				.replacingOccurrences(of: "]", with: "\\]")
		}

		let ns = attributed.string as NSString
		let markdownLinkRegex = try! NSRegularExpression(
			pattern: "\\[([^\\]]+)\\]\\(([^\\s\\)]+)\\)",
			options: []
		)
		let markdownLinkRanges: [NSRange] = markdownLinkRegex
			.matches(in: attributed.string, options: [], range: NSRange(location: 0, length: ns.length))
			.map { $0.range(at: 0) }

        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length), options: []) { attrs, range, _ in
            let substring = attributed.attributedSubstring(from: range).string
			let intersectsMarkdownLink = markdownLinkRanges.contains(where: { NSIntersectionRange($0, range).length > 0 })

			let linkURL: URL? = {
				if let u = attrs[.link] as? URL { return u }
				if let s = attrs[.link] as? String { return URL(string: s) }
				if let s = attrs[.appInlineLinkUrl] as? String { return URL(string: s) }
				return nil
			}()
			if !intersectsMarkdownLink, let linkURL {
				flushBufferedText()
				result += "[\(escapedLinkLabel(substring))](\(linkURL.absoluteString))"
				return
			}

			if !intersectsMarkdownLink,
			   let noteLinkIdValue = attrs[.appInlineNoteLinkId] {
				let noteId: String? = {
					if let s = noteLinkIdValue as? String { return s }
					if let n = noteLinkIdValue as? NSNumber { return n.stringValue }
					return nil
				}()
				if let noteId, !noteId.isEmpty {
					flushBufferedText()
					result += "[\(escapedLinkLabel(substring))](konuq://note/\(noteId))"
					return
				}
			}

			let storedBold = boolAttr(attrs, .appInlineBold)
			let storedItalic = boolAttr(attrs, .appInlineItalic)
			let storedCode = boolAttr(attrs, .appInlineCode)
			let storedStrike = boolAttr(attrs, .appInlineStrike)
            let font = (attrs[.font] as? UIFont) ?? base
            let traits = font.fontDescriptor.symbolicTraits
            let name = font.fontName.lowercased()
			let weight = weightValue(font)
			let baseWeight = weightValue(base)
			let slant = slantValue(font)
			let baseSlant = slantValue(base)

            let key = Key(
                isMono: storedCode || isMonospaced(font),
                isBold: storedBold || ((weight - baseWeight) > 0.12) || (baseWeight < UIFont.Weight.semibold.rawValue && weight >= UIFont.Weight.semibold.rawValue) || ((traits.contains(.traitBold) && !baseTraits.contains(.traitBold)) || (isNamedBold(name) && !isNamedBold(baseName))),
                isItalic: storedItalic || (abs(slant) > 0.01 && abs(baseSlant) <= 0.01) || ((traits.contains(.traitItalic) && !baseTraits.contains(.traitItalic)) || (isNamedItalic(name) && !isNamedItalic(baseName))),
                isStrike: storedStrike || (attrs[.strikethroughStyle] != nil)
            )

            if let lastKey, lastKey == key {
                buffer += substring
                return
            }

			flushBufferedText()

            lastKey = key
            buffer = substring
        }

		flushBufferedText()
		if result.isEmpty {
            result = attributed.string
        }

        return result
    }
    
    @objc
    private func moveSelectedUp() {
        guard let indexPaths = tableView.indexPathsForSelectedRows else { return }
        let indices = indexPaths.map { $0.row }.sorted()
        for i in indices {
            document.move(from: i, to: max(i-1, 0))
        }
        tableView.reloadData()
        reselect(indices.map { IndexPath(row: max($0-1, 0), section: 0) })
    }
    
    @objc
    private func moveSelectedDown() {
        guard let indexPaths = tableView.indexPathsForSelectedRows else { return }
        let indices = indexPaths.map { $0.row }.sorted(by: >)
        for i in indices {
            document.move(from: i, to: min(i+1, document.order.count-1))
        }
        tableView.reloadData()
        reselect(indices.map { IndexPath(row: min($0+1, document.order.count-1), section: 0) })
    }
    
    private func reselect(_ indexPaths: [IndexPath]) {
        for ip in indexPaths {
            tableView.selectRow(at: ip, animated: false, scrollPosition: .none)
			(tableView.cellForRow(at: ip) as? BlockSelectableCell)?.isSelectionMode = true
        }
        notifySelectionState()
    }
    
    private func focusIfNeeded() {
        guard let id = pendingFocusBlockId else { return }
        let cursor = pendingFocusCursor
		if focusVisibleTextCell(blockId: id, cursor: cursor) {
			pendingFocusBlockId = nil
			pendingFocusCursor = .end
			return
		}

		guard let row = document.order.firstIndex(of: id) else {
			pendingFocusBlockId = nil
			pendingFocusCursor = .end
			return
		}
		let indexPath = IndexPath(row: row, section: 0)
		tableView.scrollToRow(at: indexPath, at: .middle, animated: false)
		tableView.layoutIfNeeded()

		if focusVisibleTextCell(blockId: id, cursor: cursor) {
			pendingFocusBlockId = nil
			pendingFocusCursor = .end
		}
    }

	private enum FocusCursorPlacement {
		case start
		case end
		case position(Int)
	}

	private func focusVisibleTextCell(blockId: String, cursor: FocusCursorPlacement = .end) -> Bool {
		guard let row = document.order.firstIndex(of: blockId) else { return false }
		let indexPath = IndexPath(row: row, section: 0)
		guard let cell = tableView.cellForRow(at: indexPath) as? BlockCell else { return false }
		guard let block = document.block(id: blockId) else { return false }
		guard case .text(let textBlock) = block.content else { return false }

		cell.configure(
			blockId: blockId,
			text: textBlock.text,
			style: textBlock.style,
			isFirstBlock: row == 0
		)
		cell.textView.becomeFirstResponder()
		// Enforced for a short window: anything that tries to push the caret back to
		// the end (UIKit focus restoration, inline-attribute passes) gets corrected.
		placeCaret(cursor, in: cell)
		if textBlock.text.length == 0 {
			cell.setInlineTypingModes(bold: persistentInlineBoldMode, italic: persistentInlineItalicMode)
		}
		return true
	}

	private func applyOrderChange(oldOrder: [String], completion: @escaping () -> Void) {
		let newOrder = document.order
		guard oldOrder != newOrder else {
			completion()
			return
		}

		let oldSet = Set(oldOrder)
		let newSet = Set(newOrder)
		let removedIds = oldOrder.filter { !newSet.contains($0) }
		let insertedIds = newOrder.filter { !oldSet.contains($0) }

		let commonOld = oldOrder.filter { newSet.contains($0) }
		let commonNew = newOrder.filter { oldSet.contains($0) }
		let isInsertDeleteOnly = (commonOld == commonNew)

		guard isInsertDeleteOnly else {
			tableView.reloadData()
			completion()
			return
		}

		let deleteIndexPaths = removedIds.compactMap { id -> IndexPath? in
			guard let idx = oldOrder.firstIndex(of: id) else { return nil }
			return IndexPath(row: idx, section: 0)
		}
		let insertIndexPaths = insertedIds.compactMap { id -> IndexPath? in
			guard let idx = newOrder.firstIndex(of: id) else { return nil }
			return IndexPath(row: idx, section: 0)
		}

		tableView.performBatchUpdates {
			if !deleteIndexPaths.isEmpty {
				tableView.deleteRows(at: deleteIndexPaths, with: .none)
			}
			if !insertIndexPaths.isEmpty {
				tableView.insertRows(at: insertIndexPaths, with: .none)
			}
		} completion: { _ in
			completion()
		}
	}
    
    private func focus(blockId: String) {
        guard let row = document.order.firstIndex(of: blockId) else { return }
		let idToFocus: String? = {
			guard let block = document.block(id: blockId) else { return nil }
			if case .text = block.content { return blockId }
			let nextText = document.order.dropFirst(row + 1).first(where: { id in
				guard let b = document.block(id: id) else { return false }
				if case .text = b.content { return true }
				return false
			})
			if let nextText { return nextText }
			let newText = Block(content: .text(TextBlock(text: NSAttributedString(string: ""), style: .text)))
			_ = document.insert(newText, after: blockId)
			tableView.reloadData()
			scheduleBlocksChanged(immediate: true)
			return newText.id
		}()

		guard let idToFocus else { return }
		pendingFocusBlockId = idToFocus
		focusIfNeeded()
    }

    private func focusLastBlock() {
        guard let lastId = document.order.last else { return }
        focus(blockId: lastId)
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        document.order.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let blockId = document.order[indexPath.row]
		guard let block = document.block(id: blockId) else {
			return tableView.dequeueReusableCell(withIdentifier: BlockCell.reuseId, for: indexPath)
		}

		switch block.content {
		case let .text(textBlock):
			let cell = tableView.dequeueReusableCell(withIdentifier: BlockCell.reuseId, for: indexPath)
			guard let blockCell = cell as? BlockCell else { return cell }
			blockCell.configure(blockId: blockId, text: textBlock.text, style: textBlock.style, isFirstBlock: indexPath.row == 0)
			blockCell.delegate = self
			blockCell.isSelectionMode = isSelectionMode
			return blockCell
		case let .media(media):
			let cell = tableView.dequeueReusableCell(withIdentifier: MediaBlockCell.reuseId, for: indexPath)
			guard let mediaCell = cell as? MediaBlockCell else { return cell }
			mediaCell.configure(blockId: blockId, kind: media.kind, reference: media.reference, displayStyle: media.displayStyle)
			mediaCell.delegate = self
			mediaCell.isSelectionMode = isSelectionMode
			return mediaCell
		}
    }

	func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
		guard isSelectionMode == false else { return }
		guard let targetId = pendingFocusBlockId else { return }
		guard indexPath.row >= 0, indexPath.row < document.order.count else { return }
		guard document.order[indexPath.row] == targetId else { return }
		guard let blockCell = cell as? BlockCell else { return }
		guard let block = document.block(id: targetId), case .text(let textBlock) = block.content else { return }

		pendingFocusBlockId = nil
		// Consume the pending cursor too: this path races focusIfNeeded (it fires
		// during the batch insert) and used to hardcode the caret to the end,
		// overriding the split's caret placement.
		let cursor = pendingFocusCursor
		pendingFocusCursor = .end
		blockCell.configure(
			blockId: targetId,
			text: textBlock.text,
			style: textBlock.style,
			isFirstBlock: indexPath.row == 0
		)
		blockCell.textView.becomeFirstResponder()
		placeCaret(cursor, in: blockCell)
	}

	private func placeCaret(_ cursor: FocusCursorPlacement, in cell: BlockCell) {
		let length = cell.textView.attributedText.length
		let target: NSRange = {
			switch cursor {
			case .start:
				return NSRange(location: 0, length: 0)
			case .end:
				return NSRange(location: length, length: 0)
			case .position(let location):
				return NSRange(location: min(max(location, 0), length), length: 0)
			}
		}()
		cell.enforceSelection(target)
	}
    
    func blockCell(_ cell: BlockCell, didChangeText text: NSAttributedString) {
        document.updateText(blockId: cell.blockId, text: text)
        tableView.beginUpdates()
        tableView.endUpdates()
		scheduleBlocksChanged()
		// When this fires on the dictation target while we are NOT programmatically
		// applying a recognition result, the user edited by hand: re-baseline the
		// prefix and reset the transcript so old speech isn't re-inserted. (The
		// isApplyingDictationText guard is critical — without it every partial
		// result would restart the recognizer and kill the session.)
		if isApplyingDictationText == false, cell.blockId == dictationTargetBlockId {
			dictationPrefix = text
			dictationRange = nil
			onDictationInterrupted?()
		}
    }

	func blockCell(_ cell: BlockCell, didTapURL url: URL) {
		onOpenURL?(url)
	}

	func blockCell(_ cell: BlockCell, dockAccessory accessory: UIView) {
		if accessory.superview === accessoryDockContainer {
			accessoryDockContainer.isHidden = false
			return
		}
		accessoryDockContainer.subviews.forEach { $0.removeFromSuperview() }
		accessory.translatesAutoresizingMaskIntoConstraints = false
		accessoryDockContainer.addSubview(accessory)
		NSLayoutConstraint.activate([
			accessory.topAnchor.constraint(equalTo: accessoryDockContainer.topAnchor),
			accessory.bottomAnchor.constraint(equalTo: accessoryDockContainer.bottomAnchor),
			accessory.leadingAnchor.constraint(equalTo: accessoryDockContainer.leadingAnchor),
			accessory.trailingAnchor.constraint(equalTo: accessoryDockContainer.trailingAnchor)
		])
		accessoryDockContainer.isHidden = false
		if isAccessoryDocked == false {
			isAccessoryDocked = true
			// Keep the last blocks reachable above the docked bar.
			tableView.contentInset.bottom += 58
			tableView.verticalScrollIndicatorInsets.bottom = tableView.contentInset.bottom
		}
	}

	func blockCell(_ cell: BlockCell, didPasteBlocks snapshots: [EditorBlockSnapshot]) {
		guard isSelectionMode == false, !snapshots.isEmpty else { return }
		// Fresh ids so pasting within the same note can't collide with existing blocks.
		let reIded = snapshots
			.sorted { $0.position < $1.position }
			.enumerated()
			.map { index, snapshot in
				EditorBlockSnapshot(id: UUID().uuidString, kind: snapshot.kind, parentId: nil, position: index)
			}
		insertBlocksAtCursor(reIded)
	}

	func blockCell(_ cell: BlockCell, didChangeInlineTypingModeBold isBold: Bool, italic isItalic: Bool) {
		persistentInlineBoldMode = isBold
		persistentInlineItalicMode = isItalic
	}

	func blockCell(_ cell: BlockCell, didRequestMoveFocus direction: BlockFocusMoveDirection) {
		guard isSelectionMode == false else { return }
		guard let currentIndex = document.order.firstIndex(of: cell.blockId) else { return }

		let candidateIndices: AnySequence<Int> = {
			switch direction {
			case .up:
				return AnySequence(stride(from: currentIndex - 1, through: 0, by: -1))
			case .down:
				return AnySequence(stride(from: currentIndex + 1, through: max(document.order.count - 1, 0), by: 1))
			}
		}()

		for idx in candidateIndices {
			guard idx >= 0, idx < document.order.count else { continue }
			let targetId = document.order[idx]
			guard let block = document.block(id: targetId) else { continue }
			guard case .text = block.content else { continue }

			let cursor: FocusCursorPlacement = (direction == .up) ? .end : .start
			let indexPath = IndexPath(row: idx, section: 0)
			tableView.scrollToRow(at: indexPath, at: .middle, animated: false)
			tableView.layoutIfNeeded()
			_ = focusVisibleTextCell(blockId: targetId, cursor: cursor)
			return
		}
	}
    
    func blockCell(_ cell: BlockCell, didTrigger action: KeyboardAction) {
        if isSelectionMode { return }
		if action == .pickMedia {
			presentMediaPicker(insertAfterBlockId: cell.blockId)
			return
		}
		if action == .presentLinkToNoteSheet {
			onLinkToNote?()
			return
		}
		if action == .insertLocation {
			onInsertLocation?()
			return
		}
        if case .markdownTurnInto = action {
			_ = keyboardHandler.handle(blockId: cell.blockId, action: action)
			if let row = document.order.firstIndex(of: cell.blockId),
			   let block = document.block(id: cell.blockId),
			   case .text(let textBlock) = block.content {
				cell.configure(
					blockId: cell.blockId,
					text: textBlock.text,
					style: textBlock.style,
					isFirstBlock: row == 0
				)
				tableView.beginUpdates()
				tableView.endUpdates()
			}
			scheduleBlocksChanged(immediate: true)
            return
        }
        
        let currentText = cell.textView.attributedText ?? NSAttributedString(string: "")
        document.updateText(blockId: cell.blockId, text: currentText)
		let oldOrder = document.order
        
        let currentRange = cell.textView.selectedRange
        let textLength = currentText.length
        // For enter actions keep the range the keypress reported (clamped): it is
        // authoritative for where the split must happen. Re-reading selectedRange
        // here could pick up a caret silently moved by the checkbox/inline-attribute
        // machinery, splitting at the wrong spot (e.g. at the end — dropping the
        // text that should carry into the new block).
        func clamped(_ range: NSRange) -> NSRange {
            let location = max(0, min(range.location, textLength))
            let length = max(0, min(range.length, textLength - location))
            return NSRange(location: location, length: length)
        }
        let normalizedAction: KeyboardAction
        switch action {
        case .enterInside(let string, let range):
            normalizedAction = .enterInside(string: string, range: clamped(range))
        case .enterAtTheEnd(let string, let range):
            normalizedAction = .enterAtTheEnd(string: string, range: clamped(range))
		case .pasteMultiline(let text, _):
			normalizedAction = .pasteMultiline(text: text, range: currentRange)
        default:
            normalizedAction = action
        }
        
        // For a backspace-merge, the caret belongs at the junction point (end of the
        // previous block's ORIGINAL text), not at the end of the merged text.
        var mergeJunction: Int?
        var mergePreviousId: String?
        if normalizedAction == .delete,
           currentText.length > 0,
           let index = document.index(of: cell.blockId), index > 0 {
            let previousId = document.order[index - 1]
            if let previous = document.block(id: previousId),
               case .text(let previousTextBlock) = previous.content {
                mergePreviousId = previousId
                mergeJunction = previousTextBlock.text.length
            }
        }

        let newId = keyboardHandler.handle(blockId: cell.blockId, action: normalizedAction)
        pendingFocusBlockId = newId ?? cell.blockId
        // The caret stays where the interaction happened: at the START of the new
        // block after an enter/split, at the junction after a merge.
        switch normalizedAction {
        case .enterInside, .enterAtTheEnd, .enterForEmpty, .enterAtTheBegining:
            pendingFocusCursor = .start
        case .delete:
            if let mergeJunction, let mergePreviousId, newId == mergePreviousId {
                pendingFocusCursor = .position(mergeJunction)
            } else {
                pendingFocusCursor = .end
            }
        default:
            pendingFocusCursor = .end
        }

		if let updated = document.block(id: cell.blockId), case .text(let updatedTextBlock) = updated.content {
			if let row = document.order.firstIndex(of: cell.blockId) {
				cell.configure(
					blockId: cell.blockId,
					text: updatedTextBlock.text,
					style: updatedTextBlock.style,
					isFirstBlock: row == 0
				)
			}
		}

		if normalizedAction == .delete, let id = pendingFocusBlockId, focusVisibleTextCell(blockId: id, cursor: pendingFocusCursor) {
			pendingFocusBlockId = nil
			pendingFocusCursor = .end
		}

		applyOrderChange(oldOrder: oldOrder) { [weak self] in
			guard let self else { return }
			self.scheduleBlocksChanged(immediate: true)
			self.focusIfNeeded()
		}
    }

	func mediaBlockCell(_ cell: MediaBlockCell, didChangeDisplayStyle displayStyle: MediaBlockDisplayStyle) {
		guard var block = document.block(id: cell.blockId) else { return }
		guard case .media(var media) = block.content else { return }
		media.displayStyle = displayStyle
		block.content = .media(media)
		document.setBlock(block)
		tableView.beginUpdates()
		tableView.endUpdates()
		scheduleBlocksChanged()
	}

	func mediaBlockCellDidTapMedia(_ cell: MediaBlockCell) {
		guard isSelectionMode == false else { return }
		guard let block = document.block(id: cell.blockId) else { return }
		guard case .media(let media) = block.content else { return }
		switch media.kind {
		case .image:
			presentFullScreenImage(reference: media.reference)
		case .video:
			presentFullScreenVideo(reference: media.reference)
		}
	}

	private func presentFullScreenImage(reference: String) {
		pendingFullScreenImageReference = reference
		pendingFullScreenImageAttempts = 0
		forceDismissKeyboard()
		attemptPresentPendingFullScreenImage()
	}

	private func presentFullScreenVideo(reference: String) {
		pendingFullScreenVideoReference = reference
		pendingFullScreenVideoAttempts = 0
		forceDismissKeyboard()
		attemptPresentPendingFullScreenVideo()
	}

	private func findFirstResponder(in view: UIView) -> UIView? {
		if view.isFirstResponder { return view }
		for subview in view.subviews {
			if let found = findFirstResponder(in: subview) {
				return found
			}
		}
		return nil
	}

	private func forceDismissKeyboard() {
		tableView.endEditing(true)
		view.endEditing(true)
		view.window?.endEditing(true)
		UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
	}

	private func attemptPresentPendingFullScreenImage() {
		guard let reference = pendingFullScreenImageReference else { return }
		let root: UIView? = view.window ?? view
		if let root, findFirstResponder(in: root) == nil {
			pendingFullScreenImageReference = nil
			pendingFullScreenImageAttempts = 0
			presentFullScreenImageNow(reference: reference)
			return
		}

		pendingFullScreenImageAttempts += 1
		if pendingFullScreenImageAttempts >= 12 {
			pendingFullScreenImageReference = nil
			pendingFullScreenImageAttempts = 0
			presentFullScreenImageNow(reference: reference)
			return
		}

		DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
			self?.attemptPresentPendingFullScreenImage()
		}
	}

	private func attemptPresentPendingFullScreenVideo() {
		guard let reference = pendingFullScreenVideoReference else { return }
		let root: UIView? = view.window ?? view
		if let root, findFirstResponder(in: root) == nil {
			pendingFullScreenVideoReference = nil
			pendingFullScreenVideoAttempts = 0
			presentFullScreenVideoNow(reference: reference)
			return
		}

		pendingFullScreenVideoAttempts += 1
		if pendingFullScreenVideoAttempts >= 12 {
			pendingFullScreenVideoReference = nil
			pendingFullScreenVideoAttempts = 0
			presentFullScreenVideoNow(reference: reference)
			return
		}

		DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
			self?.attemptPresentPendingFullScreenVideo()
		}
	}

	private func presentFullScreenImageNow(reference: String) {
		let viewer = FullScreenImageViewController()
		viewer.modalPresentationStyle = .fullScreen
		present(viewer, animated: true)

		loadImage(reference: reference) { image in
			viewer.setImage(image)
		}
	}

	private func presentFullScreenVideoNow(reference: String) {
		let playerVC = AVPlayerViewController()
		playerVC.modalPresentationStyle = .fullScreen
		present(playerVC, animated: true)

		loadVideoPlayer(reference: reference) { player in
			playerVC.player = player
			player?.play()
		}
	}

	private func loadVideoPlayer(reference: String, completion: @escaping (AVPlayer?) -> Void) {
		if reference.hasPrefix("phasset:") {
			let id = String(reference.dropFirst("phasset:".count))
			let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
			guard let asset = assets.firstObject else {
				completion(nil)
				return
			}

			let options = PHVideoRequestOptions()
			options.isNetworkAccessAllowed = true
			options.deliveryMode = .highQualityFormat

			PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
				DispatchQueue.main.async {
					guard let item else {
						completion(nil)
						return
					}
					completion(AVPlayer(playerItem: item))
				}
			}
			return
		}

		if let url = MediaReferenceResolver.localFileURL(from: reference) {
			completion(AVPlayer(url: url))
			return
		}

		completion(nil)
	}

	private func loadImage(reference: String, completion: @escaping (UIImage?) -> Void) {
		if reference.hasPrefix("phasset:") {
			let id = String(reference.dropFirst("phasset:".count))
			let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
			guard let asset = assets.firstObject else {
				completion(nil)
				return
			}

			let options = PHImageRequestOptions()
			options.isNetworkAccessAllowed = true
			options.deliveryMode = .highQualityFormat
			options.resizeMode = .none

			PHImageManager.default().requestImage(
				for: asset,
				targetSize: PHImageManagerMaximumSize,
				contentMode: .aspectFit,
				options: options
			) { image, _ in
				DispatchQueue.main.async {
					completion(image)
				}
			}
			return
		}

		if let url = MediaReferenceResolver.localFileURL(from: reference) {
			DispatchQueue.global(qos: .userInitiated).async {
				let image: UIImage? = {
					guard let data = try? Data(contentsOf: url) else { return nil }
					return UIImage(data: data)
				}()
				DispatchQueue.main.async {
					completion(image)
				}
			}
			return
		}

		completion(nil)
	}

	private func presentMediaPicker(insertAfterBlockId: String) {
		pendingMediaInsertAfterBlockId = insertAfterBlockId
		var configuration = PHPickerConfiguration(photoLibrary: .shared())
		configuration.selectionLimit = 1
		configuration.filter = .any(of: [.images, .videos])
		let picker = PHPickerViewController(configuration: configuration)
		picker.delegate = self
		present(picker, animated: true)
	}

	func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
		dismiss(animated: true)
		guard let result = results.first else {
			pendingMediaInsertAfterBlockId = nil
			return
		}
		guard let afterId = pendingMediaInsertAfterBlockId else { return }
		pendingMediaInsertAfterBlockId = nil

		let provider = result.itemProvider
		let isVideo = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
		let assetIdentifier = result.assetIdentifier

		if isVideo {
			provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, _ in
				guard let self else { return }
				if let url {
					let persisted = self.persistPickedFile(sourceUrl: url, defaultExtension: "mov")
					DispatchQueue.main.async {
						self.insertMediaBlock(kind: .video, reference: persisted, afterBlockId: afterId)
					}
					return
				}
				guard let assetIdentifier else { return }
				self.persistVideoAsset(localIdentifier: assetIdentifier) { persisted in
					guard let persisted else { return }
					DispatchQueue.main.async {
						self.insertMediaBlock(kind: .video, reference: persisted, afterBlockId: afterId)
					}
				}
			}
			return
		}

		provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
			guard let self else { return }
			if let data, let persisted = self.persistPickedImageData(data: data) {
				DispatchQueue.main.async {
					self.insertMediaBlock(kind: .image, reference: persisted, afterBlockId: afterId)
				}
				return
			}
			guard let assetIdentifier else { return }
			self.persistImageAsset(localIdentifier: assetIdentifier) { persisted in
				guard let persisted else { return }
				DispatchQueue.main.async {
					self.insertMediaBlock(kind: .image, reference: persisted, afterBlockId: afterId)
				}
			}
		}
	}

	private func insertMediaBlock(kind: MediaBlockKind, reference: String, afterBlockId: String) {
		let media = Block(content: .media(MediaBlock(kind: kind, reference: reference, displayStyle: .medium)))
		let mediaId = document.insert(media, after: afterBlockId)
		let trailingText = Block(content: .text(TextBlock(text: NSAttributedString(string: ""), style: .text)))
		_ = document.insert(trailingText, after: mediaId)
		pendingFocusBlockId = trailingText.id
		tableView.reloadData()
		scheduleBlocksChanged(immediate: true)
		focusIfNeeded()
	}

	/// External image drop (Finder / Photos / another app): persist each image into
	/// the media directory and insert it as an image block at the drop position —
	/// the same storage the media picker uses, so sync/publish just work.
	private func performExternalImageDrop(coordinator: UITableViewDropCoordinator) {
		let destinationRow = coordinator.destinationIndexPath?.row ?? document.order.count
		var offset = 0
		for item in coordinator.items {
			let provider = item.dragItem.itemProvider
			let isImage = provider.hasItemConformingToTypeIdentifier(UTType.image.identifier)
				|| provider.canLoadObject(ofClass: UIImage.self)
			guard isImage else { continue }
			let insertRow = destinationRow + offset
			offset += 1
			provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] url, _ in
				// Read within the callback: the temp file dies when it returns.
				if let url, let data = try? Data(contentsOf: url) {
					DispatchQueue.main.async { self?.insertDroppedImageData(data, at: insertRow) }
					return
				}
				// Sources that vend a UIImage object instead of a file (e.g. Photos).
				guard provider.canLoadObject(ofClass: UIImage.self) else { return }
				provider.loadObject(ofClass: UIImage.self) { object, _ in
					guard let image = object as? UIImage,
						  let jpeg = image.jpegData(compressionQuality: 0.92) else { return }
					DispatchQueue.main.async { self?.insertDroppedImageData(jpeg, at: insertRow) }
				}
			}
		}
	}

	private func insertDroppedImageData(_ data: Data, at row: Int) {
		guard let reference = persistPickedImageData(data: data) else { return }
		let media = Block(content: .media(MediaBlock(kind: .image, reference: reference, displayStyle: .medium)))
		let clamped = max(0, min(row, document.order.count))
		_ = document.insert(media, at: clamped)
		tableView.reloadData()
		scheduleBlocksChanged(immediate: true)
	}

	private func persistPickedFile(sourceUrl: URL, defaultExtension: String) -> String {
		let mediaDir = MediaReferenceResolver.mediaDirectory()
		let ext = sourceUrl.pathExtension.isEmpty ? defaultExtension : sourceUrl.pathExtension
		let filename = "\(UUID().uuidString).\(ext)"
		let destination = mediaDir.appendingPathComponent(filename)
		try? FileManager.default.removeItem(at: destination)
		try? FileManager.default.copyItem(at: sourceUrl, to: destination)
		return MediaReferenceResolver.makeMediaReference(filename: filename)
	}

	private func persistPickedImageData(data: Data) -> String? {
		let mediaDir = MediaReferenceResolver.mediaDirectory()
		let filename = "\(UUID().uuidString).jpg"
		let destination = mediaDir.appendingPathComponent(filename)
		if let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.92) {
			try? jpeg.write(to: destination, options: [.atomic])
			return MediaReferenceResolver.makeMediaReference(filename: filename)
		}
		try? data.write(to: destination, options: [.atomic])
		return MediaReferenceResolver.makeMediaReference(filename: filename)
	}

	private func persistImageAsset(localIdentifier: String, completion: @escaping (String?) -> Void) {
		let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
		guard let asset = assets.firstObject else {
			completion(nil)
			return
		}
		let options = PHImageRequestOptions()
		options.isNetworkAccessAllowed = true
		options.deliveryMode = .highQualityFormat
		options.version = .current
		PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { [weak self] data, _, _, _ in
			guard let self, let data else {
				completion(nil)
				return
			}
			completion(self.persistPickedImageData(data: data))
		}
	}

	private func persistVideoAsset(localIdentifier: String, completion: @escaping (String?) -> Void) {
		let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
		guard let asset = assets.firstObject else {
			completion(nil)
			return
		}
		let options = PHVideoRequestOptions()
		options.isNetworkAccessAllowed = true
		options.deliveryMode = .highQualityFormat
		PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { [weak self] avAsset, _, _ in
			guard let self, let urlAsset = avAsset as? AVURLAsset else {
				completion(nil)
				return
			}
			let persisted = self.persistPickedFile(sourceUrl: urlAsset.url, defaultExtension: "mov")
			completion(persisted)
		}
	}
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        true
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            guard let self else { return }
            let id = self.document.order[indexPath.row]
            self.document.remove(blockId: id)
            self.tableView.deleteRows(at: [indexPath], with: .automatic)
			self.scheduleBlocksChanged(immediate: true)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }
    
    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        true
    }
    
    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        document.move(from: sourceIndexPath.row, to: destinationIndexPath.row)
		scheduleBlocksChanged(immediate: true)
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard isSelectionMode else { return }
        notifySelectionState()
    }
    
    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        guard isSelectionMode else { return }
        if tableView.indexPathsForSelectedRows?.isEmpty ?? true {
            setSelectionMode(false)
            return
        }
        notifySelectionState()
    }
    
    func tableView(_ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        let blockId = document.order[indexPath.row]
        // Internal reorder works through localObject; the provider is what EXTERNAL
        // drop targets (Finder, other apps) receive — so vend real content, not the
        // block id: the media file for media blocks, the text for text blocks.
        let provider: NSItemProvider
        if let block = document.block(id: blockId) {
            switch block.content {
            case .media(let media):
                if let url = MediaReferenceResolver.localFileURL(from: media.reference),
                   FileManager.default.fileExists(atPath: url.path) {
                    let fileProvider = NSItemProvider()
                    let fallback: UTType = media.kind == .image ? .jpeg : .mpeg4Movie
                    let typeId = UTType(filenameExtension: url.pathExtension)?.identifier ?? fallback.identifier
                    fileProvider.suggestedName = url.lastPathComponent
                    fileProvider.registerFileRepresentation(forTypeIdentifier: typeId, fileOptions: [], visibility: .all) { completion in
                        completion(url, false, nil)
                        return nil
                    }
                    provider = fileProvider
                } else {
                    provider = NSItemProvider(object: blockId as NSString)
                }
            case .text(let textBlock):
                let text = textBlock.text.string
                provider = NSItemProvider(object: (text.isEmpty ? blockId : text) as NSString)
            }
        } else {
            provider = NSItemProvider(object: blockId as NSString)
        }
        let item = UIDragItem(itemProvider: provider)
        item.localObject = blockId
        return [item]
    }
    
    func tableView(_ tableView: UITableView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UITableViewDropProposal {
        // External drags (Finder, Photos, another app): accept images as a copy —
        // they become image blocks at the drop position.
        if session.localDragSession == nil {
            guard session.canLoadObjects(ofClass: UIImage.self) else {
                return UITableViewDropProposal(operation: .cancel)
            }
            return UITableViewDropProposal(operation: .copy, intent: .insertAtDestinationIndexPath)
        }
        guard let indexPath = destinationIndexPath,
              let cell = tableView.cellForRow(at: indexPath) else {
            return UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
        }
        let location = session.location(in: tableView)
        let rect = tableView.rectForRow(at: indexPath)
        let relativeY = (location.y - rect.minY) / max(rect.height, 1)
        if relativeY > 0.3 && relativeY < 0.7 && cell.frame.contains(location) {
            return UITableViewDropProposal(operation: .move, intent: .insertIntoDestinationIndexPath)
        }
        return UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }
    
    func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
        if coordinator.proposal.operation == .copy {
            performExternalImageDrop(coordinator: coordinator)
            return
        }
        guard coordinator.proposal.operation == .move else { return }
        guard !document.order.isEmpty else { return }
        let destinationIndexPath = coordinator.destinationIndexPath ?? IndexPath(row: document.order.count - 1, section: 0)
        
        guard let item = coordinator.items.first,
              let sourceIndexPath = item.sourceIndexPath,
              let blockId = item.dragItem.localObject as? String
        else {
            return
        }
        
        if coordinator.proposal.intent == .insertIntoDestinationIndexPath {
            let targetRow = destinationIndexPath.row
            guard targetRow >= 0, targetRow < document.order.count else { return }
            let targetId = document.order[targetRow]
			if targetId != blockId {
				let canMerge: Bool = {
					guard let first = document.block(id: targetId), let second = document.block(id: blockId) else { return false }
					if case .text = first.content, case .text = second.content { return true }
					return false
				}()
				if canMerge {
					service.merge(firstBlockId: targetId, secondBlockId: blockId)
					tableView.reloadData()
					scheduleBlocksChanged(immediate: true)
					coordinator.drop(item.dragItem, toRowAt: destinationIndexPath)
					return
				}
			}
        }
        
        let adjustedDestinationRow: Int = {
            if destinationIndexPath.row > sourceIndexPath.row {
                return max(destinationIndexPath.row - 1, 0)
            }
            return destinationIndexPath.row
        }()
        
        let adjustedDestinationIndexPath = IndexPath(row: adjustedDestinationRow, section: destinationIndexPath.section)
        
        tableView.performBatchUpdates {
            document.move(blockId: blockId, to: adjustedDestinationRow)
            tableView.moveRow(at: sourceIndexPath, to: adjustedDestinationIndexPath)
        }
        
        coordinator.drop(item.dragItem, toRowAt: adjustedDestinationIndexPath)
		scheduleBlocksChanged(immediate: true)
    }
    
    @objc
    private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .ended else { return }
        if tableView.hasActiveDrag { return }
        let location = gesture.location(in: tableView)
        guard let indexPath = tableView.indexPathForRow(at: location) else { return }
        
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        setSelectionMode(true)
        reselect([indexPath])
    }

    /// While a text selection is active inside a block, dragging past the row's
    /// vertical bounds switches into multi-block selection and rubber-bands rows
    /// between the anchor row and the pointer — no long-press needed.
    @objc
    private func handleSelectionEscapePan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: tableView)

        switch gesture.state {
        case .changed:
            if isSelectionMode {
                guard dragSelectionAnchorRow != nil else { return }
                updateDragSelection(to: location)
                return
            }
            guard tableView.hasActiveDrag == false else { return }
            let root: UIView = view.window ?? view
            guard let textView = findFirstResponder(in: root) as? UITextView,
                  let cell = enclosingBlockCell(for: textView) else { return }
            guard textView.selectedRange.length > 0 else { return }
            let cellFrame = tableView.convert(cell.bounds, from: cell)
            // Vertical escape only: horizontal overshoot is still text selection.
            guard location.y < cellFrame.minY || location.y > cellFrame.maxY else { return }
            guard let anchorRow = document.order.firstIndex(of: cell.blockId) else { return }

            textView.resignFirstResponder()
            setSelectionMode(true)
            dragSelectionAnchorRow = anchorRow
            updateDragSelection(to: location)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .ended, .cancelled, .failed:
            dragSelectionAnchorRow = nil
        default:
            break
        }
    }

    private func updateDragSelection(to location: CGPoint) {
        guard let anchor = dragSelectionAnchorRow else { return }
        guard document.order.isEmpty == false else { return }
        let lastRow = document.order.count - 1
        let targetRow: Int = {
            if let ip = tableView.indexPathForRow(at: location) { return min(max(ip.row, 0), lastRow) }
            return location.y <= 0 ? 0 : lastRow
        }()

        let lower = min(anchor, targetRow)
        let upper = max(anchor, targetRow)
        let desired = Set(lower...upper)
        let current = Set((tableView.indexPathsForSelectedRows ?? []).map { $0.row })
        for row in current.subtracting(desired) {
            tableView.deselectRow(at: IndexPath(row: row, section: 0), animated: false)
        }
        for row in desired.subtracting(current) {
            let indexPath = IndexPath(row: row, section: 0)
            tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
            (tableView.cellForRow(at: indexPath) as? BlockSelectableCell)?.isSelectionMode = true
        }
        notifySelectionState()
    }

    @objc
    private func handleBackgroundTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        if isSelectionMode { return }
        if tableView.hasActiveDrag { return }

        let location = gesture.location(in: tableView)
        let hitView = tableView.hitTest(location, with: nil)
        if shouldIgnoreCanvasTap(on: hitView) { return }

        // Canvas feel: a tap that misses the text itself (row padding, the gap
        // between rows, side margins) lands on the nearest text block with the
        // caret at the tapped position — instead of doing nothing or jumping to
        // the end of the note.
        if let indexPath = nearestRowIndexPath(to: location) {
            let blockId = document.order[indexPath.row]
            guard let block = document.block(id: blockId) else { return }
            if case .media = block.content { return } // leave taps around media alone
            focusTextCell(at: indexPath, blockId: blockId, tapLocation: location)
            return
        }

        // Far below the content: keep the "continue writing at the end" behaviour.
        focusLastBlock()
    }

    /// Taps on the text itself or on in-cell controls (checkbox button, media
    /// actions) must keep their native behaviour.
    private func shouldIgnoreCanvasTap(on view: UIView?) -> Bool {
        var current = view
        while let v = current {
            if v is UITextView { return true }
            if v is UIControl { return true }
            current = v.superview
        }
        return false
    }

    /// The row containing the point, or the vertically nearest row when the point
    /// is in a gap. Returns nil for points well below the last row (the "empty
    /// canvas" area at the end of the note).
    private func nearestRowIndexPath(to location: CGPoint) -> IndexPath? {
        if let ip = tableView.indexPathForRow(at: location), ip.row < document.order.count { return ip }
        let count = document.order.count
        guard count > 0 else { return nil }

        let lastFrame = tableView.rectForRow(at: IndexPath(row: count - 1, section: 0))
        if location.y > lastFrame.maxY + 60 { return nil }

        var best: (indexPath: IndexPath, distance: CGFloat)?
        for row in 0..<count {
            let frame = tableView.rectForRow(at: IndexPath(row: row, section: 0))
            let distance: CGFloat
            if location.y < frame.minY {
                distance = frame.minY - location.y
            } else if location.y > frame.maxY {
                distance = location.y - frame.maxY
            } else {
                distance = 0
            }
            if best == nil || distance < best!.distance {
                best = (IndexPath(row: row, section: 0), distance)
            }
        }
        return best?.indexPath
    }

    private func focusTextCell(at indexPath: IndexPath, blockId: String, tapLocation: CGPoint) {
        guard let cell = tableView.cellForRow(at: indexPath) as? BlockCell else {
            focus(blockId: blockId)
            return
        }
        let textView = cell.textView
        let pointInTextView = tableView.convert(tapLocation, to: textView)
        let clamped = CGPoint(
            x: min(max(pointInTextView.x, 0), max(textView.bounds.width - 1, 0)),
            y: min(max(pointInTextView.y, 0), max(textView.bounds.height - 1, 0))
        )
        textView.becomeFirstResponder()
        if let position = textView.closestPosition(to: clamped) {
            textView.selectedTextRange = textView.textRange(from: position, to: position)
        } else {
            textView.selectedRange = NSRange(location: textView.attributedText.length, length: 0)
        }
    }

    private func notifySelectionState() {
        let count = tableView.indexPathsForSelectedRows?.count ?? 0
        onSelectionStateChange?(isSelectionMode, count)
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

private final class FullScreenImageViewController: UIViewController {
	private let imageView = UIImageView()
	private let scrollView = UIScrollView()
	private let contentView = UIView()
	private var isDismissingInteractively = false
	private let dismissDistance: CGFloat = 140
	private let dismissVelocity: CGFloat = 900

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		view.window?.endEditing(true)
		view.endEditing(true)
		UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		view.backgroundColor = .black

		scrollView.translatesAutoresizingMaskIntoConstraints = false
		scrollView.alwaysBounceVertical = false
		scrollView.alwaysBounceHorizontal = false
		scrollView.isScrollEnabled = false
		view.addSubview(scrollView)
		NSLayoutConstraint.activate([
			scrollView.topAnchor.constraint(equalTo: view.topAnchor),
			scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
		])

		contentView.translatesAutoresizingMaskIntoConstraints = false
		scrollView.addSubview(contentView)
		NSLayoutConstraint.activate([
			contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
			contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
			contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
			contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
			contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
			contentView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
		])

		imageView.translatesAutoresizingMaskIntoConstraints = false
		imageView.contentMode = .scaleAspectFit
		imageView.backgroundColor = .black
		contentView.addSubview(imageView)
		NSLayoutConstraint.activate([
			imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
			imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
			imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
		])

		let tap = UITapGestureRecognizer(target: self, action: #selector(didTapToDismiss))
		view.addGestureRecognizer(tap)

		let pan = UIPanGestureRecognizer(target: self, action: #selector(didPanToDismiss(_:)))
		view.addGestureRecognizer(pan)
	}

	func setImage(_ image: UIImage?) {
		imageView.image = image
	}

	@objc
	private func didTapToDismiss() {
		dismiss(animated: true)
	}

	@objc
	private func didPanToDismiss(_ recognizer: UIPanGestureRecognizer) {
		let translation = recognizer.translation(in: view)
		let y = max(translation.y, 0)
		let progress = min(y / max(dismissDistance, 1), 1)
		let scale = 1 - (progress * 0.06)

		switch recognizer.state {
		case .began:
			isDismissingInteractively = true

		case .changed:
			guard isDismissingInteractively else { return }
			contentView.transform = CGAffineTransform(translationX: 0, y: y).scaledBy(x: scale, y: scale)
			view.backgroundColor = UIColor.black.withAlphaComponent(1 - progress)

		case .ended, .cancelled:
			guard isDismissingInteractively else { return }
			isDismissingInteractively = false

			let velocity = recognizer.velocity(in: view)
			let shouldDismiss = y > dismissDistance || velocity.y > dismissVelocity

			if shouldDismiss {
				UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut]) { [weak self] in
					guard let self else { return }
					self.contentView.transform = CGAffineTransform(translationX: 0, y: self.view.bounds.height)
					self.view.backgroundColor = UIColor.black.withAlphaComponent(0)
				} completion: { [weak self] _ in
					self?.dismiss(animated: false)
				}
			} else {
				UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut]) { [weak self] in
					guard let self else { return }
					self.contentView.transform = .identity
					self.view.backgroundColor = .black
				}
			}

		default:
			break
		}
	}
}

private extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        let newTraits = fontDescriptor.symbolicTraits.union(traits)
        guard let descriptor = fontDescriptor.withSymbolicTraits(newTraits) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

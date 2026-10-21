import SwiftUI

public enum EditorBlockKind: Equatable, Codable {
	case text(text: String, style: TextStyle)
	/// `caption` is markdown shown under the photo, italic and muted. Consecutive image
	/// rows are one carousel in the editor; each row keeps its own caption.
	case image(reference: String, displayStyle: MediaBlockDisplayStyle, caption: String = "")
	case video(reference: String, displayStyle: MediaBlockDisplayStyle)

	private enum CodingKeys: String, CodingKey { case text, image, video }
	private enum TextKeys: String, CodingKey { case text, style }
	private enum MediaKeys: String, CodingKey { case reference, displayStyle, caption }

	/// Hand-written so snapshots stored before captions existed (Packd journals keep
	/// them as JSON) still decode: a missing caption is an empty one.
	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		if container.contains(.text) {
			let nested = try container.nestedContainer(keyedBy: TextKeys.self, forKey: .text)
			self = .text(text: try nested.decode(String.self, forKey: .text), style: try nested.decode(TextStyle.self, forKey: .style))
			return
		}
		if container.contains(.image) {
			let nested = try container.nestedContainer(keyedBy: MediaKeys.self, forKey: .image)
			self = .image(
				reference: try nested.decode(String.self, forKey: .reference),
				displayStyle: try nested.decode(MediaBlockDisplayStyle.self, forKey: .displayStyle),
				caption: try nested.decodeIfPresent(String.self, forKey: .caption) ?? ""
			)
			return
		}
		let nested = try container.nestedContainer(keyedBy: MediaKeys.self, forKey: .video)
		self = .video(
			reference: try nested.decode(String.self, forKey: .reference),
			displayStyle: try nested.decode(MediaBlockDisplayStyle.self, forKey: .displayStyle)
		)
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		switch self {
		case let .text(text, style):
			var nested = container.nestedContainer(keyedBy: TextKeys.self, forKey: .text)
			try nested.encode(text, forKey: .text)
			try nested.encode(style, forKey: .style)
		case let .image(reference, displayStyle, caption):
			var nested = container.nestedContainer(keyedBy: MediaKeys.self, forKey: .image)
			try nested.encode(reference, forKey: .reference)
			try nested.encode(displayStyle, forKey: .displayStyle)
			try nested.encode(caption, forKey: .caption)
		case let .video(reference, displayStyle):
			var nested = container.nestedContainer(keyedBy: MediaKeys.self, forKey: .video)
			try nested.encode(reference, forKey: .reference)
			try nested.encode(displayStyle, forKey: .displayStyle)
		}
	}
}

public struct EditorBlockSnapshot: Equatable, Codable {
    public let id: String
	public let kind: EditorBlockKind
    public let parentId: String?
    public let position: Int

    public init(id: String, kind: EditorBlockKind, parentId: String?, position: Int) {
        self.id = id
        self.kind = kind
        self.parentId = parentId
        self.position = position
    }
}

@MainActor
public final class BlocksEditorShellModel: ObservableObject {
    @Published public var isSelectionMode = false
    @Published public var selectedCount = 0
    @Published public var blocks: [EditorBlockSnapshot] = []

    fileprivate weak var controller: BlocksEditorViewController?
    private var pendingSetBlocks: [EditorBlockSnapshot]?

    /// Invoked when the user manually edits the dictation target block mid-recording.
    public var onDictationInterrupted: (() -> Void)? {
        didSet { controller?.onDictationInterrupted = onDictationInterrupted }
    }

    public init() {}

    public func done() {
        controller?.setSelectionMode(false)
    }

    func deleteSelected() {
        controller?.deleteSelectedBlocks()
    }

	func copySelected(format: EditorCopyFormat = .formatted) {
		controller?.copySelectedBlocksToPasteboard(format: format)
	}

	func cutSelected() {
		controller?.cutSelectedBlocksToPasteboard()
	}

	func selectAll() {
		controller?.selectAllBlocks()
	}

	public func focusLastTextBlock() {
		controller?.focusLastTextBlock()
	}

	public func insertText(_ text: String) {
		controller?.insertText(text)
	}

	public func insertNewBlockAtCursor() {
		controller?.insertNewBlockAtCursor()
	}

	/// Inserts the given blocks as ordinary editor rows at the current cursor position.
	public func insertBlocks(_ blocks: [EditorBlockSnapshot]) {
		controller?.insertBlocksAtCursor(blocks)
	}

	public func replaceDictationText(_ text: String) {
		controller?.replaceDictationText(text)
	}

	public func endDictation() {
		controller?.endDictation()
	}

	func selectedBlocks() -> [EditorBlockSnapshot] {
		controller?.selectedBlockSnapshots() ?? []
	}

    public func snapshotBlocks() -> [EditorBlockSnapshot] {
        controller?.snapshotBlocks() ?? []
    }

    public func setBlocks(_ blocks: [EditorBlockSnapshot]) {
        if let controller {
            controller.setBlocks(blocks)
        } else {
            pendingSetBlocks = blocks
        }
    }

    fileprivate func consumePendingSetBlocks() -> [EditorBlockSnapshot]? {
        defer { pendingSetBlocks = nil }
        return pendingSetBlocks
    }
}

public struct BlocksEditorSwiftUIShellView: View {
    @ObservedObject var model: BlocksEditorShellModel
	var topInset: AnyView? = nil
	var autoFocusOnAppear: Bool = true
	var onSendToAnotherNote: (([EditorBlockSnapshot]) -> Void)? = nil
	var onLinkToNote: (() -> Void)? = nil
	var onOpenURL: ((URL) -> Void)? = nil
	var onInsertLocation: (() -> Void)? = nil
	/// Fired after a copy from selection mode (button, ⌘C, ⌘⇧C, long-press menu) with
	/// the format that was written, so the host can word its feedback.
	var onCopySelection: ((EditorCopyFormat) -> Void)? = nil
	var onCutSelection: (() -> Void)? = nil
	var toolbarTrailing: AnyView? = nil

	public init(
		model: BlocksEditorShellModel,
		topInset: AnyView? = nil,
		autoFocusOnAppear: Bool = true,
		onSendToAnotherNote: (([EditorBlockSnapshot]) -> Void)? = nil,
		onLinkToNote: (() -> Void)? = nil,
		onOpenURL: ((URL) -> Void)? = nil,
		onInsertLocation: (() -> Void)? = nil,
		onCopySelection: ((EditorCopyFormat) -> Void)? = nil,
		onCutSelection: (() -> Void)? = nil,
		toolbarTrailing: AnyView? = nil
	) {
		self.model = model
		self.topInset = topInset
		self.autoFocusOnAppear = autoFocusOnAppear
		self.onSendToAnotherNote = onSendToAnotherNote
		self.onLinkToNote = onLinkToNote
		self.onOpenURL = onOpenURL
		self.onCopySelection = onCopySelection
		self.onCutSelection = onCutSelection
		self.toolbarTrailing = toolbarTrailing
		self.onInsertLocation = onInsertLocation
	}

    public var body: some View {
		BlocksEditorViewControllerRepresentable(
			model: model,
			autoFocusOnAppear: autoFocusOnAppear,
			onLinkToNote: onLinkToNote,
			onOpenURL: onOpenURL,
			onInsertLocation: onInsertLocation,
			onCopySelection: onCopySelection,
			onCutSelection: onCutSelection
		)
		.tint(Color(uiColor: KonuqEditor.theme.accent))
		.toolbar {
			if model.isSelectionMode {
				ToolbarItem(placement: .topBarTrailing) {
					Button(L.t("editor.done")) {
						model.done()
					}
				}
			} else if let toolbarTrailing {
				if #available(iOS 26.0, *) {
					ToolbarItem(placement: .topBarTrailing) {
						toolbarTrailing
					}
					.sharedBackgroundVisibility(.hidden)
				} else {
					ToolbarItem(placement: .topBarTrailing) {
						toolbarTrailing
					}
				}
			}
		}
		.safeAreaInset(edge: .top, spacing: 0) {
			if let topInset {
				topInset
			}
		}
		.safeAreaInset(edge: .bottom, spacing: 0) {
			if model.isSelectionMode {
				SelectionActionBar(
					selectedCount: model.selectedCount,
					totalCount: model.blocks.count,
					onSelectAll: {
						model.selectAll()
					},
					onCopy: { format in
						model.copySelected(format: format)
						model.done()
						onCopySelection?(format)
					},
					onCut: {
						model.cutSelected()
						model.done()
						onCutSelection?()
					},
					onSend: {
						let selected = model.selectedBlocks()
						if !selected.isEmpty {
							onSendToAnotherNote?(selected)
						}
					},
					onDelete: {
						model.deleteSelected()
						model.done()
					}
				)
			}
		}
    }
}

private struct SelectionActionBar: View {
    let selectedCount: Int
	let totalCount: Int
	let onSelectAll: () -> Void
	let onCopy: (EditorCopyFormat) -> Void
	let onCut: () -> Void
	let onSend: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 10) {
			Button {
				onSelectAll()
			} label: {
				Label(L.t("editor.select_all"), systemImage: "checkmark.circle")
					.labelStyle(.iconOnly)
					.frame(width: 38, height: 34)
			}
			.buttonStyle(.plain)
			.disabled(selectedCount == 0 || selectedCount == totalCount)

			// Tap copies formatted text; press and hold offers the markdown source.
			Menu {
				Button {
					onCopy(.markdown)
				} label: {
					Label(L.t("editor.copy_markdown"), systemImage: "number")
				}
			} label: {
				Label(L.t("editor.copy"), systemImage: "doc.on.doc")
					.labelStyle(.iconOnly)
					.frame(width: 38, height: 34)
			} primaryAction: {
				onCopy(.formatted)
			}
			.menuStyle(.button)
			.buttonStyle(.plain)
			.disabled(selectedCount == 0)

			Button {
				onCut()
			} label: {
				Label(L.t("editor.cut"), systemImage: "scissors")
					.labelStyle(.iconOnly)
					.frame(width: 38, height: 34)
			}
			.buttonStyle(.plain)
			.disabled(selectedCount == 0)

			Button {
				onSend()
			} label: {
				Label(L.t("editor.send"), systemImage: "arrowshape.turn.up.right")
					.labelStyle(.iconOnly)
					.frame(width: 38, height: 34)
			}
			.buttonStyle(.plain)
			.disabled(selectedCount == 0)

			Button {
				onDelete()
			} label: {
				Label(L.t("editor.delete"), systemImage: "trash")
					.labelStyle(.iconOnly)
					.frame(width: 38, height: 34)
			}
			.buttonStyle(.plain)
			.foregroundStyle(.red)
			.disabled(selectedCount == 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
    
    @ViewBuilder
    private var background: some View {
        if #available(iOS 15.0, *) {
            Rectangle().fill(.ultraThinMaterial)
        } else {
            Color(UIColor.systemBackground).opacity(0.95)
        }
    }
}

private struct BlocksEditorViewControllerRepresentable: UIViewControllerRepresentable {
    @ObservedObject var model: BlocksEditorShellModel
	var autoFocusOnAppear: Bool
	var onLinkToNote: (() -> Void)?
	var onOpenURL: ((URL) -> Void)?
	var onInsertLocation: (() -> Void)?
	var onCopySelection: ((EditorCopyFormat) -> Void)?
	var onCutSelection: (() -> Void)?

    func makeUIViewController(context: Context) -> BlocksEditorViewController {
        let controller = BlocksEditorViewController()
		controller.autoFocusOnAppear = autoFocusOnAppear
		controller.onLinkToNote = onLinkToNote
		controller.onOpenURL = onOpenURL
		controller.onInsertLocation = onInsertLocation
        controller.onSelectionStateChange = { [weak coordinator = context.coordinator] isSelectionMode, selectedCount in
            coordinator?.publishSelectionState(isSelectionMode: isSelectionMode, selectedCount: selectedCount)
        }
        controller.onBlocksChanged = { [weak coordinator = context.coordinator] snapshots in
            coordinator?.publishBlocks(snapshots)
        }
        controller.onCopyShortcut = onCopySelection
        controller.onCutShortcut = onCutSelection
        context.coordinator.attach(controller: controller)
        return controller
    }

    func updateUIViewController(_ uiViewController: BlocksEditorViewController, context: Context) {
		uiViewController.autoFocusOnAppear = autoFocusOnAppear
		uiViewController.onLinkToNote = onLinkToNote
		uiViewController.onOpenURL = onOpenURL
		uiViewController.onInsertLocation = onInsertLocation
		uiViewController.onCopyShortcut = onCopySelection
		uiViewController.onCutShortcut = onCutSelection
	}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }
    
    @MainActor
    final class Coordinator {
        private let model: BlocksEditorShellModel
        private weak var controller: BlocksEditorViewController?
        
        init(model: BlocksEditorShellModel) {
            self.model = model
        }
        
        func attach(controller: BlocksEditorViewController) {
            self.controller = controller
            model.controller = controller
            controller.onDictationInterrupted = model.onDictationInterrupted
            if let pending = model.consumePendingSetBlocks() {
                controller.setBlocks(pending)
            }
        }
        
        func publishSelectionState(isSelectionMode: Bool, selectedCount: Int) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.model.isSelectionMode = isSelectionMode
                self.model.selectedCount = selectedCount
            }
        }

        func publishBlocks(_ blocks: [EditorBlockSnapshot]) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.model.blocks = blocks
            }
        }
    }
}

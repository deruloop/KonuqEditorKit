import SwiftUI

public enum EditorBlockKind: Equatable, Codable {
	case text(text: String, style: TextStyle)
	case image(reference: String, displayStyle: MediaBlockDisplayStyle)
	case video(reference: String, displayStyle: MediaBlockDisplayStyle)
	case stop(EditorStopData)
	case day(EditorDayData)
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

    public init() {}

    public func done() {
        controller?.setSelectionMode(false)
    }

    func deleteSelected() {
        controller?.deleteSelectedBlocks()
    }

	func copySelected() {
		controller?.copySelectedBlocksToPasteboard()
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
	var onTapStop: ((String) -> Void)? = nil
	var onTapDay: ((String) -> Void)? = nil
	var onCopySelection: (() -> Void)? = nil
	var onCutSelection: (() -> Void)? = nil
	var toolbarTrailing: AnyView? = nil

	public init(
		model: BlocksEditorShellModel,
		topInset: AnyView? = nil,
		autoFocusOnAppear: Bool = true,
		onSendToAnotherNote: (([EditorBlockSnapshot]) -> Void)? = nil,
		onLinkToNote: (() -> Void)? = nil,
		onOpenURL: ((URL) -> Void)? = nil,
		onTapStop: ((String) -> Void)? = nil,
		onTapDay: ((String) -> Void)? = nil,
		onCopySelection: (() -> Void)? = nil,
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
		self.onTapStop = onTapStop
		self.onTapDay = onTapDay
	}

    public var body: some View {
		BlocksEditorViewControllerRepresentable(
			model: model,
			autoFocusOnAppear: autoFocusOnAppear,
			onLinkToNote: onLinkToNote,
			onOpenURL: onOpenURL,
			onTapStop: onTapStop,
			onTapDay: onTapDay
		)
		.tint(Color(uiColor: KonuqEditor.theme.accent))
		.toolbar {
			if model.isSelectionMode {
				ToolbarItem(placement: .topBarTrailing) {
					Button("Done") {
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
					onCopy: {
						model.copySelected()
						model.done()
						onCopySelection?()
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
	let onCopy: () -> Void
	let onCut: () -> Void
	let onSend: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 10) {
			Button {
				onSelectAll()
			} label: {
				Label("Select All", systemImage: "checkmark.circle")
					.labelStyle(.iconOnly)
					.frame(width: 38, height: 34)
			}
			.buttonStyle(.plain)
			.disabled(selectedCount == 0 || selectedCount == totalCount)

			Button {
				onCopy()
			} label: {
				Label("Copy", systemImage: "doc.on.doc")
					.labelStyle(.iconOnly)
					.frame(width: 38, height: 34)
			}
			.buttonStyle(.plain)
			.disabled(selectedCount == 0)

			Button {
				onCut()
			} label: {
				Label("Cut", systemImage: "scissors")
					.labelStyle(.iconOnly)
					.frame(width: 38, height: 34)
			}
			.buttonStyle(.plain)
			.disabled(selectedCount == 0)

			Button {
				onSend()
			} label: {
				Label("Send", systemImage: "arrowshape.turn.up.right")
					.labelStyle(.iconOnly)
					.frame(width: 38, height: 34)
			}
			.buttonStyle(.plain)
			.disabled(selectedCount == 0)

			Button {
				onDelete()
			} label: {
				Label("Delete", systemImage: "trash")
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
	var onTapStop: ((String) -> Void)?
	var onTapDay: ((String) -> Void)?
    
    func makeUIViewController(context: Context) -> BlocksEditorViewController {
        let controller = BlocksEditorViewController()
		controller.autoFocusOnAppear = autoFocusOnAppear
		controller.onLinkToNote = onLinkToNote
		controller.onOpenURL = onOpenURL
		controller.onTapStop = onTapStop
		controller.onTapDay = onTapDay
        controller.onSelectionStateChange = { [weak coordinator = context.coordinator] isSelectionMode, selectedCount in
            coordinator?.publishSelectionState(isSelectionMode: isSelectionMode, selectedCount: selectedCount)
        }
        controller.onBlocksChanged = { [weak coordinator = context.coordinator] snapshots in
            coordinator?.publishBlocks(snapshots)
        }
        context.coordinator.attach(controller: controller)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: BlocksEditorViewController, context: Context) {
		uiViewController.autoFocusOnAppear = autoFocusOnAppear
		uiViewController.onLinkToNote = onLinkToNote
		uiViewController.onOpenURL = onOpenURL
		uiViewController.onTapStop = onTapStop
		uiViewController.onTapDay = onTapDay
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

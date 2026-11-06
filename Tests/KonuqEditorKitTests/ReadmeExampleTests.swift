import SwiftUI
import XCTest
import KonuqEditorKit

/// The usage example from the README, kept here so it keeps compiling against the
/// public API. If this file stops building, the README needs the same change.
private struct NoteScreen: View {
	@StateObject private var editor = BlocksEditorShellModel()

	var body: some View {
		BlocksEditorSwiftUIShellView(
			model: editor,
			onOpenURL: { url in UIApplication.shared.open(url) }
		)
		.onAppear {
			editor.setBlocks([
				EditorBlockSnapshot(id: UUID().uuidString, kind: .text(text: "Iceland, day two", style: .title), parentId: nil, position: 0),
				EditorBlockSnapshot(id: UUID().uuidString, kind: .text(text: "Up early for the **waterfall**.", style: .text), parentId: nil, position: 1),
				EditorBlockSnapshot(id: UUID().uuidString, kind: .text(text: "[ ] Book the glacier walk", style: .checkbox), parentId: nil, position: 2)
			])
		}
		.onChange(of: editor.blocks) { _, blocks in
			print(blocks.count)
		}
	}
}

final class ReadmeExampleTests: XCTestCase {
	@MainActor
	func testExampleBuildsAView() {
		_ = NoteScreen().body
	}

	/// Snapshots written before captions existed have no `caption` key and still decode.
	func testImageSnapshotWithoutCaptionDecodes() throws {
		let json = #"[{"id":"a","kind":{"image":{"reference":"media:a.jpg","displayStyle":"medium"}},"position":0}]"#
		let blocks = try JSONDecoder().decode([EditorBlockSnapshot].self, from: Data(json.utf8))
		XCTAssertEqual(blocks.first?.kind, .image(reference: "media:a.jpg", displayStyle: .medium, caption: ""))
	}

	func testAppearanceSettersFromTheReadme() {
		KonuqEditor.theme = .app(accent: .systemIndigo)
		KonuqEditor.preferredLanguageCode = "it"
		KonuqEditor.theme = .konuq
		KonuqEditor.preferredLanguageCode = nil
	}
}

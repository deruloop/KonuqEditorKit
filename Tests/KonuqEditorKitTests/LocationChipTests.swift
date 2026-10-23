import XCTest
import UIKit
@testable import KonuqEditorKit

@MainActor
final class LocationChipTests: XCTestCase {
	private let place = EditorLocationLink.Place(
		name: "Saiho-ji", latitude: 34.9922, longitude: 135.6839, area: "Kyoto", tintHex: "#3b82f6"
	)

	func test_linkCarriesAreaAndTint_andParsesBack() throws {
		let markdown = EditorLocationLink.markdown(for: place)
		XCTAssertTrue(markdown.hasPrefix("[📍 Saiho-ji](https://maps.apple.com/?"))
		let url = try XCTUnwrap(URL(string: String(markdown.split(separator: "(", maxSplits: 1)[1].dropLast())))
		let parsed = try XCTUnwrap(EditorLocationLink.place(from: url))
		XCTAssertEqual(parsed.name, "Saiho-ji")
		XCTAssertEqual(parsed.area, "Kyoto")
		XCTAssertEqual(parsed.tintHex, "3B82F6")
		XCTAssertEqual(parsed.latitude ?? 0, 34.9922, accuracy: 0.0001)
	}

	func test_oldLinkWithoutAreaOrTintStillParses() throws {
		let url = try XCTUnwrap(URL(string: "https://maps.apple.com/?q=Pantheon&ll=41.8986,12.4768"))
		let parsed = try XCTUnwrap(EditorLocationLink.place(from: url))
		XCTAssertEqual(parsed.name, "Pantheon")
		XCTAssertNil(parsed.area)
		XCTAssertNil(parsed.tintHex)
	}

	func test_parenthesesInNamesDoNotBreakTheMarkdown() {
		let markdown = EditorLocationLink.markdown(name: "Bakery (yuum?)", area: "London")
		XCTAssertFalse(markdown.dropFirst().contains("[") && markdown.filter { $0 == ")" }.count > 1,
					   "a ')' inside the URL would end the markdown link early: \(markdown)")
	}

	func test_cellShowsTheLinkAsOneChip_andSerializesTheSameMarkdown() throws {
		let link = EditorLocationLink.markdown(for: place)
		let markdown = "Start at \(link) before the crowds"
		let controller = BlocksEditorViewController(initialEmptyStyle: .text)
		let cell = BlockCell(style: .default, reuseIdentifier: nil)
		cell.frame = CGRect(x: 0, y: 0, width: 390, height: 120)
		cell.delegate = controller
		cell.configure(blockId: "b1", text: NSAttributedString(string: markdown), style: .text, isFirstBlock: false)

		let shown = cell.textView.attributedText!
		var chips: [LocationChipAttachment] = []
		shown.enumerateAttribute(.attachment, in: NSRange(location: 0, length: shown.length)) { value, _, _ in
			if let chip = value as? LocationChipAttachment { chips.append(chip) }
		}
		XCTAssertEqual(chips.count, 1)
		XCTAssertEqual(shown.string, "Start at \u{FFFC} before the crowds")
		XCTAssertEqual(chips.first?.place.area, "Kyoto")

		// The chip draws a non-empty image.
		let container = cell.textView.textContainer
		let image = chips.first?.image(forBounds: .zero, textContainer: container, characterIndex: 9)
		XCTAssertNotNil(image)
		XCTAssertGreaterThan(image?.size.width ?? 0, 60)

		// Saving writes back exactly the markdown that was loaded.
		XCTAssertEqual(controller.blockCell(cell, markdownFor: shown), markdown)

		// Copy sees the label, not the attachment character.
		XCTAssertEqual(LocationChips.expanded(shown).string, "Start at 📍 Saiho-ji before the crowds")
	}

	func test_ordinaryLinksStayLinks() {
		let markdown = "See [the site](https://konuq.app) today"
		let controller = BlocksEditorViewController(initialEmptyStyle: .text)
		let cell = BlockCell(style: .default, reuseIdentifier: nil)
		cell.delegate = controller
		cell.configure(blockId: "b1", text: NSAttributedString(string: markdown), style: .text, isFirstBlock: false)
		XCTAssertEqual(cell.textView.attributedText.string, "See the site today")
		XCTAssertEqual(controller.blockCell(cell, markdownFor: cell.textView.attributedText), markdown)
	}

	func test_hexRoundTrip() {
		let color = EditorLocationLink.color(fromHex: "EC4899")!
		XCTAssertEqual(EditorLocationLink.hex(from: color), "EC4899")
		XCTAssertNil(EditorLocationLink.color(fromHex: "nothex"))
	}
}

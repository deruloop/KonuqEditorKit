import UIKit
import SwiftUI

extension NSAttributedString.Key {
	/// The `📍 name` label of a location shown as a chip. The chip itself is one attachment
	/// character, so the serializer reads the label from here to write `[label](url)` back.
	static let appInlineLocationLabel = NSAttributedString.Key("app.inline.location.label")
}

/// A location drawn inline as one atomic character: a rounded, tinted pill holding the pin,
/// the place name, its area and a small arrow. The caret cannot enter it, backspace removes
/// it whole, and a tap goes through the ordinary link path (`.link` sits on the character).
///
/// TextKit 1 renders attachments as images, so the pill is drawn on demand in
/// `image(forBounds:…)` with the colours of the current appearance. The cell invalidates
/// its display when the appearance changes.
final class LocationChipAttachment: NSTextAttachment {
	let place: EditorLocationLink.Place
	let label: String
	let font: UIFont

	init(place: EditorLocationLink.Place, label: String, font: UIFont) {
		self.place = place
		self.label = label
		self.font = font
		super.init(data: nil, ofType: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	// MARK: Layout

	private static let horizontalPadding: CGFloat = 8
	private static let verticalPadding: CGFloat = 3
	private static let spacing: CGFloat = 5

	private var tint: UIColor {
		place.tintHex.flatMap(EditorLocationLink.color(fromHex:)) ?? KonuqEditor.theme.accent
	}

	private var nameFont: UIFont {
		let descriptor = font.fontDescriptor.addingAttributes([
			.traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.semibold]
		])
		return UIFont(descriptor: descriptor, size: font.pointSize * 0.94)
	}

	private var areaFont: UIFont {
		font.withSize(font.pointSize * 0.86)
	}

	private var displayName: String {
		var name = label.trimmingCharacters(in: .whitespaces)
		if name.hasPrefix("📍") { name.removeFirst() }
		name = name.trimmingCharacters(in: .whitespaces)
		return name.isEmpty ? place.name : name
	}

	private var displayArea: String? {
		guard let area = place.area, area.caseInsensitiveCompare(displayName) != .orderedSame else { return nil }
		return area
	}

	private struct Metrics {
		let size: CGSize
		let pinWidth: CGFloat
		let nameWidth: CGFloat
		let areaWidth: CGFloat
		let arrowWidth: CGFloat
	}

	private func metrics(maxWidth: CGFloat) -> Metrics {
		let pin = ("📍" as NSString).size(withAttributes: [.font: areaFont]).width
		let arrow = areaFont.pointSize * 0.7
		let naturalName = (displayName as NSString).size(withAttributes: [.font: nameFont]).width.rounded(.up)
		let naturalArea = displayArea.map { ($0 as NSString).size(withAttributes: [.font: areaFont]).width.rounded(.up) } ?? 0
		let fixed = Self.horizontalPadding * 2 + pin + Self.spacing + arrow + Self.spacing
			+ (displayArea == nil ? 0 : Self.spacing)
		var nameWidth = naturalName
		var areaWidth = naturalArea
		let available = max(60, maxWidth - fixed)
		if nameWidth + areaWidth > available {
			// The area gives way first, then the name is truncated.
			areaWidth = min(areaWidth, max(0, available * 0.35))
			nameWidth = min(nameWidth, max(24, available - areaWidth))
		}
		let height = (font.lineHeight + Self.verticalPadding * 2).rounded(.up)
		let width = (fixed + nameWidth + areaWidth).rounded(.up)
		return Metrics(size: CGSize(width: width, height: height), pinWidth: pin, nameWidth: nameWidth, areaWidth: areaWidth, arrowWidth: arrow)
	}

	private func maxWidth(for container: NSTextContainer?) -> CGFloat {
		guard let container, container.size.width > 0, container.size.width < .greatestFiniteMagnitude else { return 320 }
		return container.size.width - container.lineFragmentPadding * 2 - 2
	}

	override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: CGRect, glyphPosition position: CGPoint, characterIndex charIndex: Int) -> CGRect {
		let size = metrics(maxWidth: maxWidth(for: textContainer)).size
		// Centre the pill on the text's x-height band so it sits on the line like a word.
		let y = (font.descender - Self.verticalPadding).rounded()
		return CGRect(x: 0, y: y, width: size.width, height: size.height)
	}

	override func image(forBounds imageBounds: CGRect, textContainer: NSTextContainer?, characterIndex charIndex: Int) -> UIImage? {
		let m = metrics(maxWidth: maxWidth(for: textContainer))
		let traits = UITraitCollection.current
		let tint = self.tint.resolvedColor(with: traits)
		let primary = KonuqEditor.theme.primaryText.resolvedColor(with: traits)
		let secondary = KonuqEditor.theme.secondaryText.resolvedColor(with: traits)
		let isDark = traits.userInterfaceStyle == .dark

		let format = UIGraphicsImageRendererFormat.preferred()
		format.opaque = false
		return UIGraphicsImageRenderer(size: m.size, format: format).image { _ in
			let rect = CGRect(origin: .zero, size: m.size).insetBy(dx: 0.5, dy: 0.5)
			let pill = UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2)
			tint.withAlphaComponent(isDark ? 0.26 : 0.14).setFill()
			pill.fill()
			tint.withAlphaComponent(isDark ? 0.55 : 0.38).setStroke()
			pill.lineWidth = 1
			pill.stroke()

			var x = Self.horizontalPadding
			func baselineY(for f: UIFont) -> CGFloat { (m.size.height - f.lineHeight) / 2 }

			("📍" as NSString).draw(at: CGPoint(x: x, y: baselineY(for: areaFont)), withAttributes: [.font: areaFont])
			x += m.pinWidth + Self.spacing

			let truncating = NSMutableParagraphStyle()
			truncating.lineBreakMode = .byTruncatingTail
			(displayName as NSString).draw(
				in: CGRect(x: x, y: baselineY(for: nameFont), width: m.nameWidth, height: nameFont.lineHeight),
				withAttributes: [.font: nameFont, .foregroundColor: primary, .paragraphStyle: truncating]
			)
			x += m.nameWidth + Self.spacing

			if let area = displayArea, m.areaWidth > 8 {
				(area as NSString).draw(
					in: CGRect(x: x, y: baselineY(for: areaFont), width: m.areaWidth, height: areaFont.lineHeight),
					withAttributes: [.font: areaFont, .foregroundColor: secondary, .paragraphStyle: truncating]
				)
				x += m.areaWidth + Self.spacing
			}

			let config = UIImage.SymbolConfiguration(pointSize: m.arrowWidth, weight: .semibold)
			if let arrow = UIImage(systemName: "arrow.up.right", withConfiguration: config)?.withTintColor(tint, renderingMode: .alwaysOriginal) {
				let y = (m.size.height - arrow.size.height) / 2
				arrow.draw(at: CGPoint(x: x, y: y))
			}
		}
	}
}

enum LocationChips {
	/// The chip text with every chip replaced by its `📍 name` label, keeping the link: what
	/// copy, cut and any plain-text reader should see.
	static func expanded(_ text: NSAttributedString) -> NSAttributedString {
		guard text.length > 0 else { return text }
		let out = NSMutableAttributedString(attributedString: text)
		var ranges: [(NSRange, String)] = []
		out.enumerateAttribute(.appInlineLocationLabel, in: NSRange(location: 0, length: out.length), options: .reverse) { value, range, _ in
			if let label = value as? String { ranges.append((range, label)) }
		}
		for (range, label) in ranges {
			var attrs = out.attributes(at: range.location, effectiveRange: nil)
			attrs.removeValue(forKey: .attachment)
			attrs.removeValue(forKey: .appInlineLocationLabel)
			out.replaceCharacters(in: range, with: NSAttributedString(string: label, attributes: attrs))
		}
		return out
	}
}

// MARK: - SwiftUI preview of the same chip, for pickers and sheets

/// The chip as a SwiftUI view, matching what the editor draws, for previews in a host's
/// own UI (the location sheet uses it while the colour is chosen).
public struct EditorLocationChipView: View {
	let place: EditorLocationLink.Place
	let tint: Color

	public init(place: EditorLocationLink.Place, tint: Color) {
		self.place = place
		self.tint = tint
	}

	public var body: some View {
		HStack(spacing: 5) {
			Text("📍").font(.footnote)
			Text(place.name)
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(Color(uiColor: KonuqEditor.theme.primaryText))
				.lineLimit(1)
			if let area = place.area, area.caseInsensitiveCompare(place.name) != .orderedSame {
				Text(area)
					.font(.footnote)
					.foregroundStyle(Color(uiColor: KonuqEditor.theme.secondaryText))
					.lineLimit(1)
			}
			Image(systemName: "arrow.up.right")
				.font(.caption2.weight(.semibold))
				.foregroundStyle(tint)
		}
		.padding(.horizontal, 10)
		.padding(.vertical, 5)
		.background(Capsule().fill(tint.opacity(0.14)))
		.overlay(Capsule().stroke(tint.opacity(0.38), lineWidth: 1))
	}
}

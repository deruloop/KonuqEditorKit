import UIKit

private extension NSAttributedString.Key {
	static let appInlineBold = NSAttributedString.Key("app.inline.bold")
	static let appInlineItalic = NSAttributedString.Key("app.inline.italic")
	static let appInlineCode = NSAttributedString.Key("app.inline.code")
	static let appInlineStrike = NSAttributedString.Key("app.inline.strike")
	static let appInlineLinkUrl = NSAttributedString.Key("app.inline.link.url")
	static let appInlineNoteLinkId = NSAttributedString.Key("app.inline.note.link.id")
	static let appInlineCheckboxAutoStrike = NSAttributedString.Key("app.inline.checkbox.auto.strike")
	static let appInlineCheckboxHidden = NSAttributedString.Key("app.inline.checkbox.hidden")
}

/// The formatted (non-markdown) forms of editor content for the pasteboard: RTF for
/// Pages/Notes/TextEdit/Mail, HTML for browsers, Notion, Google Docs and Slack, and a
/// plain string with no markdown markers as the fallback for everything else.
struct ClipboardRichContent {
	let rtf: Data?
	let html: String
	let plain: String

	/// One pasteboard item with every representation, plus any extra private types
	/// (the lossless block payload for in-app paste).
	func pasteboardItem(extra: [String: Any] = [:]) -> [String: Any] {
		var item: [String: Any] = extra
		item[EditorClipboard.plainText] = plain
		item[EditorClipboard.html] = html
		if let rtf { item[EditorClipboard.rtf] = rtf }
		return item
	}
}

enum ClipboardExport {
	/// One paragraph of output: a block's style and its inline-attributed text. The
	/// inline formatting is read from the `app.inline.*` attributes the editor stores
	/// (plus `.link` / strikethrough), never from the fonts, so the export does not
	/// depend on which display font the editor is using.
	struct Paragraph {
		let style: TextStyle
		let text: NSAttributedString
	}

	private struct Run {
		let text: String
		let bold: Bool
		let italic: Bool
		let strike: Bool
		let code: Bool
		let link: URL?
	}

	// MARK: - Entry points

	static func richContent(paragraphs: [Paragraph]) -> ClipboardRichContent {
		let attributed = NSMutableAttributedString()
		var htmlParts: [String] = []
		var plainParts: [String] = []
		var openList: String? = nil // "ul" while consecutive bullet/checkbox items are open

		func closeList() {
			if let tag = openList { htmlParts.append("</\(tag)>") }
			openList = nil
		}

		for paragraph in paragraphs {
			let (checked, body) = splitCheckboxPrefix(paragraph.text, style: paragraph.style)
			let runs = inlineRuns(body, allowLinks: paragraph.style != .code)
			let plainBody = runs.map(\.text).joined()
			guard !plainBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

			// Plain text
			plainParts.append(plainPrefix(for: paragraph.style, checked: checked) + plainBody)

			// HTML
			let inlineHTML = runs.map(htmlFragment).joined()
			switch paragraph.style {
			case .listBullet, .checkbox:
				if openList == nil { htmlParts.append("<ul>"); openList = "ul" }
				let mark = paragraph.style == .checkbox ? ((checked ? "\u{2611}" : "\u{2610}") + " ") : ""
				htmlParts.append("<li>\(mark)\(inlineHTML)</li>")
			default:
				closeList()
				htmlParts.append(htmlBlock(for: paragraph.style, body: paragraph.style == .code ? escapeHTML(plainBody) : inlineHTML))
			}

			// RTF
			attributed.append(rtfParagraph(runs: runs, style: paragraph.style, checked: checked, terminated: true))
		}
		closeList()

		return ClipboardRichContent(
			rtf: rtfData(from: attributed),
			html: wrapHTMLDocument(htmlParts.joined(separator: "\n")),
			plain: plainParts.joined(separator: "\n")
		)
	}

	/// A text selection inside one block: inline formatting only, no list marks,
	/// the block style just picks the heading level.
	static func richContent(inline text: NSAttributedString, style: TextStyle) -> ClipboardRichContent {
		let runs = inlineRuns(text, allowLinks: style != .code)
		let plain = runs.map(\.text).joined()
		let inlineHTML = style == .code ? escapeHTML(plain) : runs.map(htmlFragment).joined()
		let attributed = rtfParagraph(runs: runs, style: style, checked: false, withPrefix: false)
		return ClipboardRichContent(
			rtf: rtfData(from: attributed),
			html: wrapHTMLDocument(htmlBlock(for: style, body: inlineHTML)),
			plain: plain
		)
	}

	// MARK: - Inline runs

	/// Walks attribute runs and also resolves literal `[label](url)` markdown links
	/// (the form links take in block snapshots) into link runs.
	private static func inlineRuns(_ source: NSAttributedString, allowLinks: Bool) -> [Run] {
		let resolved = allowLinks ? resolvingMarkdownLinks(source) : source
		var runs: [Run] = []
		let full = NSRange(location: 0, length: resolved.length)
		resolved.enumerateAttributes(in: full, options: []) { attrs, range, _ in
			if attrs[.appInlineCheckboxHidden] != nil { return }
			let substring = (resolved.string as NSString).substring(with: range)
			guard !substring.isEmpty else { return }
			let link: URL? = {
				guard allowLinks else { return nil }
				if let u = attrs[.link] as? URL { return exportable(u) }
				if let s = attrs[.link] as? String, let u = URL(string: s) { return exportable(u) }
				if let s = attrs[.appInlineLinkUrl] as? String, let u = URL(string: s) { return exportable(u) }
				return nil
			}()
			let strike = boolAttr(attrs, .appInlineCheckboxAutoStrike)
				? false
				: (boolAttr(attrs, .appInlineStrike) || attrs[.strikethroughStyle] != nil)
			runs.append(Run(
				text: substring,
				bold: boolAttr(attrs, .appInlineBold),
				italic: boolAttr(attrs, .appInlineItalic),
				strike: strike,
				code: boolAttr(attrs, .appInlineCode),
				link: link
			))
		}
		return runs
	}

	/// Only web links survive the trip out of the app; `konuq://` note links and map
	/// links would be dead in another app, so they export as their label.
	private static func exportable(_ url: URL) -> URL? {
		guard let scheme = url.scheme?.lowercased() else { return nil }
		return ["http", "https", "mailto"].contains(scheme) ? url : nil
	}

	private static let markdownLinkRegex = try! NSRegularExpression(
		pattern: "\\[([^\\]]+)\\]\\(([^\\s\\)]+)\\)",
		options: []
	)

	private static func resolvingMarkdownLinks(_ source: NSAttributedString) -> NSAttributedString {
		let ns = source.string as NSString
		let matches = markdownLinkRegex.matches(in: source.string, options: [], range: NSRange(location: 0, length: ns.length))
		guard !matches.isEmpty else { return source }
		let result = NSMutableAttributedString(attributedString: source)
		for match in matches.reversed() {
			let label = ns.substring(with: match.range(at: 1))
				.replacingOccurrences(of: "\\[", with: "[")
				.replacingOccurrences(of: "\\]", with: "]")
			let target = ns.substring(with: match.range(at: 2))
			var attrs = source.attributes(at: match.range.location, effectiveRange: nil)
			attrs[.link] = target
			result.replaceCharacters(in: match.range, with: NSAttributedString(string: label, attributes: attrs))
		}
		return result
	}

	/// The "[ ] " / "[x] " prefix of a checkbox is markup: strip it and keep the state.
	private static func splitCheckboxPrefix(_ text: NSAttributedString, style: TextStyle) -> (checked: Bool, body: NSAttributedString) {
		guard style == .checkbox, text.length >= 4 else { return (false, text) }
		let prefix = (text.string as NSString).substring(to: 4).lowercased()
		guard prefix == "[ ] " || prefix == "[x] " else { return (false, text) }
		return (prefix == "[x] ", text.attributedSubstring(from: NSRange(location: 4, length: text.length - 4)))
	}

	private static func boolAttr(_ attrs: [NSAttributedString.Key: Any], _ key: NSAttributedString.Key) -> Bool {
		if let b = attrs[key] as? Bool { return b }
		if let n = attrs[key] as? NSNumber { return n.boolValue }
		return false
	}

	// MARK: - Plain

	private static func plainPrefix(for style: TextStyle, checked: Bool) -> String {
		switch style {
		case .listBullet: return "\u{2022} "
		case .checkbox: return (checked ? "\u{2611}" : "\u{2610}") + " "
		default: return ""
		}
	}

	// MARK: - HTML

	private static func htmlBlock(for style: TextStyle, body: String) -> String {
		switch style {
		case .title: return "<h1>\(body)</h1>"
		case .description: return "<h2>\(body)</h2>"
		case .heading3: return "<h3>\(body)</h3>"
		case .heading4: return "<h4>\(body)</h4>"
		case .heading5: return "<h5>\(body)</h5>"
		case .heading6: return "<h6>\(body)</h6>"
		case .code: return "<pre><code>\(body)</code></pre>"
		case .toggle, .toggleHeader: return "<blockquote><p>\(body)</p></blockquote>"
		case .listBullet: return "<ul><li>\(body)</li></ul>"
		case .checkbox: return "<ul><li>\(body)</li></ul>"
		case .text:
			return body == "----" ? "<hr>" : "<p>\(body)</p>"
		}
	}

	private static func htmlFragment(_ run: Run) -> String {
		var out = escapeHTML(run.text)
		if run.code { out = "<code>\(out)</code>" }
		if run.bold { out = "<strong>\(out)</strong>" }
		if run.italic { out = "<em>\(out)</em>" }
		if run.strike { out = "<s>\(out)</s>" }
		if let link = run.link {
			out = "<a href=\"\(escapeHTML(link.absoluteString))\">\(out)</a>"
		}
		return out
	}

	private static func wrapHTMLDocument(_ body: String) -> String {
		"<!DOCTYPE html><html><head><meta charset=\"utf-8\"></head><body>\n\(body)\n</body></html>"
	}

	private static func escapeHTML(_ s: String) -> String {
		s.replacingOccurrences(of: "&", with: "&amp;")
			.replacingOccurrences(of: "<", with: "&lt;")
			.replacingOccurrences(of: ">", with: "&gt;")
			.replacingOccurrences(of: "\"", with: "&quot;")
	}

	// MARK: - RTF

	/// System fonts on purpose: the receiving app will not have the editor's display
	/// fonts installed, and RTF references fonts by name.
	private static func rtfBaseFont(for style: TextStyle) -> UIFont {
		switch style {
		case .title: return .systemFont(ofSize: 26, weight: .bold)
		case .description: return .systemFont(ofSize: 22, weight: .bold)
		case .heading3: return .systemFont(ofSize: 19, weight: .semibold)
		case .heading4: return .systemFont(ofSize: 17, weight: .semibold)
		case .heading5: return .systemFont(ofSize: 15, weight: .semibold)
		case .heading6: return .systemFont(ofSize: 14, weight: .semibold)
		case .code: return .monospacedSystemFont(ofSize: 13, weight: .regular)
		case .text, .toggle, .toggleHeader, .listBullet, .checkbox: return .systemFont(ofSize: 14)
		}
	}

	/// `terminated` appends the paragraph break with the paragraph's own attributes,
	/// so spacing and font size stay consistent across the whole RTF.
	private static func rtfParagraph(runs: [Run], style: TextStyle, checked: Bool, withPrefix: Bool = true, terminated: Bool = false) -> NSAttributedString {
		let base = rtfBaseFont(for: style)
		let paragraphStyle = NSMutableParagraphStyle()
		paragraphStyle.paragraphSpacing = 6
		switch style {
		case .title: paragraphStyle.paragraphSpacingBefore = 10
		case .description, .heading3, .heading4, .heading5, .heading6: paragraphStyle.paragraphSpacingBefore = 6
		case .listBullet, .checkbox:
			paragraphStyle.paragraphSpacing = 2
			paragraphStyle.headIndent = 18
			paragraphStyle.firstLineHeadIndent = 0
		case .toggle, .toggleHeader:
			paragraphStyle.headIndent = 18
			paragraphStyle.firstLineHeadIndent = 18
		default: break
		}
		let baseAttrs: [NSAttributedString.Key: Any] = [
			.font: base,
			.foregroundColor: UIColor.black,
			.paragraphStyle: paragraphStyle
		]

		let out = NSMutableAttributedString()
		if withPrefix {
			let prefix = plainPrefix(for: style, checked: checked)
			if !prefix.isEmpty { out.append(NSAttributedString(string: prefix, attributes: baseAttrs)) }
		}

		for run in runs {
			var attrs = baseAttrs
			var font = base
			if run.code || style == .code {
				font = .monospacedSystemFont(ofSize: max(base.pointSize - 1, 11), weight: .regular)
			} else {
				var traits = font.fontDescriptor.symbolicTraits
				if run.bold { traits.insert(.traitBold) }
				if run.italic { traits.insert(.traitItalic) }
				if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
					font = UIFont(descriptor: descriptor, size: font.pointSize)
				}
			}
			attrs[.font] = font
			if run.strike { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
			if let link = run.link {
				attrs[.link] = link
				attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
				attrs[.foregroundColor] = UIColor.systemBlue
			}
			out.append(NSAttributedString(string: run.text, attributes: attrs))
		}
		if terminated { out.append(NSAttributedString(string: "\n", attributes: baseAttrs)) }
		return out
	}

	private static func rtfData(from attributed: NSAttributedString) -> Data? {
		guard attributed.length > 0 else { return nil }
		return try? attributed.data(
			from: NSRange(location: 0, length: attributed.length),
			documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
		)
	}
}

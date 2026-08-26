import UIKit

/// Visual theme for the Konuq editor so a host app can make it look native.
///
/// Set `KonuqEditor.theme` (on the main thread, before presenting the editor) to
/// override fonts and colors. The default is `.konuq` — the original Konuq look.
public struct KonuqEditorTheme {
	/// Font for titles and headings.
	public var displayFont: (_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont
	/// Font for body text, lists and quotes.
	public var textFont: (_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont
	/// Accent color (cursor, selection handles, toolbar actions, links).
	public var accent: UIColor
	/// Primary text color.
	public var primaryText: UIColor
	/// Secondary text color.
	public var secondaryText: UIColor
	/// Background colors used for inline `#tags`, cycled by a hash of the tag. Provide at least one.
	public var tagColors: [UIColor]

	public init(
		displayFont: @escaping (CGFloat, UIFont.Weight) -> UIFont,
		textFont: @escaping (CGFloat, UIFont.Weight) -> UIFont,
		accent: UIColor,
		primaryText: UIColor,
		secondaryText: UIColor,
		tagColors: [UIColor]
	) {
		self.displayFont = displayFont
		self.textFont = textFont
		self.accent = accent
		self.primaryText = primaryText
		self.secondaryText = secondaryText
		self.tagColors = tagColors
	}
}

public extension KonuqEditorTheme {
	/// The original Konuq look: bundled Space Grotesk + DM Sans and Konuq colors.
	static var konuq: KonuqEditorTheme {
		KonuqEditorTheme(
			displayFont: { size, weight in UIFont.konuqSpaceGrotesk(size: size, weight: weight) },
			textFont: { size, weight in UIFont.konuqDMSans(size: size, weight: weight) },
			accent: UIColor(named: "appAccentColor", in: .module, compatibleWith: nil)
				?? UIColor(displayP3Red: 0.403, green: 0.527, blue: 0.455, alpha: 1),
			primaryText: UIColor(named: "primaryTextColor", in: .module, compatibleWith: nil) ?? .label,
			secondaryText: UIColor(named: "secondaryTextColor", in: .module, compatibleWith: nil) ?? .secondaryLabel,
			tagColors: (1...6).compactMap { UIColor(named: "tag\($0)Color", in: .module, compatibleWith: nil) }
		)
	}

	/// Adopt the Konuq layout but override the accent (and, optionally, fonts/text colors)
	/// so the editor looks native in the host app. Fonts default to the system font.
	static func app(
		accent: UIColor,
		displayFont: @escaping (CGFloat, UIFont.Weight) -> UIFont = { UIFont.systemFont(ofSize: $0, weight: $1) },
		textFont: @escaping (CGFloat, UIFont.Weight) -> UIFont = { UIFont.systemFont(ofSize: $0, weight: $1) },
		primaryText: UIColor = .label,
		secondaryText: UIColor = .secondaryLabel,
		tagColors: [UIColor]? = nil
	) -> KonuqEditorTheme {
		KonuqEditorTheme(
			displayFont: displayFont,
			textFont: textFont,
			accent: accent,
			primaryText: primaryText,
			secondaryText: secondaryText,
			tagColors: tagColors ?? [
				.secondarySystemBackground,
				.tertiarySystemBackground,
				.systemGray5,
				.systemGray6,
				.systemGray4,
				.systemGray3
			]
		)
	}
}

/// Entry point for configuring the editor's appearance.
public enum KonuqEditor {
	/// The active theme. Set on the main thread before presenting the editor. Defaults to `.konuq`.
	public static var theme: KonuqEditorTheme = .konuq

	/// Forces the language of the editor's own strings (e.g. "it", "pt-BR").
	/// Leave nil to follow the system. Set this when the host app offers an
	/// in-app language picker, otherwise the editor stays on the system language
	/// while the rest of the app switches.
	public static var preferredLanguageCode: String?
}

// The editor calls `UIFont.appSpaceGrotesk`/`appDMSans` throughout; route those through the
// active theme. The bundled Konuq fonts remain available as `konuqSpaceGrotesk`/`konuqDMSans`.
extension UIFont {
	static func appSpaceGrotesk(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
		KonuqEditor.theme.displayFont(size, weight)
	}

	static func appDMSans(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
		KonuqEditor.theme.textFont(size, weight)
	}
}

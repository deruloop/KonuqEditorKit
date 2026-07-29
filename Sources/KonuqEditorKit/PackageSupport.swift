import UIKit
import CoreText

// Small app-level symbols the Konuq editor referenced in the host app,
// re-provided here so the editor compiles as a standalone package.

/// True when running as an iOS app on an Apple-silicon Mac (affects some keyboard handling).
var isiOSAppOnMac: Bool {
	ProcessInfo.processInfo.isiOSAppOnMac
}

extension UIColor {
	/// Accent color, resolved from the package's bundled asset catalog.
	static var appAccent: UIColor {
		KonuqEditor.theme.accent
	}

	/// Resolve an editor palette color from the package bundle, with a fallback.
	static func editorAsset(_ name: String, fallback: UIColor = .label) -> UIColor {
		UIColor(named: name, in: .module, compatibleWith: nil) ?? fallback
	}

	func lighter(by percentage: CGFloat = 30.0) -> UIColor? {
		adjust(by: abs(percentage))
	}

	func darker(by percentage: CGFloat = 30.0) -> UIColor? {
		adjust(by: -1 * abs(percentage))
	}

	func adjust(by percentage: CGFloat = 30.0) -> UIColor? {
		var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
		if getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
			return UIColor(red: min(red + percentage / 100, 1.0),
						   green: min(green + percentage / 100, 1.0),
						   blue: min(blue + percentage / 100, 1.0),
						   alpha: alpha)
		}
		return nil
	}
}

enum KonuqEditorFonts {
	private static let registerOnce: Void = {
		var urls: [URL] = []
		for sub in [nil, "Fonts"] as [String?] {
			if let found = Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: sub) {
				urls.append(contentsOf: found)
			}
		}
		for url in Set(urls) {
			CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
		}
	}()

	/// Register the package's bundled fonts with the system, once.
	static func registerIfNeeded() {
		_ = registerOnce
	}
}

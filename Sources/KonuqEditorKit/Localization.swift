import Foundation

/// String lookup for the editor's own UI.
///
/// Package strings live in `Resources/<lang>.lproj` and resolve through
/// `Bundle.module`, which follows the SYSTEM language — so an app that lets the
/// user pick a language would otherwise keep showing the editor in English.
/// `KonuqEditor.preferredLanguageCode` lets the host force one.
enum L {
	static func t(_ key: String) -> String {
		let fallback = Bundle.module
		guard let code = KonuqEditor.preferredLanguageCode else {
			return fallback.localizedString(forKey: key, value: key, table: nil)
		}
		guard let bundle = languageBundle(for: code) else {
			return fallback.localizedString(forKey: key, value: key, table: nil)
		}
		return bundle.localizedString(forKey: key, value: key, table: nil)
	}

	private static var cache: [String: Bundle] = [:]

	private static func languageBundle(for code: String) -> Bundle? {
		if let cached = cache[code] { return cached }
		// Try the exact code first ("pt-BR", "zh-Hans"), then its base ("pt").
		let candidates = [code, String(code.split(separator: "-").first ?? "")]
		for candidate in candidates where candidate.isEmpty == false {
			if let path = Bundle.module.path(forResource: candidate, ofType: "lproj"),
			   let bundle = Bundle(path: path) {
				cache[candidate] = bundle
				cache[code] = bundle
				return bundle
			}
		}
		return nil
	}
}

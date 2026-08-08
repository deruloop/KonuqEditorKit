import Foundation

/// The single source of truth for how a "location" is written into a note: a pin emoji
/// followed by the place name, linking out to Apple Maps. Both hosts (Packd's trip-stop
/// template and Konuq's search-and-insert) compose their rows from this, so a location
/// row is byte-identical wherever it is authored and renders the same everywhere.
public enum EditorLocationLink {

	/// An Apple Maps deep link that drops a pin labelled with the place name, at its
	/// coordinates when known.
	public static func appleMapsURL(name: String, latitude: Double? = nil, longitude: Double? = nil) -> String {
		let query = sanitizedName(name)
		let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
		if let latitude, let longitude {
			return "https://maps.apple.com/?q=\(encoded)&ll=\(latitude),\(longitude)"
		}
		return "https://maps.apple.com/?q=\(encoded)"
	}

	/// The inline markdown a location renders as everywhere: `📍 name` linking to Apple Maps.
	public static func markdown(name: String, latitude: Double? = nil, longitude: Double? = nil) -> String {
		let display = sanitizedName(name)
		let label = display.isEmpty ? "Location" : display
		let url = appleMapsURL(name: display.isEmpty ? name : display, latitude: latitude, longitude: longitude)
		return "[📍 \(label)](\(url))"
	}

	/// A single inline-location-link text row, ready to hand to `insertBlocks`.
	public static func snapshot(name: String, latitude: Double? = nil, longitude: Double? = nil, position: Int = 0) -> EditorBlockSnapshot {
		EditorBlockSnapshot(
			id: UUID().uuidString,
			kind: .text(text: markdown(name: name, latitude: latitude, longitude: longitude), style: .text),
			parentId: nil,
			position: position
		)
	}

	/// Strip characters that would break the inline `[label](url)` markdown.
	public static func sanitizedName(_ raw: String) -> String {
		raw.replacingOccurrences(of: "[", with: "")
			.replacingOccurrences(of: "]", with: "")
			.trimmingCharacters(in: .whitespacesAndNewlines)
	}
}

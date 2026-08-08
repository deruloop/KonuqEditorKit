import Foundation

/// The single source of truth for how a "location" is written into a note: a pin emoji
/// followed by the place name, linking out to Apple Maps. Both hosts (Packd's trip-stop
/// template and Konuq's search-and-insert) compose their rows from this, so a location
/// row is byte-identical wherever it is authored and renders the same everywhere.
public enum EditorLocationLink {

	/// A place extracted from (or destined for) a location link: a display name and, when
	/// known, its coordinates. The editor kit stays maps-agnostic — a host decides which
	/// map app to open with this.
	public struct Place: Equatable {
		public let name: String
		public let latitude: Double?
		public let longitude: Double?
		public init(name: String, latitude: Double? = nil, longitude: Double? = nil) {
			self.name = name
			self.latitude = latitude
			self.longitude = longitude
		}
	}

	/// Parse a tapped URL back into a `Place` if it is one of our location links (an Apple
	/// Maps `?q=&ll=` link). Returns nil for ordinary links, so a host can special-case
	/// location taps (e.g. route them through the user's chosen map app) and fall through
	/// otherwise. Pure parsing — no map app is launched here.
	public static func place(from url: URL) -> Place? {
		guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
		let isAppleMaps = (comps.host?.lowercased().contains("maps.apple.com") ?? false)
			|| comps.scheme?.lowercased() == "maps"
		guard isAppleMaps else { return nil }
		let items = comps.queryItems ?? []
		let name = items.first(where: { $0.name == "q" })?.value ?? ""
		var latitude: Double?
		var longitude: Double?
		if let ll = items.first(where: { $0.name == "ll" })?.value {
			let parts = ll.split(separator: ",")
			if parts.count == 2 { latitude = Double(parts[0]); longitude = Double(parts[1]) }
		}
		guard !name.isEmpty || (latitude != nil && longitude != nil) else { return nil }
		return Place(name: name, latitude: latitude, longitude: longitude)
	}

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

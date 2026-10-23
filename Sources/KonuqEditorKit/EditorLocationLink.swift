import UIKit

/// The single source of truth for how a "location" is written into a note: a pin emoji
/// followed by the place name, linking out to Apple Maps. Both hosts (Packd's trip-stop
/// template and Konuq's search-and-insert) compose their rows from this, so a location
/// row is byte-identical wherever it is authored and renders the same everywhere.
///
/// The editor shows the link as a chip (pin, name, area, tinted background). The area and
/// the tint travel as two extra query items on the Maps URL, `kq-area` and `kq-tint`
/// (six hex digits), which Apple Maps ignores. Readers that know nothing about chips still
/// see an ordinary `[📍 name](url)` link, so older app versions, exports and the web keep
/// working.
public enum EditorLocationLink {

	static let areaQueryItem = "kq-area"
	static let tintQueryItem = "kq-tint"

	/// A place extracted from (or destined for) a location link: a display name and, when
	/// known, its coordinates, the area it sits in, and the chip tint. The editor kit stays
	/// maps-agnostic — a host decides which map app to open with this.
	public struct Place: Equatable {
		public let name: String
		public let latitude: Double?
		public let longitude: Double?
		/// The town, district or region shown after the name ("Kyoto"). nil when unknown.
		public let area: String?
		/// The chip tint as six hex digits ("678674"). nil = the editor accent.
		public let tintHex: String?

		public init(name: String, latitude: Double? = nil, longitude: Double? = nil, area: String? = nil, tintHex: String? = nil) {
			self.name = name
			self.latitude = latitude
			self.longitude = longitude
			self.area = area.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
			self.tintHex = tintHex.flatMap(EditorLocationLink.normalizedHex)
		}

		/// The same place with another tint.
		public func withTint(_ hex: String?) -> Place {
			Place(name: name, latitude: latitude, longitude: longitude, area: area, tintHex: hex)
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
		return Place(
			name: name,
			latitude: latitude,
			longitude: longitude,
			area: items.first(where: { $0.name == areaQueryItem })?.value,
			tintHex: items.first(where: { $0.name == tintQueryItem })?.value
		)
	}

	/// Whether a link label and URL form a location: the label starts with the pin and the
	/// URL is one of our Maps links.
	public static func isLocation(label: String, url: URL) -> Bool {
		label.trimmingCharacters(in: .whitespaces).hasPrefix("📍") && place(from: url) != nil
	}

	/// An Apple Maps deep link that drops a pin labelled with the place name, at its
	/// coordinates when known, carrying the chip's area and tint.
	public static func appleMapsURL(name: String, latitude: Double? = nil, longitude: Double? = nil, area: String? = nil, tintHex: String? = nil) -> String {
		var comps = URLComponents()
		comps.scheme = "https"
		comps.host = "maps.apple.com"
		comps.path = "/"
		var items = [URLQueryItem(name: "q", value: sanitizedName(name))]
		if let latitude, let longitude {
			items.append(URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"))
		}
		if let area = area.map(sanitizedName), !area.isEmpty {
			items.append(URLQueryItem(name: areaQueryItem, value: area))
		}
		if let hex = tintHex.flatMap(normalizedHex) {
			items.append(URLQueryItem(name: tintQueryItem, value: hex))
		}
		comps.queryItems = items
		// `)` would end the markdown link early; spaces would end it too.
		let raw = comps.url?.absoluteString ?? "https://maps.apple.com/"
		return raw
			.replacingOccurrences(of: "(", with: "%28")
			.replacingOccurrences(of: ")", with: "%29")
	}

	/// The inline markdown a location renders as everywhere: `📍 name` linking to Apple Maps.
	public static func markdown(name: String, latitude: Double? = nil, longitude: Double? = nil, area: String? = nil, tintHex: String? = nil) -> String {
		let display = sanitizedName(name)
		let label = display.isEmpty ? "Location" : display
		let url = appleMapsURL(name: display.isEmpty ? name : display, latitude: latitude, longitude: longitude, area: area, tintHex: tintHex)
		return "[📍 \(label)](\(url))"
	}

	public static func markdown(for place: Place) -> String {
		markdown(name: place.name, latitude: place.latitude, longitude: place.longitude, area: place.area, tintHex: place.tintHex)
	}

	/// A single inline-location-link text row, ready to hand to `insertBlocks`.
	public static func snapshot(name: String, latitude: Double? = nil, longitude: Double? = nil, area: String? = nil, tintHex: String? = nil, position: Int = 0) -> EditorBlockSnapshot {
		EditorBlockSnapshot(
			id: UUID().uuidString,
			kind: .text(text: markdown(name: name, latitude: latitude, longitude: longitude, area: area, tintHex: tintHex), style: .text),
			parentId: nil,
			position: position
		)
	}

	public static func snapshot(for place: Place, position: Int = 0) -> EditorBlockSnapshot {
		snapshot(name: place.name, latitude: place.latitude, longitude: place.longitude, area: place.area, tintHex: place.tintHex, position: position)
	}

	/// Strip characters that would break the inline `[label](url)` markdown.
	public static func sanitizedName(_ raw: String) -> String {
		raw.replacingOccurrences(of: "[", with: "")
			.replacingOccurrences(of: "]", with: "")
			.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	// MARK: - Tint as hex

	/// Six uppercase hex digits for a colour, resolved in the light appearance so a
	/// dynamic colour stores one stable value.
	public static func hex(from color: UIColor) -> String {
		let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
		var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
		guard resolved.getRed(&r, green: &g, blue: &b, alpha: &a) else { return "678674" }
		func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
		return String(format: "%02X%02X%02X", byte(r), byte(g), byte(b))
	}

	/// The colour for six hex digits, nil when the value is not hex.
	public static func color(fromHex hex: String) -> UIColor? {
		guard let normalized = normalizedHex(hex), let value = UInt32(normalized, radix: 16) else { return nil }
		return UIColor(
			red: CGFloat((value >> 16) & 0xFF) / 255,
			green: CGFloat((value >> 8) & 0xFF) / 255,
			blue: CGFloat(value & 0xFF) / 255,
			alpha: 1
		)
	}

	static func normalizedHex(_ raw: String) -> String? {
		var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
		if s.hasPrefix("#") { s.removeFirst() }
		guard s.count == 6, s.allSatisfy({ $0.isHexDigit }) else { return nil }
		return s
	}
}

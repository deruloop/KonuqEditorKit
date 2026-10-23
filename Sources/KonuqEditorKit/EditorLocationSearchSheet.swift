import SwiftUI
import MapKit

/// A generic address-search sheet used to insert a location when a host has no structured
/// place data of its own (e.g. Konuq, which — unlike Packd — has no trip stops to draw on).
/// Type a place, pick a result, and the sheet hands back its name, area, coordinates and
/// the chip tint.
///
/// With `allowsTintChoice` the sheet shows a second step after the pick: the chip as it
/// will look and an `EditorColorPicker`, starting from `defaultTintHex`.
public struct EditorLocationSearchSheet: View {

	@Environment(\.dismiss) private var dismiss
	@StateObject private var model = LocationSearchModel()
	private let defaultTintHex: String?
	private let allowsTintChoice: Bool
	private let onPick: (EditorLocationLink.Place) -> Void

	@State private var pending: EditorLocationLink.Place?
	@State private var tintHex: String = ""
	@State private var isResolving = false

	/// - Parameters:
	///   - defaultTintHex: the chip tint to start from (six hex digits); nil = the editor accent.
	///   - allowsTintChoice: show the colour step before handing the place back.
	public init(defaultTintHex: String? = nil, allowsTintChoice: Bool = false, onPick: @escaping (EditorLocationLink.Place) -> Void) {
		self.defaultTintHex = defaultTintHex
		self.allowsTintChoice = allowsTintChoice
		self.onPick = onPick
	}

	private var startingTint: String {
		defaultTintHex.flatMap(EditorLocationLink.normalizedHex) ?? EditorLocationLink.hex(from: KonuqEditor.theme.accent)
	}

	public var body: some View {
		NavigationStack {
			Group {
				if let pending {
					tintStep(pending)
				} else {
					searchStep
				}
			}
			.navigationTitle(L.t("editor.location.title"))
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button(L.t("editor.cancel")) { dismiss() }
				}
				if let pending {
					ToolbarItem(placement: .confirmationAction) {
						Button(L.t("editor.location.add")) {
							onPick(pending.withTint(tintHex))
							dismiss()
						}
						.fontWeight(.semibold)
					}
				}
			}
			.tint(Color(uiColor: KonuqEditor.theme.accent))
		}
		.onAppear {
			if tintHex.isEmpty { tintHex = startingTint }
		}
	}

	private var searchStep: some View {
		List(model.results, id: \.self) { completion in
			Button {
				resolve(completion)
			} label: {
				VStack(alignment: .leading, spacing: 2) {
					Text(completion.title)
						.foregroundStyle(.primary)
					if !completion.subtitle.isEmpty {
						Text(completion.subtitle)
							.font(.footnote)
							.foregroundStyle(.secondary)
					}
				}
			}
			.disabled(isResolving)
		}
		.listStyle(.plain)
		.overlay {
			if model.query.isEmpty {
				ContentUnavailableView(L.t("editor.location.search"), systemImage: "mappin.and.ellipse")
			} else if model.results.isEmpty {
				ContentUnavailableView.search
			}
		}
		.searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: L.t("editor.location.search"))
		.autocorrectionDisabled()
	}

	private func tintStep(_ place: EditorLocationLink.Place) -> some View {
		let tint = Color(uiColor: EditorLocationLink.color(fromHex: tintHex) ?? KonuqEditor.theme.accent)
		return VStack(alignment: .leading, spacing: 22) {
			EditorLocationChipView(place: place, tint: tint)
				.frame(maxWidth: .infinity, alignment: .center)
				.padding(.top, 28)

			VStack(alignment: .leading, spacing: 8) {
				Text(L.t("editor.location.color"))
					.font(.footnote.weight(.semibold))
					.foregroundStyle(.secondary)
					.textCase(.uppercase)
				EditorColorPicker(selection: $tintHex)
			}
			.padding(.horizontal, 20)

			Spacer(minLength: 0)
		}
	}

	private func resolve(_ completion: MKLocalSearchCompletion) {
		isResolving = true
		let request = MKLocalSearch.Request(completion: completion)
		MKLocalSearch(request: request).start { response, _ in
			DispatchQueue.main.async {
				isResolving = false
				let item = response?.mapItems.first
				let coordinate = item?.placemark.coordinate
				let name = item?.name ?? completion.title
				let area = Self.area(of: item?.placemark, name: name, fallback: completion.subtitle)
				let place = EditorLocationLink.Place(
					name: name,
					latitude: coordinate?.latitude,
					longitude: coordinate?.longitude,
					area: area,
					tintHex: tintHex.isEmpty ? startingTint : tintHex
				)
				if allowsTintChoice {
					withAnimation(.easeInOut(duration: 0.2)) { pending = place }
				} else {
					onPick(place)
					dismiss()
				}
			}
		}
	}

	/// The most useful short area for a place: its town, else its region, else its
	/// country. Never the name itself ("Kyoto" for Kyoto is no help).
	static func area(of placemark: MKPlacemark?, name: String, fallback: String) -> String? {
		let candidates = [placemark?.locality, placemark?.subAdministrativeArea, placemark?.administrativeArea, placemark?.country]
		for candidate in candidates {
			guard let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { continue }
			if value.caseInsensitiveCompare(name) == .orderedSame { continue }
			return value
		}
		let first = fallback.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.last { !$0.isEmpty }
		return first.flatMap { $0.caseInsensitiveCompare(name) == .orderedSame ? nil : $0 }
	}
}

/// Bridges `MKLocalSearchCompleter`'s delegate callbacks into observable SwiftUI state.
private final class LocationSearchModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
	@Published var query: String = "" {
		didSet {
			let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
			if trimmed.isEmpty {
				results = []
				completer.queryFragment = ""
			} else {
				completer.queryFragment = trimmed
			}
		}
	}
	@Published var results: [MKLocalSearchCompletion] = []

	private let completer = MKLocalSearchCompleter()

	override init() {
		super.init()
		completer.delegate = self
		completer.resultTypes = [.address, .pointOfInterest]
	}

	func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
		results = completer.results
	}

	func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
		results = []
	}
}

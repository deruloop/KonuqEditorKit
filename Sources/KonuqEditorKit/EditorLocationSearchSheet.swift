import SwiftUI
import MapKit

/// A generic address-search sheet used to insert a location when a host has no structured
/// place data of its own (e.g. Konuq, which — unlike Packd — has no trip stops to draw on).
/// Type a place, pick a result, and the sheet hands back its display name and coordinates.
public struct EditorLocationSearchSheet: View {

	/// A resolved place chosen from the search results.
	public struct Place: Equatable {
		public let name: String
		public let latitude: Double?
		public let longitude: Double?
	}

	@Environment(\.dismiss) private var dismiss
	@StateObject private var model = LocationSearchModel()
	private let onPick: (Place) -> Void

	public init(onPick: @escaping (Place) -> Void) {
		self.onPick = onPick
	}

	public var body: some View {
		NavigationStack {
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
			}
			.listStyle(.plain)
			.overlay {
				if model.query.isEmpty {
					ContentUnavailableView("Search for a place", systemImage: "mappin.and.ellipse")
				} else if model.results.isEmpty {
					ContentUnavailableView.search
				}
			}
			.searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search for a place")
			.autocorrectionDisabled()
			.navigationTitle("Add location")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") { dismiss() }
				}
			}
			.tint(Color(uiColor: KonuqEditor.theme.accent))
		}
	}

	private func resolve(_ completion: MKLocalSearchCompletion) {
		let request = MKLocalSearch.Request(completion: completion)
		MKLocalSearch(request: request).start { response, _ in
			DispatchQueue.main.async {
				let item = response?.mapItems.first
				let coordinate = item?.placemark.coordinate
				let name = item?.name ?? completion.title
				onPick(Place(name: name, latitude: coordinate?.latitude, longitude: coordinate?.longitude))
				dismiss()
			}
		}
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

import SwiftUI
import UIKit

/// A compact colour picker: a row of swatches plus the system picker for anything else.
/// Reusable by any host or editor feature that needs a tint (location chips today).
/// The selection is six hex digits, the form colours are stored in.
public struct EditorColorPicker: View {
	@Binding private var selection: String
	private let palette: [String]

	/// A palette that reads well as a light tint in both appearances.
	public static let defaultPalette: [String] = [
		"678674", // Konuq green
		"3B82F6", // blue
		"0EA5A4", // teal
		"8B5CF6", // violet
		"EC4899", // pink
		"EF4444", // red
		"F97316", // orange
		"EAB308", // yellow
		"84CC16", // lime
		"78716C", // stone
	]

	/// - Parameters:
	///   - selection: six hex digits, with or without `#`.
	///   - palette: the swatches offered; the current selection is added when missing.
	public init(selection: Binding<String>, palette: [String] = EditorColorPicker.defaultPalette) {
		self._selection = selection
		self.palette = palette.compactMap(EditorLocationLink.normalizedHex)
	}

	private var normalizedSelection: String {
		EditorLocationLink.normalizedHex(selection) ?? palette.first ?? "678674"
	}

	private var swatches: [String] {
		palette.contains(normalizedSelection) ? palette : [normalizedSelection] + palette
	}

	private var customBinding: Binding<Color> {
		Binding(
			get: { Color(uiColor: EditorLocationLink.color(fromHex: normalizedSelection) ?? KonuqEditor.theme.accent) },
			set: { selection = EditorLocationLink.hex(from: UIColor($0)) }
		)
	}

	public var body: some View {
		ScrollView(.horizontal, showsIndicators: false) {
			HStack(spacing: 10) {
				ForEach(swatches, id: \.self) { hex in
					let color = Color(uiColor: EditorLocationLink.color(fromHex: hex) ?? .gray)
					Button {
						selection = hex
					} label: {
						Circle()
							.fill(color)
							.frame(width: 30, height: 30)
							.overlay(
								Circle()
									.strokeBorder(Color.primary.opacity(hex == normalizedSelection ? 0.85 : 0), lineWidth: 2.5)
									.padding(-4)
							)
					}
					.buttonStyle(.plain)
					.accessibilityLabel(Text("#\(hex)"))
					.accessibilityAddTraits(hex == normalizedSelection ? .isSelected : [])
				}
				ColorPicker(L.t("editor.color.custom"), selection: customBinding, supportsOpacity: false)
					.labelsHidden()
					.frame(width: 30, height: 30)
					.accessibilityLabel(Text(L.t("editor.color.custom")))
			}
			.padding(.horizontal, 6)
			.padding(.vertical, 6)
		}
	}
}

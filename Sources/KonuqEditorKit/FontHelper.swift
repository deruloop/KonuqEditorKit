//
//  FontHelper.swift
//  PackdApp
//
//  Created by Cristiano Calicchia on 09/08/24.
//  Copyright © 2024 deruloop. All rights reserved.
//

import Foundation

import SwiftUI
import UIKit

private func isIOsAppOnMacRuntime() -> Bool {
	if #available(iOS 14.0, *) { return ProcessInfo.processInfo.isiOSAppOnMac }
	return false
}

public enum AppFontFamily {
	case system
	case spaceGrotesk
	case dmSans
}

extension Font {
	///
	/// Use the closest weight if your typeface does not support a particular weight
	///
	static private var regularFontName: String {
		"SpaceGrotesk"
	}
	
	static private var mediumFontName: String {
		"SpaceGrotesk-Medium"
	}
	
	static private var boldFontName: String {
		"SpaceGrotesk-Bold"
	}
	
	static private var semiBoldFontName: String {
		"SpaceGrotesk-Bold"
	}
	
	static private var extraBoldFontName: String {
		"SpaceGrotesk-ExtraBold"
	}
	
	static private var heavyFontName: String {
		"SpaceGrotesk-CondensedBold"
	}
	
	static private var lightFontName: String {
		"SpaceGrotesk-Light"
	}
	
	static private var thinFontName: String {
		"SpaceGrotesk-Light"
	}
	
	static private var ultraThinFontName: String {
		"SpaceGrotesk-UltraLight"
	}
	
	static private var blackFontName: String {
		"SpaceGrotesk-CondensedBlack"
	}
	
	/// Sizes
	private static var preferredSizeTitle: CGFloat {
		UIFont.preferredFont(forTextStyle: .title1).pointSize
	}
	
	private static var preferredLargeTitle: CGFloat {
		UIFont.preferredFont(forTextStyle: .largeTitle).pointSize
	}
		
	private static var preferredExtraLargeTitle: CGFloat {
		if #available(iOS 17.0, *) {
			UIFont.preferredFont(forTextStyle: .extraLargeTitle).pointSize
		} else {
			UIFont.preferredFont(forTextStyle: .largeTitle).pointSize
		}
	}
	
	private static var preferredExtraLargeTitle2: CGFloat {
		if #available(iOS 17.0, *) {
			UIFont.preferredFont(forTextStyle: .extraLargeTitle2).pointSize
		} else {
			UIFont.preferredFont(forTextStyle: .largeTitle).pointSize
		}
	}
	
	private static var preferredTitle1: CGFloat {
		UIFont.preferredFont(forTextStyle: .title1).pointSize
	}
	
	private static var preferredTitle2: CGFloat {
		UIFont.preferredFont(forTextStyle: .title2).pointSize
	}
	
	private static var preferredTitle3: CGFloat {
		UIFont.preferredFont(forTextStyle: .title3).pointSize
	}
	
	private static var preferredHeadline: CGFloat {
		UIFont.preferredFont(forTextStyle: .headline).pointSize
	}
	
	private static var preferredSubheadline: CGFloat {
		UIFont.preferredFont(forTextStyle: .subheadline).pointSize
	}
	
	private static var preferredBody: CGFloat {
		UIFont.preferredFont(forTextStyle: .body).pointSize
	}
	
	private static var preferredCallout: CGFloat {
		UIFont.preferredFont(forTextStyle: .callout).pointSize
	}
	
	private static var preferredFootnote: CGFloat {
		UIFont.preferredFont(forTextStyle: .footnote).pointSize
	}
	
	private static var preferredCaption: CGFloat {
		UIFont.preferredFont(forTextStyle: .caption1).pointSize
	}
	
	private static var preferredCaption2: CGFloat {
		UIFont.preferredFont(forTextStyle: .caption2).pointSize
	}
	
	/// Styles
	public static var title: Font {
		return Font.custom(regularFontName, size: preferredTitle1)
	}
	
	public static var title2: Font {
		return Font.custom(regularFontName, size: preferredTitle2)
	}
	
	public static var title3: Font {
		return Font.custom(regularFontName, size: preferredTitle3)
	}

	public static var largeTitle: Font {
		return Font.custom(regularFontName, size: preferredLargeTitle)
	}
	
	public static var body: Font {
		return Font.custom(regularFontName, size: preferredBody)
	}
	
	public static var headline: Font {
		return Font.custom(regularFontName, size: preferredHeadline)
	}
		
	public static var subheadline: Font {
		return Font.custom(regularFontName, size: preferredSubheadline)
	}
		
	public static var callout: Font {
		return Font.custom(regularFontName, size: preferredCallout)
	}
	
	public static var footnote: Font {
		return Font.custom(regularFontName, size: preferredFootnote)
	}
	
	public static var caption: Font {
		return Font.custom(regularFontName, size: preferredCaption)
	}
	
	public static var caption2: Font {
		return Font.custom(regularFontName, size: preferredCaption2)
	}

	private static func uiWeight(from weight: Font.Weight) -> UIFont.Weight {
		switch weight {
		case .bold: return .bold
		case .regular: return .regular
		case .heavy: return .heavy
		case .light: return .light
		case .medium: return .medium
		case .semibold: return .semibold
		case .thin: return .thin
		case .ultraLight: return .ultraLight
		case .black: return .black
		default: return .regular
		}
	}

	private static func preferredPointSize(for style: Font.TextStyle) -> CGFloat {
		switch style {
		case .largeTitle:
			return preferredLargeTitle
		case .title:
			return preferredTitle1
		case .title2:
			return preferredTitle2
		case .title3:
			return preferredTitle3
		case .headline:
			return preferredHeadline
		case .subheadline:
			return preferredSubheadline
		case .body:
			return preferredBody
		case .callout:
			return preferredCallout
		case .footnote:
			return preferredFootnote
		case .caption:
			return preferredCaption
		case .caption2:
			return preferredCaption2
		case .extraLargeTitle:
			return preferredExtraLargeTitle
		case .extraLargeTitle2:
			return preferredExtraLargeTitle2
		default:
			return preferredBody
		}
	}

	public static func app(_ style: Font.TextStyle, family: AppFontFamily = .spaceGrotesk, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
		if isIOsAppOnMacRuntime() {
			return Font.system(style, design: design).weight(weight)
		}
		switch family {
		case .system:
			return Font.system(style, design: design).weight(weight)
		case .spaceGrotesk:
			let size = preferredPointSize(for: style)
			let uiFont = UIFont.appSpaceGrotesk(size: size, weight: uiWeight(from: weight))
			return Font.custom(uiFont.fontName, size: size)
		case .dmSans:
			let size = preferredPointSize(for: style)
			let uiFont = UIFont.appDMSans(size: size, weight: uiWeight(from: weight))
			return Font.custom(uiFont.fontName, size: size)
		}
	}

	public static func app(size: CGFloat, family: AppFontFamily = .spaceGrotesk, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
		if isIOsAppOnMacRuntime() {
			return Font.system(size: size, weight: weight, design: design)
		}
		switch family {
		case .system:
			return Font.system(size: size, weight: weight, design: design)
		case .spaceGrotesk:
			let uiFont = UIFont.appSpaceGrotesk(size: size, weight: uiWeight(from: weight))
			return Font.custom(uiFont.fontName, size: size)
		case .dmSans:
			let uiFont = UIFont.appDMSans(size: size, weight: uiWeight(from: weight))
			return Font.custom(uiFont.fontName, size: size)
		}
	}
	
	public static func appSystem(_ style: Font.TextStyle, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
		var size: CGFloat
		var font: String

		switch style {
		case .largeTitle:
			size = preferredLargeTitle
		case .title:
			size = preferredTitle1
		case .title2:
			size = preferredTitle2
		case .title3:
			size = preferredTitle3
		case .headline:
			size = preferredHeadline
		case .subheadline:
			size = preferredSubheadline
		case .body:
			size = preferredBody
		case .callout:
			size = preferredCallout
		case .footnote:
			size = preferredFootnote
		case .caption:
			size = preferredCaption
		case .caption2:
			size = preferredCaption2
		case .extraLargeTitle:
			size = preferredExtraLargeTitle
		case .extraLargeTitle2:
			size = preferredExtraLargeTitle2
		default:
			size = preferredBody
		}
				
		switch weight {
		case .bold:
			font = boldFontName
		case .regular:
			font = regularFontName
		case .heavy:
			font = heavyFontName
		case .light:
			font = lightFontName
		case .medium:
			font = mediumFontName
		case .semibold:
			font = semiBoldFontName
		case .thin:
			font = thinFontName
		case .ultraLight:
			font = ultraThinFontName
		case .black:
			font = blackFontName
		default:
			font = regularFontName
		}
		
		return Font.custom(font, size: size)
	}
	
	public static func appSystem(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
		var font: String
		
		switch weight {
		case .bold:
			font = boldFontName
		case .regular:
			font = regularFontName
		case .heavy:
			font = heavyFontName
		case .light:
			font = lightFontName
		case .medium:
			font = mediumFontName
		case .semibold:
			font = semiBoldFontName
		case .thin:
			font = thinFontName
		case .ultraLight:
			font = ultraThinFontName
		case .black:
			font = blackFontName
		default:
			font = regularFontName
		}
		
		return Font.custom(font, size: size)
	}
}

extension UIFont {
	static func appSpaceGrotesk(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
		KonuqEditorFonts.registerIfNeeded()
		if isIOsAppOnMacRuntime() {
			return UIFont.systemFont(ofSize: size, weight: weight)
		}
		return resolvedCustomFont(
			size: size,
			weight: weight,
			primaryNames: ["SpaceGrotesk", "Space Grotesk", "SpaceGrotesk-VariableFont_wght"],
			familyNameHints: ["SpaceGrotesk", "Space Grotesk"]
		)
	}

	static func appDMSans(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
		KonuqEditorFonts.registerIfNeeded()
		if isIOsAppOnMacRuntime() {
			return UIFont.systemFont(ofSize: size, weight: weight)
		}
		return resolvedCustomFont(
			size: size,
			weight: weight,
			primaryNames: ["DMSans", "DM Sans", "DMSans-VariableFont_opsz,wght"],
			familyNameHints: ["DMSans", "DM Sans"]
		)
	}
}

private extension UIFont {
	static func resolvedCustomFont(
		size: CGFloat,
		weight: UIFont.Weight,
		primaryNames: [String],
		familyNameHints: [String]
	) -> UIFont {
		let availableNames = orderedUnique(primaryNames + fontNamesMatchingFamilyHints(familyNameHints))

		if let bestNamed = bestMatchByWeight(from: availableNames, weight: weight),
		   let font = UIFont(name: bestNamed, size: size) {
			if shouldApplyWeightViaDescriptor(fontName: bestNamed) {
				return font.withWeight(weight)
			}
			return font
		}

		for name in availableNames {
			if let font = UIFont(name: name, size: size) {
				return shouldApplyWeightViaDescriptor(fontName: name) ? font.withWeight(weight) : font
			}
		}

		return UIFont.systemFont(ofSize: size, weight: weight)
	}

	static func fontNamesMatchingFamilyHints(_ hints: [String]) -> [String] {
		let normalizedHints = hints.map(normalize)
		var names: [String] = []

		for family in UIFont.familyNames {
			let normalizedFamily = normalize(family)
			let matches = normalizedHints.contains { hint in
				normalizedFamily.contains(hint) || hint.contains(normalizedFamily)
			}
			if matches {
				names.append(contentsOf: UIFont.fontNames(forFamilyName: family))
			}
		}

		for hint in hints {
			names.append(contentsOf: UIFont.fontNames(forFamilyName: hint))
		}

		return names
	}

	static func bestMatchByWeight(from names: [String], weight: UIFont.Weight) -> String? {
		let desiredKeywords = weightKeywords(for: weight)
		guard !desiredKeywords.isEmpty else { return nil }

		for keyword in desiredKeywords {
			if let name = names.first(where: { normalize($0).contains(normalize(keyword)) }) {
				return name
			}
		}
		if isIOsAppOnMacRuntime(), weight == .regular {
			let boldMarkers = ["bold", "semibold", "demibold", "black", "heavy", "extrabold"]
			if let name = names.first(where: { n in
				let nn = normalize(n)
				return !boldMarkers.contains(where: { nn.contains($0) })
			}) {
				return name
			}
		}
		return nil
	}

	static func weightKeywords(for weight: UIFont.Weight) -> [String] {
		switch weight {
		case .black:
			return ["Black", "ExtraBold", "Heavy", "Bold"]
		case .heavy:
			return ["Heavy", "ExtraBold", "Bold", "SemiBold"]
		case .bold:
			return ["Bold", "SemiBold", "DemiBold", "Medium"]
		case .semibold:
			return ["SemiBold", "Semibold", "DemiBold", "Bold", "Medium"]
		case .medium:
			return ["Medium", "SemiBold", "Bold", "Regular"]
		case .light:
			return ["Light", "ExtraLight", "Thin", "UltraLight", "Regular"]
		case .thin:
			return ["Thin", "Light", "UltraLight", "ExtraLight", "Regular"]
		case .ultraLight:
			return ["UltraLight", "ExtraLight", "Thin", "Light", "Regular"]
		default:
			return ["Regular", "Book"]
		}
	}

	static func shouldApplyWeightViaDescriptor(fontName: String) -> Bool {
		let n = normalize(fontName)
		let markers = ["bold", "semibold", "demibold", "medium", "black", "heavy", "light", "thin", "ultralight", "extrabold", "extralight", "condensed"]
		return !markers.contains(where: { n.contains($0) })
	}

	static func normalize(_ value: String) -> String {
		return value
			.lowercased()
			.replacingOccurrences(of: " ", with: "")
			.replacingOccurrences(of: "-", with: "")
			.replacingOccurrences(of: "_", with: "")
	}

	static func orderedUnique(_ values: [String]) -> [String] {
		var seen = Set<String>()
		var result: [String] = []
		result.reserveCapacity(values.count)
		for v in values {
			let key = normalize(v)
			if seen.insert(key).inserted {
				result.append(v)
			}
		}
		return result
	}

	func withWeight(_ weight: UIFont.Weight) -> UIFont {
		let descriptor = fontDescriptor.addingAttributes([
			UIFontDescriptor.AttributeName.traits: [
				UIFontDescriptor.TraitKey.weight: weight
			]
		])
		guard isIOsAppOnMacRuntime() else {
			return UIFont(descriptor: descriptor, size: pointSize)
		}
		var symbolic = descriptor.symbolicTraits
		if weight.rawValue <= UIFont.Weight.regular.rawValue {
			symbolic.remove(.traitBold)
		}
		guard let tuned = descriptor.withSymbolicTraits(symbolic) else {
			return UIFont(descriptor: descriptor, size: pointSize)
		}
		return UIFont(descriptor: tuned, size: pointSize)
	}
}

// swift-tools-version: 5.10
import PackageDescription

let package = Package(
	name: "KonuqEditorKit",
	defaultLocalization: "en",
	platforms: [.iOS(.v17)],
	products: [
		.library(name: "KonuqEditorKit", targets: ["KonuqEditorKit"])
	],
	targets: [
		.target(
			name: "KonuqEditorKit",
			path: "Sources/KonuqEditorKit",
			resources: [
				.process("Resources")
			]
		)
	]
)

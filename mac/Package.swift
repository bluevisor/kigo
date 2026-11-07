// swift-tools-version:6.0
// Kigo for macOS: the same launcher as the Haiku app, native on the Mac.
// Build the app bundle with mac/build.sh.
import PackageDescription

let package = Package(
	name: "Kigo",
	platforms: [.macOS(.v15)],
	targets: [
		.executableTarget(name: "Kigo", dependencies: ["IslandKit"], path: "Sources/Kigo",
			swiftSettings: [.swiftLanguageMode(.v5)]),
		// Saddle Island's IslandKit client, vendored (Sources/IslandKit/*.swift say from where): Kigo
		// plugs into Saddle Island, which then hands F4 to Kigo (SaddleIsland.swift).
		.target(name: "IslandKit", path: "Sources/IslandKit"),
		.testTarget(name: "KigoTests", dependencies: ["Kigo"], path: "Tests/KigoTests",
			swiftSettings: [.swiftLanguageMode(.v5)]),
	]
)

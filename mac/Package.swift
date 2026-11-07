// swift-tools-version:5.9
// Kigo for macOS: the same launcher as the Haiku app, native on the Mac.
// Build the app bundle with mac/build.sh.
import PackageDescription

let package = Package(
	name: "Kigo",
	platforms: [.macOS(.v14)],
	targets: [
		.executableTarget(name: "Kigo", path: "Sources/Kigo"),
		.testTarget(name: "KigoTests", dependencies: ["Kigo"], path: "Tests/KigoTests"),
	]
)

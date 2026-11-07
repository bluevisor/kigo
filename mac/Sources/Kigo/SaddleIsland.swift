// Kigo as a Saddle Island plugin. Saddle Island (a Dynamic Island for the
// MacBook notch) takes F4 for its own search; with its Settings › Plugins ›
// Kigo switch on, it hands each F4 press to Kigo instead, over IslandKit (a
// local socket, docs/IslandKit.md in Saddle Island's repo). It knows Kigo by
// its code signature, so only a Kigo signed by bluevisor's team gets the key.
//
// Kigo only listens: it shows no live activities. When Saddle Island isn't
// running the client waits quietly (it retries, backing off to a minute, and
// at once when Saddle Island announces itself); Option+Space works either way.
import Foundation
import IslandKit

final class SaddleIslandLink {
	/// The `action` frame Saddle Island sends for F4 (`IslandKitServer.keyActionID` / `searchKeyAction`).
	static let keyActivity = "@key"
	static let searchAction = "search"

	private let client = IslandClient(name: "Kigo")

	/// `onSearchKey` runs on the main thread for every F4 press Saddle Island hands over.
	init(onSearchKey: @escaping () -> Void) {
		client.onAction = { id, action in
			guard id == SaddleIslandLink.keyActivity, action == SaddleIslandLink.searchAction else { return }
			onSearchKey()
		}
		client.activate()
	}

	deinit { client.invalidate() }
}

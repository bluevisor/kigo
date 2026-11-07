// The global shortcut that opens Kigo, through Carbon's hot keys: they need
// no Accessibility permission.
import Carbon

final class HotKey {
	private var ref: EventHotKeyRef?
	private var handler: EventHandlerRef?
	private let action: () -> Void

	init(action: @escaping () -> Void) {
		self.action = action
		var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
		InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
			guard let userData else { return noErr }
			let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
			DispatchQueue.main.async { hotKey.action() }
			return noErr
		}, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
	}

	/// Registers Space with the shortcut's modifier; false when another app
	/// already owns it.
	@discardableResult
	func register(_ shortcut: Shortcut) -> Bool {
		unregister()
		let modifiers: Int
		switch shortcut {
		case .option: modifiers = optionKey
		case .control: modifiers = controlKey
		case .command: modifiers = cmdKey
		}
		let id = EventHotKeyID(signature: OSType(0x4B49_474F), id: 1)	// 'KIGO'
		let status = RegisterEventHotKey(UInt32(kVK_Space), UInt32(modifiers), id, GetApplicationEventTarget(),
			0, &ref)
		if status != noErr { NSLog("Kigo: couldn't register \(shortcut.name) (\(status))") }
		return status == noErr
	}

	func unregister() {
		if let ref { UnregisterEventHotKey(ref) }
		ref = nil
	}
}

// The floating panel: shows and hides it, sizes it to its content, and turns
// keys into launcher actions.
import AppKit
import Combine
import SwiftUI

/// A borderless panel that takes keys without activating Kigo, so the app you
/// were in keeps its menu bar, like Spotlight.
final class LauncherPanel: NSPanel {
	var keyHandler: ((NSEvent) -> Bool)?

	init() {
		super.init(contentRect: NSRect(x: 0, y: 0, width: 680, height: 56),
			styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
			backing: .buffered, defer: false)
		isFloatingPanel = true
		level = .modalPanel
		collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
		isOpaque = false
		backgroundColor = .clear
		hasShadow = true
		hidesOnDeactivate = false
		isMovable = false
		becomesKeyOnlyIfNeeded = false
		animationBehavior = .none
	}

	override var canBecomeKey: Bool { true }
	override var canBecomeMain: Bool { false }

	override func sendEvent(_ event: NSEvent) {
		if event.type == .keyDown, keyHandler?(event) == true { return }
		super.sendEvent(event)
	}
}

final class LauncherController: NSObject, NSWindowDelegate {
	let model = LauncherModel()
	private let prefs = Prefs.shared
	private let panel = LauncherPanel()
	private var top: CGFloat = 0
	private var subscriptions: Set<AnyCancellable> = []
	var onShortcutChanged: (() -> Void)?

	override init() {
		super.init()
		panel.delegate = self
		panel.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }
		let view = LauncherView(model: model, prefs: prefs,
			onActivate: { [weak self] index in self?.activate(at: index, reveal: false, alternate: false) },
			onBack: { [weak self] in self?.closeSettings() })
		let hosting = NSHostingView(rootView: view)
		hosting.sizingOptions = []
		panel.contentView = hosting

		// Resize after SwiftUI has the new results.
		model.objectWillChange
			.receive(on: RunLoop.main)
			.sink { [weak self] in self?.relayout() }
			.store(in: &subscriptions)
		var shortcut = prefs.shortcut
		prefs.objectWillChange
			.receive(on: RunLoop.main)
			.sink { [weak self] in
				guard let self else { return }
				self.model.update(keepSelection: true)
				if self.prefs.shortcut != shortcut {
					shortcut = self.prefs.shortcut
					self.onShortcutChanged?()
				}
				self.relayout()
			}
			.store(in: &subscriptions)
	}

	var isShowing: Bool { panel.isVisible }

	func toggle() {
		if panel.isVisible && panel.isKeyWindow { hide() } else { show() }
	}

	func show(settings: Bool = false) {
		if !panel.isVisible {
			model.query = ""
			model.confirming = nil
			model.settingsOpen = settings
			model.prepare()
			// On the screen with the pointer, a little above the middle.
			let mouse = NSEvent.mouseLocation
			let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
			let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
			top = visible.maxY - (visible.height * 0.2).rounded()
			panel.setFrame(frame(centerX: visible.midX), display: false)
		} else if settings {
			openSettings()
		}
		panel.makeKeyAndOrderFront(nil)
		if !model.settingsOpen { model.focusToken += 1 }
	}

	func hide() {
		guard panel.isVisible else { return }
		panel.orderOut(nil)
		model.settingsOpen = false
		model.confirming = nil
	}

	func windowDidResignKey(_ notification: Notification) {
		// Click elsewhere and it goes away, like Spotlight.
		hide()
	}

	// Layout ----------------------------------------------------------------

	private func frame(centerX: CGFloat) -> NSRect {
		let m = Metrics(scale: prefs.size.scale)
		let width: CGFloat
		var height = m.field
		if model.settingsOpen {
			width = m.settingsWidth
			let screenBottom = (panel.screen ?? NSScreen.main)?.visibleFrame.minY ?? 0
			let room = top - screenBottom - 40 - m.field - m.footer
			height += 1 + min(m.settingsBody, max(room, m.row * 4)) + 1 + m.footer
		} else {
			width = m.width
			if !model.results.isEmpty { height += 1 + m.listHeight(model.results) + 1 + m.footer }
		}
		return NSRect(x: (centerX - width / 2).rounded(), y: top - height, width: width, height: height)
	}

	private func relayout(animated: Bool = false) {
		guard panel.isVisible else { return }
		let target = frame(centerX: panel.frame.midX)
		guard target != panel.frame else { return }
		if animated {
			NSAnimationContext.runAnimationGroup { context in
				context.duration = 0.18
				context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
				panel.animator().setFrame(target, display: true)
			}
		} else {
			panel.setFrame(target, display: true)
		}
		panel.invalidateShadow()
	}

	// Settings --------------------------------------------------------------

	func openSettings() {
		guard !model.settingsOpen else { return }
		model.settingsOpen = true
		relayout(animated: true)
		panel.makeFirstResponder(nil)
	}

	func closeSettings() {
		guard model.settingsOpen else { return }
		model.settingsOpen = false
		relayout(animated: true)
		model.focusToken += 1
	}

	/// Saves what the panel shows as a PNG, for checking layouts in tests.
	func snapshot(to path: String) {
		guard let view = panel.contentView,
			let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
		view.cacheDisplay(in: view.bounds, to: rep)
		try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
	}

	// Keys ------------------------------------------------------------------

	private func activate(at index: Int? = nil, reveal: Bool, alternate: Bool) {
		switch model.invoke(at: index, reveal: reveal, alternate: alternate) {
		case .hide: hide()
		case .openSettings: openSettings()
		case .failed: NSSound.beep()
		case .stay: break
		}
	}

	private func edit(_ selector: Selector) -> Bool {
		NSApp.sendAction(selector, to: nil, from: panel)
	}

	private func handleKey(_ event: NSEvent) -> Bool {
		let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
		let command = flags.contains(.command)
		let option = flags.contains(.option)
		let control = flags.contains(.control)
		let shift = flags.contains(.shift)
		let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

		// ⌥, or ⌘, : settings, and back.
		if event.keyCode == 43 && (command || option) && !control {
			if model.settingsOpen { closeSettings() } else { openSettings() }
			return true
		}
		if command && !option && !control && (key == "w" || key == "q") {
			hide()
			return true
		}
		if model.settingsOpen {
			if event.keyCode == 53 {
				closeSettings()
				return true
			}
			return false
		}

		switch event.keyCode {
		case 126: model.move(-1); return true
		case 125: model.move(1); return true
		case 116: model.move(-5); return true
		case 121: model.move(5); return true
		case 36, 76:
			activate(reveal: command || option, alternate: shift)
			return true
		case 53:
			if model.query.isEmpty { hide() } else { model.query = "" }
			return true
		case 48:
			if shift { return false }
			model.complete()
			return true
		default: break
		}

		// Emacs-style ⌃N / ⌃P, as in Raycast.
		if control && !command {
			if key == "n" { model.move(1); return true }
			if key == "p" { model.move(-1); return true }
		}

		if command && !option && !control {
			if shift && key == "c" {
				if model.copySelection() { hide() } else { NSSound.beep() }
				return true
			}
			if let digit = Int(key), (1...9).contains(digit) {
				if digit <= model.results.count {
					activate(at: digit - 1, reveal: false, alternate: false)
				} else {
					NSSound.beep()
				}
				return true
			}
			// No menu bar of our own, so the editing keys go straight to the field.
			switch (key, shift) {
			case ("a", false): return edit(#selector(NSText.selectAll(_:)))
			case ("c", false): return edit(#selector(NSText.copy(_:)))
			case ("v", false): return edit(#selector(NSText.paste(_:)))
			case ("x", false): return edit(#selector(NSText.cut(_:)))
			case ("z", false): return edit(Selector(("undo:")))
			case ("z", true): return edit(Selector(("redo:")))
			default: break
			}
		}
		return false
	}
}

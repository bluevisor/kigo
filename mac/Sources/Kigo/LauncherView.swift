// The launcher's look: query field, sectioned results, an action footer, and
// the settings page it grows into.
import AppKit
import SwiftUI

/// Sizes at the Default size; everything scales with the Size setting.
struct Metrics {
	let scale: CGFloat
	var width: CGFloat { (680 * scale).rounded() }
	var settingsWidth: CGFloat { (760 * scale).rounded() }
	var field: CGFloat { (56 * scale).rounded() }
	var row: CGFloat { (40 * scale).rounded() }
	var header: CGFloat { (30 * scale).rounded() }
	var footer: CGFloat { (36 * scale).rounded() }
	var icon: CGFloat { (26 * scale).rounded() }
	var listPadding: CGFloat { (6 * scale).rounded() }
	var settingsBody: CGFloat { (540 * scale).rounded() }
	/// Rounded panel corners, with rows concentric to them.
	var corner: CGFloat { (20 * scale).rounded() }
	var rowCorner: CGFloat { (10 * scale).rounded() }

	func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
		.system(size: (size * scale).rounded(), weight: weight)
	}

	/// The results list's full height: every row and section header. The
	/// panel grows to fit it, up to the bottom of the screen.
	func listHeight(_ results: [Result]) -> CGFloat {
		var height = listPadding * 2
		for (i, result) in results.enumerated() {
			if i == 0 || results[i - 1].section != result.section { height += header }
			height += row
		}
		return height
	}
}

/// An NSTextField, for full control over focus and the caret.
struct QueryField: NSViewRepresentable {
	@Binding var text: String
	let fontSize: CGFloat
	let focusToken: Int

	func makeCoordinator() -> Coordinator { Coordinator(self) }

	func makeNSView(context: Context) -> NSTextField {
		let field = NSTextField()
		field.isBordered = false
		field.drawsBackground = false
		field.focusRingType = .none
		field.lineBreakMode = .byClipping
		field.cell?.isScrollable = true
		field.cell?.wraps = false
		field.placeholderString = "Search apps, files, and commands"
		field.delegate = context.coordinator
		return field
	}

	func updateNSView(_ field: NSTextField, context: Context) {
		context.coordinator.parent = self
		let font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
		if field.font != font { field.font = font }
		if field.stringValue != text { field.stringValue = text }
		if context.coordinator.focusToken != focusToken {
			context.coordinator.focusToken = focusToken
			DispatchQueue.main.async {
				field.window?.makeFirstResponder(field)
				let end = (field.stringValue as NSString).length
				field.currentEditor()?.selectedRange = NSRange(location: end, length: 0)
			}
		}
	}

	final class Coordinator: NSObject, NSTextFieldDelegate {
		var parent: QueryField
		var focusToken = -1

		init(_ parent: QueryField) { self.parent = parent }

		func controlTextDidChange(_ note: Notification) {
			guard let field = note.object as? NSTextField else { return }
			parent.text = field.stringValue
		}
	}
}

struct Keycap: View {
	let text: String
	let metrics: Metrics

	var body: some View {
		Text(text)
			.font(metrics.font(11, .medium))
			.foregroundStyle(.secondary)
			.padding(.horizontal, 5 * metrics.scale)
			.frame(minWidth: 20 * metrics.scale, minHeight: 18 * metrics.scale)
			.background(RoundedRectangle(cornerRadius: 5 * metrics.scale, style: .continuous)
				.fill(Color.primary.opacity(0.08)))
	}
}

struct ResultIcon: View {
	let result: Result
	let size: CGFloat

	var body: some View {
		if let icon = result.icon {
			Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size)
		} else {
			RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
				.fill(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.38)], startPoint: .top,
					endPoint: .bottom))
				.overlay(Image(systemName: result.symbol ?? "questionmark")
					.font(.system(size: size * 0.5, weight: .semibold))
					.foregroundStyle(.white))
				.frame(width: size * 0.86, height: size * 0.86)
				.frame(width: size, height: size)
		}
	}
}

struct ResultRow: View {
	let result: Result
	let selected: Bool
	let confirming: Bool
	/// The theme color, for the selected row.
	let tint: Color
	let metrics: Metrics

	var body: some View {
		HStack(spacing: 12 * metrics.scale) {
			ResultIcon(result: result, size: metrics.icon)
			Text(result.title)
				.font(metrics.font(14))
				.lineLimit(1)
				.layoutPriority(1)
			if !result.subtitle.isEmpty {
				Text(result.subtitle)
					.font(metrics.font(12))
					.foregroundStyle(.secondary)
					.lineLimit(1)
					.truncationMode(.middle)
			}
			Spacer(minLength: 8)
			if confirming {
				Text("Press ↩ again to \(result.title.lowercased())")
					.font(metrics.font(12, .medium))
					.foregroundStyle(.red)
			} else if selected {
				Image(systemName: "return")
					.font(.system(size: 13 * metrics.scale, weight: .medium))
					.foregroundStyle(.secondary)
			} else {
				Text(result.kind.label)
					.font(metrics.font(12))
					.foregroundStyle(.tertiary)
			}
		}
		.padding(.horizontal, 12 * metrics.scale)
		.frame(height: metrics.row)
		.background {
			if selected {
				RoundedRectangle(cornerRadius: metrics.rowCorner, style: .continuous)
					.fill(tint.opacity(0.17))
					.overlay(RoundedRectangle(cornerRadius: metrics.rowCorner, style: .continuous)
						.strokeBorder(tint.opacity(0.42), lineWidth: 1))
			}
		}
		.contentShape(Rectangle())
	}
}

struct SectionHeader: View {
	let title: String
	/// A hairline above every section but the first.
	let separated: Bool
	let metrics: Metrics

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			Rectangle()
				.fill(Color.primary.opacity(separated ? 0.09 : 0))
				.frame(height: 1)
				.padding(.horizontal, 6 * metrics.scale)
			Spacer(minLength: 0)
			Text(title)
				.font(metrics.font(12, .semibold))
				.foregroundStyle(.secondary)
				.lineLimit(1)
				.padding(.horizontal, 12 * metrics.scale)
				.padding(.bottom, 4 * metrics.scale)
		}
		.frame(height: metrics.header)
	}
}

/// The panel's surface: a blurred material (LauncherController) under a
/// mostly solid fill, a hairline border and the window's shadow, so its edge
/// reads clearly on any background.
struct PanelSurface: View {
	let corner: CGFloat

	/// Deep charcoal in dark mode, near white in light, a little see-through.
	static let fill = NSColor(name: nil) { appearance in
		appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
			? NSColor(white: 0.11, alpha: 0.9) : NSColor(white: 0.97, alpha: 0.9)
	}

	var body: some View {
		let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
		shape
			.fill(Color(nsColor: PanelSurface.fill))
			.overlay(shape.strokeBorder(Color.primary.opacity(0.16), lineWidth: 1))
	}
}

struct LauncherView: View {
	@ObservedObject var model: LauncherModel
	@ObservedObject var prefs: Prefs
	let onActivate: (Int) -> Void
	let onBack: () -> Void
	let onSettings: () -> Void

	var body: some View {
		let m = Metrics(scale: prefs.size.scale)
		VStack(spacing: 0) {
			if model.settingsOpen {
				settingsHeader(m)
				divider
				SettingsPage(prefs: prefs, model: model, metrics: m)
					.frame(maxHeight: .infinity)
				divider
				footer(m)
			} else {
				searchHeader(m)
				if !model.results.isEmpty {
					divider
					resultsList(m)
					divider
					footer(m)
				}
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
		.background(PanelSurface(corner: m.corner))
		.tint(Color(nsColor: prefs.theme.color))
		.clipShape(RoundedRectangle(cornerRadius: m.corner, style: .continuous))
	}

	private var divider: some View {
		Rectangle().fill(Color.primary.opacity(0.10)).frame(height: 1)
	}

	private func leaf(_ size: CGFloat) -> some View {
		Image(nsImage: Icons.leaf).resizable().interpolation(.high).frame(width: size, height: size)
	}

	private func searchHeader(_ m: Metrics) -> some View {
		HStack(spacing: 12 * m.scale) {
			Image(systemName: "magnifyingglass")
				.font(.system(size: 19 * m.scale, weight: .medium))
				.foregroundStyle(.secondary)
				.frame(width: (24 * m.scale).rounded())
			QueryField(text: $model.query, fontSize: (21 * m.scale).rounded(), focusToken: model.focusToken)
			Button(action: onSettings) {
				Image(systemName: "gearshape")
					.font(.system(size: 16 * m.scale, weight: .regular))
					.foregroundStyle(.secondary)
					.frame(width: 26 * m.scale, height: 26 * m.scale)
					.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.help("Settings (⌘, or ⌥,)")
			Keycap(text: "⌘,", metrics: m)
		}
		.padding(.leading, 16 * m.scale)
		.padding(.trailing, 14 * m.scale)
		.frame(height: m.field)
	}

	private func settingsHeader(_ m: Metrics) -> some View {
		HStack(spacing: 10 * m.scale) {
			Button(action: onBack) {
				Image(systemName: "chevron.left")
					.font(.system(size: 15 * m.scale, weight: .semibold))
					.foregroundStyle(.secondary)
					.frame(width: 24 * m.scale, height: 24 * m.scale)
					.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			leaf((26 * m.scale).rounded())
			Text("Kigo Settings").font(m.font(18, .semibold))
			Spacer()
		}
		.padding(.horizontal, 14 * m.scale)
		.frame(height: m.field)
	}

	private func resultsList(_ m: Metrics) -> some View {
		ScrollViewReader { proxy in
			ScrollView(.vertical) {
				LazyVStack(alignment: .leading, spacing: 0) {
					ForEach(Array(model.results.enumerated()), id: \.offset) { i, result in
						if i == 0 || model.results[i - 1].section != result.section {
							SectionHeader(title: result.section, separated: i > 0, metrics: m)
						}
						ResultRow(result: result, selected: i == model.selection,
							confirming: model.confirming == result.id, tint: Color(nsColor: prefs.theme.color),
							metrics: m)
							.id(i)
							.onTapGesture { onActivate(i) }
					}
				}
				.padding(.horizontal, 10 * m.scale)
				.padding(.vertical, m.listPadding)
			}
			.scrollIndicators(.never)
			.frame(maxHeight: .infinity)
			.onChange(of: model.selection) { _, selection in
				proxy.scrollTo(selection)
			}
			.onChange(of: model.query) { _, _ in
				proxy.scrollTo(0, anchor: .top)
			}
		}
	}

	private func hint(_ key: String, _ label: String, _ m: Metrics, strong: Bool = false) -> some View {
		HStack(spacing: 6 * m.scale) {
			Keycap(text: key, metrics: m)
			Text(label)
				.font(m.font(12, strong ? .medium : .regular))
				.foregroundStyle(strong ? .primary : .secondary)
		}
	}

	private var footerSeparator: some View {
		Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 1, height: 16).padding(.horizontal, 4)
	}

	private func footer(_ m: Metrics) -> some View {
		HStack(spacing: 8 * m.scale) {
			leaf((20 * m.scale).rounded())
			Text("Kigo").font(m.font(13)).foregroundStyle(.secondary)
			Spacer()
			if model.settingsOpen {
				hint("esc", "Back", m, strong: true)
			} else if let result = model.selected {
				if result.canReveal {
					hint("⌘↩", "Show in Finder", m)
					footerSeparator
				}
				hint("↩", model.confirming == result.id ? "Confirm" : result.primaryAction, m, strong: true)
			}
		}
		.padding(.horizontal, 16 * m.scale)
		.frame(height: m.footer)
	}
}

// Settings ------------------------------------------------------------------

struct SettingsPage: View {
	@ObservedObject var prefs: Prefs
	let model: LauncherModel
	let metrics: Metrics
	@State private var cleared = false

	var body: some View {
		let m = metrics
		ScrollView(.vertical) {
			VStack(alignment: .leading, spacing: 0) {
				section("Search")
				card {
					toggle("Applications", "Apps and System Settings panes", $prefs.searchApps)
					line
					toggle("Files and folders", "Spotlight's index of your home folder", $prefs.searchFiles)
					line
					toggle("Commands", "Sleep, Lock Screen, Empty Trash, folders and more", $prefs.searchCommands)
					line
					toggle("Calculator", "Answers arithmetic as you type", $prefs.calculator)
					line
					row("Web search", "Offered last, for anything else") {
						Picker("", selection: $prefs.webSearch) {
							ForEach(WebSearch.allCases, id: \.self) { Text($0.name).tag($0) }
						}
					}
				}

				section("Suggestions")
				card {
					toggle("Suggest what you use most", "Shown before you type anything", $prefs.suggestions)
					line
					row("Search history", cleared ? "Cleared" : "Forget what you opened; ranking starts over") {
						Button("Clear") {
							model.history.clear()
							model.update(keepSelection: false)
							cleared = true
						}
						.disabled(cleared)
					}
				}

				section("Appearance")
				card {
					row("Theme color", prefs.theme.name) {
						HStack(spacing: 8 * m.scale) {
							ForEach(ThemeColor.allCases, id: \.self) { swatch($0) }
						}
					}
					line
					row("Size", "Text and rows") {
						Picker("", selection: $prefs.size) {
							ForEach(Size.allCases, id: \.self) { Text($0.name).tag($0) }
						}
					}
				}

				section("General")
				card {
					row("Shortcut", "Opens Kigo from anywhere") {
						Picker("", selection: $prefs.shortcut) {
							ForEach(Shortcut.allCases, id: \.self) { Text($0.name).tag($0) }
						}
					}
					if SaddleIslandLink.isInstalled {
						line
						toggle("Search in Saddle Island",
							"\(prefs.shortcut.name) and F4 open the island's search; off, this panel",
							$prefs.islandSearch)
					}
					line
					toggle("Open at login", "Starts Kigo, hidden, when you log in", $prefs.openAtLogin)
					line
					toggle("Update automatically", "Installs new versions from GitHub once a day", $prefs.updates)
				}

				section("About")
				card { about }
			}
			.padding(.horizontal, 16 * m.scale)
			.padding(.bottom, 16 * m.scale)
			.background(GeometryReader { geometry in
				Color.clear.preference(key: ContentHeight.self, value: geometry.size.height)
			})
		}
		.scrollIndicators(.never)
		.onPreferenceChange(ContentHeight.self) { height in
			if abs(model.settingsHeight - height) > 0.5 { model.settingsHeight = height }
		}
		.pickerStyle(.segmented)
		.labelsHidden()
		.controlSize(m.scale > 1.05 ? .regular : .small)
	}

	private var appVersion: String {
		Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
	}

	/// Kigo's mark: 季 (ki, season) in brush calligraphy, the first half of
	/// 季語 (kigo, the season word).
	private var about: some View {
		let m = metrics
		let tint = Color(nsColor: prefs.theme.color)
		let seal = (54 * m.scale).rounded()
		return HStack(spacing: 14 * m.scale) {
			KiShape()
				.fill(tint)
				.frame(width: seal * 0.74, height: seal * 0.74)
				.frame(width: seal, height: seal)
				.background(RoundedRectangle(cornerRadius: 12 * m.scale, style: .continuous)
					.fill(tint.opacity(0.13)))
				.overlay(RoundedRectangle(cornerRadius: 12 * m.scale, style: .continuous)
					.strokeBorder(tint.opacity(0.35), lineWidth: 1))
			VStack(alignment: .leading, spacing: 2 * m.scale) {
				Text("Kigo").font(m.font(15, .semibold))
				Text("The season word: the one word that sets the scene")
					.font(m.font(11)).foregroundStyle(.secondary)
				Text("Version \(appVersion)").font(m.font(11)).foregroundStyle(.tertiary)
			}
			Spacer()
			HStack(spacing: 8) {
				Button("Check for Updates") { Updater.shared.check(manual: true) }
				Button("Quit Kigo") { NSApp.terminate(nil) }
			}
			.fixedSize()
		}
		.padding(.vertical, 12 * m.scale)
	}

	private func section(_ title: String) -> some View {
		Text(title)
			.font(metrics.font(13, .medium))
			.foregroundStyle(.secondary)
			.padding(.leading, 4 * metrics.scale)
			.padding(.top, 14 * metrics.scale)
			.padding(.bottom, 6 * metrics.scale)
	}

	/// One theme color to pick; the chosen one is ringed.
	private func swatch(_ theme: ThemeColor) -> some View {
		let size = (18 * metrics.scale).rounded()
		let chosen = prefs.theme == theme
		return Button { prefs.theme = theme } label: {
			Circle()
				.fill(theme == .system
					? AnyShapeStyle(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
						center: .center))
					: AnyShapeStyle(Color(nsColor: theme.color)))
				.frame(width: size, height: size)
				.overlay(Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5))
				.padding(3)
				.overlay(Circle().strokeBorder(Color.primary.opacity(chosen ? 0.75 : 0), lineWidth: 1.5))
				.contentShape(Circle())
		}
		.buttonStyle(.plain)
		.help(theme.name)
	}

	/// Rows grouped on a bordered card, like System Settings.
	private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
		let shape = RoundedRectangle(cornerRadius: 12 * metrics.scale, style: .continuous)
		return VStack(spacing: 0) { content() }
			.padding(.horizontal, 14 * metrics.scale)
			.background(shape.fill(Color.primary.opacity(0.035)))
			.overlay(shape.strokeBorder(Color.primary.opacity(0.11), lineWidth: 1))
	}

	private var line: some View {
		Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
	}

	private func toggle(_ title: String, _ subtitle: String, _ value: Binding<Bool>) -> some View {
		row(title, subtitle) {
			Toggle("", isOn: value).toggleStyle(.switch)
		}
	}

	private func row<Control: View>(_ title: String, _ subtitle: String,
		@ViewBuilder control: () -> Control) -> some View {
		HStack(spacing: 12) {
			VStack(alignment: .leading, spacing: 2) {
				Text(title).font(metrics.font(13, .medium))
				Text(subtitle).font(metrics.font(11)).foregroundStyle(.secondary)
			}
			Spacer()
			control().fixedSize()
		}
		.padding(.vertical, 9 * metrics.scale)
	}
}

/// The settings page's natural height, so the panel can grow to fit it.
private struct ContentHeight: PreferenceKey {
	static var defaultValue: CGFloat = 0
	static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

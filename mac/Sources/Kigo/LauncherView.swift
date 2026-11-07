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
	var header: CGFloat { (26 * scale).rounded() }
	var footer: CGFloat { (36 * scale).rounded() }
	var icon: CGFloat { (26 * scale).rounded() }
	var listPadding: CGFloat { (6 * scale).rounded() }
	var maxList: CGFloat { row * 9 + header * 2 }
	var settingsBody: CGFloat { (540 * scale).rounded() }
	/// Liquid Glass corners: nearly a capsule around the bare field, and
	/// rows concentric with the panel.
	var corner: CGFloat { (26 * scale).rounded() }
	var rowCorner: CGFloat { (12 * scale).rounded() }

	func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
		.system(size: (size * scale).rounded(), weight: weight)
	}

	/// The results list's height: rows and section headers, up to about nine rows.
	func listHeight(_ results: [Result]) -> CGFloat {
		var height = listPadding * 2
		for (i, result) in results.enumerated() {
			if i == 0 || results[i - 1].section != result.section { height += header }
			height += row
		}
		return min(height, maxList)
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
	let shortcut: Int?
	let metrics: Metrics

	var body: some View {
		HStack(spacing: 10 * metrics.scale) {
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
			} else {
				Text(result.kind.label)
					.font(metrics.font(12))
					.foregroundStyle(.tertiary)
				if let shortcut, selected {
					Keycap(text: "⌘\(shortcut)", metrics: metrics)
				}
			}
		}
		.padding(.horizontal, 10 * metrics.scale)
		.frame(height: metrics.row)
		.background(
			RoundedRectangle(cornerRadius: metrics.rowCorner, style: .continuous)
				.fill(selected ? Color.primary.opacity(0.11) : Color.clear))
		.contentShape(Rectangle())
	}
}

struct SectionHeader: View {
	let title: String
	let metrics: Metrics

	var body: some View {
		Text(title)
			.font(metrics.font(11, .semibold))
			.foregroundStyle(.secondary)
			.lineLimit(1)
			.padding(.horizontal, 10 * metrics.scale)
			.frame(height: metrics.header, alignment: .bottomLeading)
			.padding(.bottom, 2)
	}
}

struct LauncherView: View {
	@ObservedObject var model: LauncherModel
	@ObservedObject var prefs: Prefs
	let onActivate: (Int) -> Void
	let onBack: () -> Void

	var body: some View {
		let m = Metrics(scale: prefs.size.scale)
		VStack(spacing: 0) {
			if model.settingsOpen {
				settingsHeader(m)
				Divider().opacity(0.35)
				SettingsPage(prefs: prefs, model: model, metrics: m)
					.frame(maxHeight: .infinity)
				Divider().opacity(0.35)
				footer(m)
			} else {
				searchHeader(m)
				if !model.results.isEmpty {
					Divider().opacity(0.35)
					resultsList(m)
					Divider().opacity(0.35)
					footer(m)
				}
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
		// The glass behind (LauncherController) is drawn by the window server;
		// this only keeps the content inside the same corners.
		.clipShape(RoundedRectangle(cornerRadius: m.corner, style: .continuous))
	}

	private func searchHeader(_ m: Metrics) -> some View {
		HStack(spacing: 12 * m.scale) {
			Image(systemName: "magnifyingglass")
				.font(.system(size: 18 * m.scale, weight: .medium))
				.foregroundStyle(.secondary)
			QueryField(text: $model.query, fontSize: (21 * m.scale).rounded(), focusToken: model.focusToken)
		}
		.padding(.horizontal, 18 * m.scale)
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
			Text("Settings").font(m.font(18, .semibold))
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
							SectionHeader(title: result.section, metrics: m)
						}
						ResultRow(result: result, selected: i == model.selection,
							confirming: model.confirming == result.id, shortcut: i < 9 ? i + 1 : nil,
							metrics: m)
							.id(i)
							.onTapGesture { onActivate(i) }
					}
				}
				.padding(.horizontal, 10 * m.scale)
				.padding(.vertical, m.listPadding)
			}
			.scrollIndicators(.automatic)
			.frame(height: m.listHeight(model.results))
			.onChange(of: model.selection) { _, selection in
				proxy.scrollTo(selection)
			}
			.onChange(of: model.query) { _, _ in
				proxy.scrollTo(0, anchor: .top)
			}
		}
	}

	private func footer(_ m: Metrics) -> some View {
		HStack(spacing: 8 * m.scale) {
			Image(nsImage: Icons.kigo).resizable().frame(width: 16 * m.scale, height: 16 * m.scale)
			Text("Kigo").font(m.font(12)).foregroundStyle(.secondary)
			Spacer()
			if model.settingsOpen {
				Text("Back").font(m.font(12))
				Keycap(text: "esc", metrics: m)
			} else if let result = model.selected {
				if result.canReveal {
					Text("Show in Finder").font(m.font(12)).foregroundStyle(.secondary)
					Keycap(text: "⌘↩", metrics: m)
					Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 1, height: 14 * m.scale)
						.padding(.horizontal, 2)
				}
				Text(model.confirming == result.id ? "Confirm" : result.primaryAction)
					.font(m.font(12, .medium))
				Keycap(text: "↩", metrics: m)
			}
		}
		.padding(.horizontal, 18 * m.scale)
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
				toggle("Applications", "Apps and System Settings panes", $prefs.searchApps)
				toggle("Files and folders", "Spotlight's index of your home folder", $prefs.searchFiles)
				toggle("Commands", "Sleep, Lock Screen, Empty Trash, folders and more", $prefs.searchCommands)
				toggle("Calculator", "Answers arithmetic as you type", $prefs.calculator)
				row("Web search", "Offered last, for anything else") {
					Picker("", selection: $prefs.webSearch) {
						ForEach(WebSearch.allCases, id: \.self) { Text($0.name).tag($0) }
					}
				}

				section("Suggestions")
				toggle("Suggest what you use most", "Shown before you type anything", $prefs.suggestions)
				row("Search history", cleared ? "Cleared" : "Forget what you opened; ranking starts over") {
					Button("Clear") {
						model.history.clear()
						model.update(keepSelection: false)
						cleared = true
					}
					.disabled(cleared)
				}

				section("Appearance")
				row("Size", "Text and rows") {
					Picker("", selection: $prefs.size) {
						ForEach(Size.allCases, id: \.self) { Text($0.name).tag($0) }
					}
				}

				section("General")
				row("Shortcut", "Opens Kigo from anywhere") {
					Picker("", selection: $prefs.shortcut) {
						ForEach(Shortcut.allCases, id: \.self) { Text($0.name).tag($0) }
					}
				}
				toggle("Open at login", "Starts Kigo, hidden, when you log in", $prefs.openAtLogin)
				row("Kigo \(appVersion)", "Settings: ⌥, or ⌘,") {
					Button("Quit Kigo") { NSApp.terminate(nil) }
				}
			}
			.padding(.horizontal, 18 * m.scale)
			.padding(.bottom, 12 * m.scale)
		}
		.pickerStyle(.segmented)
		.labelsHidden()
		.controlSize(m.scale > 1.05 ? .regular : .small)
	}

	private var appVersion: String {
		Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
	}

	private func section(_ title: String) -> some View {
		Text(title)
			.font(metrics.font(11, .semibold))
			.foregroundStyle(.secondary)
			.padding(.top, 16 * metrics.scale)
			.padding(.bottom, 4 * metrics.scale)
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
				Text(title).font(metrics.font(13))
				Text(subtitle).font(metrics.font(11)).foregroundStyle(.secondary)
			}
			Spacer()
			control().fixedSize()
		}
		.padding(.vertical, 7 * metrics.scale)
	}
}

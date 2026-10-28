import SwiftUI

/// The profile picked for a space: Default (nil), an existing one, or a new one to make.
enum SpaceProfileChoice: Hashable {
	case existing(UUID?)
	case new
}

/// Create or edit a space: name, SF Symbol, colors, intensity, grain, appearance, profile
/// (Arc: SpaceCreation + SpaceStyleEditor + SpaceIconPicker + "Edit Space profile").
struct SpaceEditorView: View {
	let existing: Space?
	let profiles: [BrowserProfile]
	/// Title, symbol, theme, profile; a new profile comes with its name.
	let onSave: (String, String, SpaceTheme, SpaceProfileChoice, String) -> Void
	let onCancel: () -> Void
	/// Every theme change while editing, so the window can show it live.
	var onPreview: (SpaceTheme) -> Void = { _ in }

	@State private var title: String
	@State private var symbol: String
	@State private var customSymbol = ""
	@State private var theme: SpaceTheme
	@State private var profile: SpaceProfileChoice
	@State private var newProfileName = ""

	init(
		existing: Space?, profiles: [BrowserProfile],
		onSave: @escaping (String, String, SpaceTheme, SpaceProfileChoice, String) -> Void,
		onCancel: @escaping () -> Void, onPreview: @escaping (SpaceTheme) -> Void = { _ in }
	) {
		self.onPreview = onPreview
		self.existing = existing
		self.profiles = profiles
		_profile = State(initialValue: .existing(existing?.profileID))
		self.onSave = onSave
		self.onCancel = onCancel
		let t = existing?.theme ?? SpaceTheme.presets[Int.random(in: 0..<5)]
		_title = State(initialValue: existing?.title ?? "")
		_symbol = State(initialValue: existing?.symbolName ?? Space.defaultSymbol)
		_theme = State(initialValue: t)
	}

	var body: some View {
		VStack(spacing: 16) {
			Text(existing == nil ? "New Space" : "Edit Space").font(
				.system(size: 16, weight: .semibold))
			HStack(spacing: 12) {
				// Preview
				ZStack {
					SpaceBackground(palette: theme.palette)
					VStack(spacing: 6) {
						SpaceIcon(symbol: symbol, size: 28).foregroundStyle(
							theme.palette.textPrimary)
						Text(title.isEmpty ? "Space" : title).font(
							.system(size: 13, weight: .semibold)
						).foregroundStyle(theme.palette.textPrimary)
						RoundedRectangle(cornerRadius: 6).fill(theme.palette.selectedFill).frame(
							width: 100, height: 22)
						RoundedRectangle(cornerRadius: 6).fill(theme.palette.hoverFill).frame(
							width: 100, height: 22)
					}
				}
				.frame(width: 180, height: 200)
				.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

				VStack(alignment: .leading, spacing: 10) {
					TextField("Name", text: $title).textFieldStyle(.roundedBorder)
					LazyVGrid(
						columns: Array(repeating: GridItem(.fixed(28), spacing: 4), count: 8),
						spacing: 4
					) {
						ForEach(Space.pickerSymbols, id: \.self) { name in
							Image(systemName: name).font(.system(size: 14, weight: .medium))
								.frame(width: 28, height: 28)
								.background(
									RoundedRectangle(cornerRadius: 6).fill(
										name == symbol ? Color.accentColor.opacity(0.25) : .clear)
								)
								.contentShape(Rectangle())
								.help(name)
								.onTapGesture { symbol = name }
						}
					}
					HStack {
						Text("Symbol name").font(.system(size: 11)).foregroundStyle(.secondary)
						TextField("e.g. sparkles", text: $customSymbol).textFieldStyle(
							.roundedBorder
						)
						.onChange(of: customSymbol) { _, v in
							if let name = Space.validSymbol(v.trimmingCharacters(in: .whitespaces))
							{
								symbol = name
							}
						}
					}
				}
			}
			Divider()
			SpaceLookPicker(theme: $theme)
			Divider()
			profileSection
			HStack {
				Button("Cancel") { onCancel() }.keyboardShortcut(.cancelAction)
				Spacer()
				Button(existing == nil ? "Create Space" : "Save") {
					onSave(
						title.isEmpty ? "Space" : title, symbol, theme,
						profile, trimmedProfileName)
				}
				.keyboardShortcut(.defaultAction)
				.disabled(
					(title.trimmingCharacters(in: .whitespaces).isEmpty && existing == nil)
						|| (profile == .new && trimmedProfileName.isEmpty))
			}
		}
		.padding(20)
		.frame(width: 520)
		.onChange(of: theme) { _, t in onPreview(t) }
	}

	private var trimmedProfileName: String { newProfileName.trimmingCharacters(in: .whitespaces) }

	/// Arc's copy: "Profiles make your Spaces truly separate…" and, when an existing space
	/// changes profile, "Each Profile has different browser data…".
	private var profileSection: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack {
				Picker("Profile", selection: $profile) {
					Text("Default").tag(SpaceProfileChoice.existing(nil))
					ForEach(profiles) { p in Text(p.name).tag(SpaceProfileChoice.existing(p.id)) }
					Divider()
					Text("New Profile…").tag(SpaceProfileChoice.new)
				}
				.frame(width: 260)
				if profile == .new {
					TextField("Profile name", text: $newProfileName).textFieldStyle(.roundedBorder)
				}
			}
			Text(profileNote).font(.system(size: 11)).foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	private var profileNote: String {
		if let existing, profile != .existing(existing.profileID) {
			return
				"Each Profile has different browser data, so you might get logged out of some websites or need to re-install extensions. Open tabs in this space reload."
		}
		if profile == .new {
			return
				"This Space will start fresh in your brand new Profile, signed out of every website."
		}
		return
			"Profiles make your Spaces truly separate with their own logins, cookies and site data. Spaces with the same Profile share them."
	}
}

extension Color {
	var hexString: String {
		let ns = NSColor(self).usingColorSpace(.sRGB) ?? .gray
		return String(
			format: "#%02X%02X%02X", Int(round(ns.redComponent * 255)),
			Int(round(ns.greenComponent * 255)), Int(round(ns.blueComponent * 255)))
	}
}

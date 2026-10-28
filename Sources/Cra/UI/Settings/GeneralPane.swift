import SwiftUI

/// System integration in Dia's card idiom (Dia asks for these in onboarding and shows the
/// default-browser prompt at the top of its Account pane): default browser, Dock, login.
struct GeneralPane: View {
	private let system = SystemIntegration.shared
	@Environment(SidebarStore.self) private var store

	var body: some View {
		@Bindable var store = store
		SettingsCardPane {
			SettingsHeader("System")
			SettingsCard {
				SettingsCardRow {
					Text("Default browser").font(.system(size: 13))
				} trailing: {
					if system.isDefaultBrowser {
						Label("Cra", systemImage: "checkmark.circle.fill").font(.system(size: 13))
							.foregroundStyle(.secondary)
					} else {
						if let name = system.defaultBrowserName {
							Text(name).font(.system(size: 13)).foregroundStyle(.secondary)
						}
						Button(
							system.isPromptingDefault
								? "Confirm in the Dialog…" : "Set Cra as Default"
						) {
							Task { await system.makeDefaultBrowser() }
						}
						.disabled(system.isPromptingDefault)
					}
				}
				SettingsCardDivider()
				SettingsCardRow {
					Text("Dock").font(.system(size: 13))
				} trailing: {
					if system.isInDock {
						Label("Cra is in the Dock", systemImage: "checkmark.circle.fill").font(
							.system(size: 13)
						).foregroundStyle(.secondary)
					} else {
						Button("Add Cra to Dock") {
							if !system.addToDock() { error = "Cra could not be added to the Dock." }
						}
					}
				}
				SettingsCardDivider()
				SettingsCardRow {
					Text("Open Cra at login").font(.system(size: 13))
				} trailing: {
					Toggle(
						"Open Cra at login",
						isOn: Binding(
							get: { system.launchesAtLogin },
							set: { error = system.setLaunchAtLogin($0) })
					)
					.toggleStyle(.switch).labelsHidden()
				}
			}
			if !system.isDefaultBrowser {
				SettingsFootnote("Cra works best as your default browser.")
			}
			if let error { SettingsFootnote(error).foregroundStyle(.red) }
			AppIconSection().padding(.top, 20)

			SettingsHeader("Appearance")
			SettingsCard {
				SettingsCardRow {
					Text("Sidebar position").font(.system(size: 13))
				} trailing: {
					Picker("", selection: $store.settings.sidebarOnRight) {
						Text("Left").tag(false)
						Text("Right").tag(true)
					}
					.pickerStyle(.segmented)
					.labelsHidden()
					.frame(width: 140)
				}
				SettingsCardDivider()
				SettingsCardRow {
					Text("Window transparency").font(.system(size: 13))
				} trailing: {
					Slider(value: $store.settings.windowTransparency, in: 0...1)
						.frame(width: 180)
				}
			}
			SettingsFootnote(
				"The desktop shows through the sidebar and around the page, still tinted with the space's colour and grain. Pages stay opaque."
			)
		}
		.onAppear { system.refresh() }
	}

	@State private var error: String?
}

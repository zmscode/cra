import SwiftUI

enum SidebarSection { case favorites, pinned, today }

/// A tab or a folder (with its children when expanded).
struct SidebarItemView: View {
	let item: SidebarItem
	let depth: Int
	let palette: SpacePalette
	let section: SidebarSection
	@Environment(SidebarStore.self) private var store

	var body: some View {
		if item.isFolder {
			FolderRow(item: item, depth: depth, palette: palette)
			if store.isExpanded(item.id) {
				ForEach(store.children(of: item.id)) { child in
					SidebarItemView(
						item: child, depth: depth + 1, palette: palette, section: section
					)
					.transition(
						.asymmetric(
							insertion: .opacity.combined(with: .offset(y: -6)), removal: .opacity))
				}
				if item.isLiveFolder {
					LiveFolderStatusRow(item: item, depth: depth + 1, palette: palette)
				}
			}
		} else if item.isTab {
			TabRow(item: item, depth: depth, palette: palette, section: section)
		} else if item.isSplit {
			SplitRow(item: item, depth: depth, palette: palette, section: section)
		}
	}
}

struct FaviconView: View {
	let key: String?
	let palette: SpacePalette
	var size: CGFloat = CraMetrics.favicon
	/// Whether the icon sits on a dark fill; defaults to the sidebar's.
	var onDark: Bool?
	@Environment(FaviconCache.self) private var favicons

	var body: some View {
		if let img = favicons.image(forKey: key) {
			// One-color glyphs (GitHub) flip to white on dark fills and black on light ones.
			let dark = onDark ?? palette.isDark
			let flip = favicons.glyphIsDark(forKey: key) == dark
			Image(nsImage: img)
				.resizable()
				.renderingMode(flip ? .template : .original)
				.interpolation(.high)
				.aspectRatio(contentMode: .fit)
				.foregroundStyle(dark ? Color.white.opacity(0.92) : Color.black.opacity(0.85))
				.frame(width: size, height: size)
				.clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
		} else {
			Image(systemName: "globe")
				.font(.system(size: size * 0.8, weight: .regular))
				.foregroundStyle(palette.textTertiary)
				.frame(width: size, height: size)
		}
	}
}

struct TabRow: View {
	let item: SidebarItem
	let depth: Int
	let palette: SpacePalette
	let section: SidebarSection
	@Environment(SidebarStore.self) private var store
	@Environment(SidebarUIState.self) private var ui
	@Environment(\.sidebarActions) private var actions
	@State private var hover = false
	@State private var draft = ""
	@FocusState private var renameFocused: Bool
	@AppStorage("didShowRenameHint") private var didShowRenameHint = false

	private var tab: TabData { item.tab! }
	private var selected: Bool { store.selectedTabID(window: ui.windowID) == item.id }
	/// While tabs are ⌘/⇧-picked the highlight follows the picks, not the open tab.
	private var highlighted: Bool {
		ui.multiSelection.isEmpty ? selected : ui.multiSelection.contains(item.id)
	}
	/// Close acts on every picked tab when this row is one of them.
	private var closeGroup: [UUID] {
		ui.multiSelection.contains(item.id) && ui.multiSelection.count > 1
			? Array(ui.multiSelection) : [item.id]
	}
	private var editing: Bool { ui.renamingID == item.id }
	private var loaded: Bool { ui.loadedTabIDs.contains(item.id) }
	private var pinned: Bool { section != .today }
	private var navigatedAway: Bool { pinned && tab.url != tab.savedURL && !tab.savedURL.isEmpty }
	/// Arc shows the host under a pinned tab only when it has left the pinned
	/// site (navigating within the same host shows nothing).
	private var subtitle: String? {
		// A live folder's pull request by someone else shows its author (Arc's sidebarItemSubtitleTextField).
		if let author = tab.liveSubtitle, URL(string: tab.url)?.host == "github.com" {
			return author
		}
		guard navigatedAway, let host = URL(string: tab.url)?.host,
			let saved = URL(string: tab.savedURL)?.host,
			host.replacingOccurrences(of: "www.", with: "")
				!= saved.replacingOccurrences(of: "www.", with: "")
		else { return nil }
		return host.replacingOccurrences(of: "www.", with: "")
	}

	var body: some View {
		let session = ui
		HStack(spacing: 11) {
			Group {
				if tab.liveItemURL != nil && tab.customIconKey == nil {
					GitHubMarkIcon(palette: palette)
				} else {
					FaviconView(key: tab.iconKey, palette: palette)
				}
			}
			.frame(width: CraMetrics.favicon)
			if editing {
				TextField("", text: $draft)
					.textFieldStyle(.plain)
					.font(.system(size: 14))
					.focused($renameFocused)
					.onSubmit { commitRename() }
					.onExitCommand { ui.renamingID = nil }
					.onAppear {
						draft = item.title ?? item.displayTitle
						renameFocused = true
					}
					.onChange(of: renameFocused) { _, f in if !f && editing { commitRename() } }
			} else {
				VStack(alignment: .leading, spacing: 1) {
					Text(item.displayTitle)
						.font(.system(size: 14))
						.foregroundStyle(palette.textPrimary)
						.lineLimit(1)
						.truncationMode(.tail)
					if let subtitle {
						Text(subtitle).font(.system(size: 11)).foregroundStyle(palette.textTertiary)
							.lineLimit(1)
					}
				}
			}
			Spacer(minLength: 4)
			if ui.capturingTabIDs.contains(item.id) {
				// Arc's recording indicator; a red dot by the title, with Arc's tooltip.
				Circle().fill(Color.red).frame(width: 7, height: 7)
					.frame(width: 16, height: 16)
					.contentShape(Rectangle())
					.arcTooltip("This tab is using your camera or microphone")
			}
			if tab.muted {
				SidebarIconButton(
					symbol: "speaker.slash.fill", palette: palette, help: "Unmute Tab", size: 20,
					iconSize: 10
				) {
					store.setMuted(item.id, false)
					actions.performAction("muteTab:\(item.id)")
				}
			}
			if item.isUnread && !selected && !hover {
				Circle().fill(palette.textPrimary.opacity(0.55)).frame(width: 6, height: 6)
			}
			if hover && !editing {
				if navigatedAway {
					SidebarIconButton(
						symbol: "arrow.uturn.backward", palette: palette,
						help: "Back to pinned page", size: 22
					) {
						actions.resetPinnedTab(item.id)
					}
				}
				if closeGroup.count > 1 {
					SidebarIconButton(
						symbol: "xmark", palette: palette,
						help: "Close \(closeGroup.count) Tabs (⌘W)", size: 22
					) {
						closeTabs(closeGroup)
					}
				} else if pinned && selected {
					// Arc: the open pinned tab shows a minus; it unloads and stays pinned.
					SidebarIconButton(
						symbol: "minus", palette: palette, help: "Close and Keep Pinned (⌘W)",
						size: 22
					) {
						closeTabs([item.id])
					}
				} else if pinned {
					// Arc: any other pinned tab shows ✕, which archives it out of the pinned section.
					SidebarIconButton(
						symbol: "xmark", palette: palette, help: "Archive this tab", size: 22
					) {
						withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
							store.archiveTab(item.id, reason: .manual)
						}
					}
				} else {
					SidebarIconButton(
						symbol: "xmark", palette: palette, help: "Archive (⌘W)", size: 22
					) {
						closeTabs(closeGroup)
					}
				}
			}
		}
		.padding(.leading, 8 + CGFloat(depth) * CraMetrics.indent)
		.padding(.trailing, 6)
		.frame(height: CraMetrics.rowHeight)
		.background(
			RoundedRectangle(cornerRadius: CraMetrics.rowCorner, style: .continuous)
				.fill(palette.raised(highlighted ? palette.selectedFill : (hover ? palette.hoverFill : .clear)))
				.shadow(
					color: highlighted && !palette.isDark ? .black.opacity(0.06) : .clear,
					radius: 3, y: 1)
		)
		.overlay { if ui.keyboardFocusID == item.id { FocusRing(radius: CraMetrics.rowCorner) } }
		.contentShape(Rectangle())
		.onHover { inside in
			hover = inside
			ui.hoverDraggable(item.id, inside)
			if inside {
				ui.hoveredTabID = item.id
			} else if ui.hoveredTabID == item.id {
				ui.hoveredTabID = nil
			}
		}
		.onTapGesture {
			let event = NSApp.currentEvent
			let flags = event?.modifierFlags.intersection([.command, .shift]) ?? []
			if !flags.isEmpty {
				ui.pick(item.id, range: flags.contains(.shift), in: store)
			} else if event?.clickCount == 2 {
				ui.renamingID = item.id
			} else {
				// A click on the row (not the field) ends a rename, so it can never get stuck.
				if editing { commitRename() }
				ui.clearPicks(anchor: item.id)
				ui.keyboardFocusID = nil
				store.selectTab(item.id, window: ui.windowID)
			}
		}
		.draggable(SidebarDragItem.begin(item.id, session)) {
			// The page's last screenshot over its title; dragging one of several picked tabs
			// moves them all.
			VStack(alignment: .leading, spacing: 6) {
				if let shot = actions.tabSnapshot(item.id) {
					Image(nsImage: shot)
						.resizable()
						.aspectRatio(contentMode: .fill)
						.frame(width: 200, height: 133)
						.clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
						.overlay(
							RoundedRectangle(cornerRadius: 6, style: .continuous)
								.strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
				}
				HStack(spacing: 8) {
					FaviconView(key: tab.iconKey, palette: palette)
					Text(item.displayTitle).font(.system(size: 13)).lineLimit(1)
					Spacer(minLength: 0)
					if closeGroup.count > 1 {
						Text("\(closeGroup.count)")
							.font(.system(size: 11, weight: .semibold))
							.foregroundStyle(.white)
							.padding(.horizontal, 6)
							.frame(minWidth: 18, minHeight: 18)
							.background(Capsule().fill(Color.accentColor))
					}
				}
				.padding(.horizontal, 2)
			}
			.frame(width: 200)
			.padding(6)
			.background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.regularMaterial))
		}
		.iconMenu(palette: palette, enabled: { !editing }) {
			closeGroup.count > 1 ? groupMenuItems : menuItems
		}
		// Arc's row tip is the tab's title by the pointer; the close buttons' own tips win over it.
		// Like Arc (didShowRenameHint), "Double-click to rename" rides along once.
		.arcTooltip(
			editing ? "" : item.displayTitle, followsCursor: true,
			subtitle: didShowRenameHint || item.title != nil ? nil : "Double-click to rename",
			onShow: { if !didShowRenameHint && item.title == nil { didShowRenameHint = true } }
		)
		.modifier(SidebarDropPreview(id: item.id, palette: palette, depth: depth))
	}

	private func commitRename() {
		guard editing else { return }
		store.rename(item.id, to: draft)
		ui.renamingID = nil
	}

	private func closeTabs(_ ids: [UUID]) {
		// The open tab goes last so closing it doesn't hop through tabs about to close.
		let open = store.selectedTabID(window: ui.windowID)
		let ordered = ids.filter { $0 != open } + ids.filter { $0 == open }
		withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
			for id in ordered { actions.closeTab(id) }
			ui.multiSelection.subtract(ids)
		}
	}

	/// The icon menu for this tab (IconMenu).
	private var menuItems: [[IconMenuItem]] {
		let fav = store.isFavorite(item.id)
		var edit = [
			IconMenuItem(title: "Rename", symbol: "pencil") { ui.renamingID = item.id },
			IconMenuItem(title: "Duplicate", symbol: "plus.square.on.square") {
				store.duplicateTab(item.id)
			},
			IconMenuItem(title: "Copy Link", symbol: "link") {
				NSPasteboard.general.clearContents()
				NSPasteboard.general.setString(tab.url, forType: .string)
			},
			IconMenuItem(
				title: tab.muted ? "Unmute" : "Mute",
				symbol: tab.muted ? "speaker.wave.2" : "speaker.slash"
			) {
				store.setMuted(item.id, !tab.muted)
				actions.performAction("muteTab:\(item.id)")
			},
		]
		if navigatedAway {
			edit.append(
				IconMenuItem(title: "Back to Pinned Page", symbol: "arrow.uturn.backward") {
					actions.resetPinnedTab(item.id)
				})
		}
		// A pinned tab closes (stays pinned, unloaded) or archives (leaves the list).
		var end: [IconMenuItem] = []
		if pinned, selected || loaded {
			end.append(
				IconMenuItem(title: "Close and Keep Pinned", symbol: "xmark") {
					actions.closeTab(item.id)
				})
		}
		end.append(
			IconMenuItem(title: "Archive", symbol: "archivebox", destructive: true) {
				pinned ? store.archiveTab(item.id, reason: .manual) : actions.closeTab(item.id)
			})
		return [
			[
				IconMenuItem(title: pinned ? "Unpin" : "Pin", symbol: pinned ? "pin.slash" : "pin") {
					pinned ? store.unpinTab(item.id) : store.pinTab(item.id)
				},
				IconMenuItem(
					title: fav ? "Unfavourite" : "Favourite", symbol: fav ? "star.slash" : "star"
				) {
					fav ? store.removeFromFavorites(item.id) : store.addToFavorites(item.id)
				},
				splitItem,
			],
			edit, end,
		]
	}

	/// Pair with the open tab (or join its split), give it an empty pane, or take it out.
	private var splitItem: IconMenuItem {
		let current = store.selectedTabID(window: ui.windowID)
		if store.splitContaining(item.id) != nil {
			return IconMenuItem(title: "Unsplit", symbol: "rectangle.split.2x1.slash") {
				actions.separatePane(item.id)
			}
		}
		if let current, current != item.id, store.paneTabIDs(for: current).count < 4 {
			return IconMenuItem(title: "Split", symbol: "rectangle.split.2x1") {
				if let split = store.splitContaining(current) {
					store.addToSplit(split.id, tabID: item.id, at: nil)
				} else if let split = store.createSplit(with: [current, item.id], at: current),
					let focus = split.split?.focusTabID
				{
					// A pinned tab stays put and a copy becomes its pane: show the split's.
					store.selectTab(focus, window: ui.windowID)
				}
			}
		}
		return IconMenuItem(title: "Split with New Tab", symbol: "rectangle.split.2x1") {
			if current != item.id { store.selectTab(item.id, window: ui.windowID) }
			actions.performAction("addSplitView")
		}
	}

	/// The icon menu for several picked tabs.
	private var groupMenuItems: [[IconMenuItem]] {
		let ids = closeGroup
		var first = [
			IconMenuItem(title: "New Folder with \(ids.count) Tabs", symbol: "folder.badge.plus") {
				withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
					ui.renamingID = store.createFolder(with: ids).id
				}
			}
		]
		if (2...4).contains(ids.count) {
			first.append(
				IconMenuItem(title: "Open \(ids.count) Tabs in Split View", symbol: "rectangle.split.2x1") {
					if let split = store.createSplit(with: ids, at: item.id),
						let focus = split.split?.focusTabID
					{
						store.selectTab(focus, window: ui.windowID)
					}
					ui.clearPicks()
				})
		}
		return [
			first,
			[IconMenuItem(title: "Deselect All", symbol: "xmark.circle") { ui.clearPicks() }],
			[
				IconMenuItem(title: "Close \(ids.count) Tabs", symbol: "xmark", destructive: true) {
					closeTabs(ids)
				}
			],
		]
	}
}

struct FolderRow: View {
	let item: SidebarItem
	let depth: Int
	let palette: SpacePalette
	@Environment(SidebarStore.self) private var store
	@Environment(SidebarUIState.self) private var ui
	@State private var hover = false
	@State private var draft = ""
	@FocusState private var renameFocused: Bool

	private var expanded: Bool { store.isExpanded(item.id) }
	private var editing: Bool { ui.renamingID == item.id }

	var body: some View {
		let session = ui
		let glyph = palette.folderColors(item.folderIcon)
		HStack(spacing: 11) {
			if item.isLiveFolder {
				LiveFolderIcon(palette: palette, style: item.folderIcon, expanded: expanded).frame(
					width: CraMetrics.favicon)
			} else {
				ZStack {
					if !expanded {
						Image(systemName: "folder.fill").foregroundStyle(glyph.fill)
					}
					Image(systemName: "folder").foregroundStyle(glyph.tint)
				}
				.font(.system(size: 15, weight: .regular))
				.frame(width: CraMetrics.favicon)
			}
			if editing {
				TextField("", text: $draft)
					.textFieldStyle(.plain)
					.font(.system(size: 14, weight: .medium))
					.focused($renameFocused)
					.onSubmit { commitRename() }
					.onExitCommand { ui.renamingID = nil }
					.onAppear {
						draft = item.title ?? ""
						renameFocused = true
					}
					.onChange(of: renameFocused) { _, f in if !f && editing { commitRename() } }
			} else {
				Text(item.title ?? "Folder")
					.font(.system(size: 14, weight: .medium))
					.lineLimit(1)
			}
			Spacer()
			if item.isLiveFolder {
				LiveFolderAccessory(item: item, palette: palette, hover: hover && !editing)
					.padding(.trailing, 7)
			} else if hover && !expanded {
				Text("\(store.tabs(under: item.id).count)")
					.font(.system(size: 11, weight: .medium))
					.foregroundStyle(palette.textTertiary)
					.padding(.trailing, 8)
			}
		}
		.padding(.leading, 8 + CGFloat(depth) * CraMetrics.indent)
		.frame(height: CraMetrics.rowHeight)
		.background(
			RoundedRectangle(cornerRadius: CraMetrics.rowCorner, style: .continuous).fill(
				palette.raised(hover ? palette.hoverFill : .clear))
		)
		.contentShape(Rectangle())
		.onHover {
			hover = $0
			ui.hoverDraggable(item.id, $0)
		}
		// Every click toggles, however fast they come: double-click-to-rename made
		// quick open/close clicks start a rename that then swallowed the clicks.
		// Rename stays in the context menu. No count: 2 gesture either: it makes
		// SwiftUI hold every single click for the double-click interval.
		.onTapGesture {
			if editing { commitRename() }
			withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
				store.setExpanded(item.id, !expanded)
			}
		}
		.draggable(SidebarDragItem.begin(item.id, session))
		// A live folder's menu holds its settings, so it stays the system menu.
		.contextMenu { if item.isLiveFolder { LiveFolderMenu(item: item) } }
		.iconMenu(palette: palette, enabled: { !item.isLiveFolder && !editing }) {
			folderMenuItems
		}
		.modifier(SidebarDropPreview(id: item.id, palette: palette))
	}

	/// The folder's icon menu (IconMenu). Its icon colour cycles Auto → White → Black.
	private var folderMenuItems: [[IconMenuItem]] {
		let next: FolderIconStyle? =
			switch item.folderIcon {
			case nil: .white
			case .white: .black
			case .black: nil
			}
		let nextName = next.map { $0 == .white ? "White" : "Black" } ?? "Auto"
		return [
			[
				IconMenuItem(title: "Rename", symbol: "pencil") { ui.renamingID = item.id },
				IconMenuItem(title: "New Folder Inside", symbol: "folder.badge.plus") {
					let f = store.createFolder(named: "New Folder", in: item.id, index: 0)
					store.setExpanded(item.id, true)
					ui.renamingID = f.id
				},
				IconMenuItem(title: "Icon Colour: \(nextName)", symbol: "circle.lefthalf.filled") {
					store.setFolderIcon(next, for: item.id)
				},
			],
			[
				IconMenuItem(title: "Delete Folder (archives tabs)", symbol: "trash", destructive: true) {
					store.deleteFolder(item.id)
				}
			],
		]
	}

	private func commitRename() {
		guard editing else { return }
		store.rename(item.id, to: draft.isEmpty ? "Folder" : draft)
		ui.renamingID = nil
	}
}

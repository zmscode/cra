import AppKit
import SwiftUI

/// A tab's right-click menu as a row of icon buttons (like the space dock) instead of the system menu (a first
/// pass: several picked tabs still get the system menu, and folders aren't in it yet).
@MainActor
enum TabActionMenu {
	private static var panel: TabActionMenuPanel?
	private static var monitors: [Any] = []
	private static var resignObserver: NSObjectProtocol?

	/// Opens the menu centred just below the pointer, kept on the pointer's screen.
	static func show(_ content: AnyView, dark: Bool) {
		close()
		let host = NSHostingView(rootView: content)
		let size = host.fittingSize
		let mouse = NSEvent.mouseLocation
		let screen =
			NSScreen.screens.first { $0.frame.contains(mouse) }?.visibleFrame ?? .zero
		// Centred under the click, nudged back inside the screen near its edges.
		var origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height - 8)
		origin.x = min(max(screen.minX + 4, origin.x), screen.maxX - size.width - 4)
		origin.y = min(max(screen.minY + 4, origin.y), screen.maxY - size.height - 4)
		let p = TabActionMenuPanel(
			contentRect: NSRect(origin: origin, size: size),
			styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
		p.isOpaque = false
		p.backgroundColor = .clear
		p.hasShadow = true
		p.level = .popUpMenu
		p.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
		p.contentView = host
		p.alphaValue = 0
		p.orderFrontRegardless()
		NSAnimationContext.runAnimationGroup { ctx in
			ctx.duration = 0.12
			p.animator().alphaValue = 1
		}
		panel = p
		// Any click outside the menu, or Esc, closes it; the click still goes where it was aimed.
		monitors.append(
			NSEvent.addLocalMonitorForEvents(matching: [
				.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown,
			]) { e in
				if e.type == .keyDown {
					if e.keyCode == 53 {
						close()
						return nil
					}
				} else if e.window !== panel {
					close()
				}
				return e
			} as Any)
		monitors.append(
			NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
				Task { @MainActor in close() }
			} as Any)
		resignObserver = NotificationCenter.default.addObserver(
			forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
		) { _ in Task { @MainActor in close() } }
	}

	static func close() {
		monitors.forEach(NSEvent.removeMonitor)
		monitors = []
		if let o = resignObserver { NotificationCenter.default.removeObserver(o) }
		resignObserver = nil
		guard let p = panel else { return }
		panel = nil
		NSAnimationContext.runAnimationGroup { ctx in
			ctx.duration = 0.1
			p.animator().alphaValue = 0
		} completionHandler: {
			p.orderOut(nil)
		}
	}
}

final class TabActionMenuPanel: NSPanel {
	override var canBecomeKey: Bool { false }
}

/// The menu's contents for one tab.
struct TabActionMenuView: View {
	let item: SidebarItem
	let pinned: Bool
	let navigatedAway: Bool
	@Environment(SidebarStore.self) private var store
	@Environment(SidebarUIState.self) private var ui
	@Environment(\.sidebarActions) private var actions

	private var tab: TabData { item.tab! }

	var body: some View {
		HStack(spacing: 2) {
			row(pinned ? "Unpin" : "Pin", symbol: pinned ? "pin.slash" : "pin") {
				pinned ? store.unpinTab(item.id) : store.pinTab(item.id)
			}
			row(
				store.isFavorite(item.id) ? "Unfavourite" : "Favourite",
				symbol: store.isFavorite(item.id) ? "star.slash" : "star"
			) {
				store.isFavorite(item.id)
					? store.removeFromFavorites(item.id) : store.addToFavorites(item.id)
			}
			splitRow
			separator
			row("Rename", symbol: "pencil") { ui.renamingID = item.id }
			row("Duplicate", symbol: "plus.square.on.square") { store.duplicateTab(item.id) }
			row("Copy Link", symbol: "link") {
				NSPasteboard.general.clearContents()
				NSPasteboard.general.setString(tab.url, forType: .string)
			}
			row(tab.muted ? "Unmute" : "Mute", symbol: tab.muted ? "speaker.wave.2" : "speaker.slash") {
				store.setMuted(item.id, !tab.muted)
				actions.performAction("muteTab:\(item.id)")
			}
			if navigatedAway {
				separator
				row("Back to Pinned Page", symbol: "arrow.uturn.backward") {
					actions.resetPinnedTab(item.id)
				}
			}
			separator
			row("Archive", symbol: "archivebox", destructive: true) { actions.closeTab(item.id) }
		}
		.padding(4)
		.fixedSize()
		.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: 10, style: .continuous)
				.strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
	}

	private var separator: some View {
		Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 0.5, height: 16)
			.padding(.horizontal, 3)
	}

	/// Pair with the open tab (or join its split), give it an empty pane, or take it out.
	@ViewBuilder private var splitRow: some View {
		let current = store.selectedTabID(window: ui.windowID)
		if store.splitContaining(item.id) != nil {
			row("Unsplit", symbol: "rectangle.split.2x1.slash") { actions.separatePane(item.id) }
		} else if let current, current != item.id, store.paneTabIDs(for: current).count < 4 {
			row("Split", symbol: "rectangle.split.2x1") {
				if let split = store.splitContaining(current) {
					store.addToSplit(split.id, tabID: item.id, at: nil)
				} else if let split = store.createSplit(with: [current, item.id], at: current),
					let focus = split.split?.focusTabID
				{
					store.selectTab(focus, window: ui.windowID)
				}
			}
		} else {
			row("Split", symbol: "rectangle.split.2x1") {
				if current != item.id { store.selectTab(item.id, window: ui.windowID) }
				actions.performAction("addSplitView")
			}
		}
	}

	/// One icon button; its name shows as a tooltip.
	private func row(
		_ title: String, symbol: String, destructive: Bool = false,
		action: @escaping () -> Void
	) -> some View {
		Button {
			TabActionMenu.close()
			action()
		} label: {
			Image(systemName: symbol)
				.font(.system(size: 13))
				.foregroundStyle(destructive ? Color.red : Color.primary)
				.frame(width: 28, height: 28)
				.contentShape(Rectangle())
		}
		.buttonStyle(MenuHoverStyle(cornerRadius: 6))
		.help(title)
		.accessibilityLabel(title)
	}
}

/// Hover and press fill for the menu's buttons.
private struct MenuHoverStyle: ButtonStyle {
	let cornerRadius: CGFloat

	func makeBody(configuration: Configuration) -> some View {
		HoverBody(configuration: configuration, cornerRadius: cornerRadius)
	}

	private struct HoverBody: View {
		let configuration: ButtonStyleConfiguration
		let cornerRadius: CGFloat
		@State private var hover = false

		var body: some View {
			configuration.label
				.background(
					RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
						.fill(
							Color.primary.opacity(
								configuration.isPressed ? 0.14 : (hover ? 0.08 : 0))))
				.onHover { hover = $0 }
		}
	}
}

/// Takes right-clicks (and ⌃-clicks) over a view and nothing else: other clicks pass through
/// to the SwiftUI content underneath.
struct RightClickCatcher: NSViewRepresentable {
	var enabled: () -> Bool
	let onRightClick: () -> Void

	func makeNSView(context: Context) -> CatcherView { CatcherView() }

	func updateNSView(_ view: CatcherView, context: Context) {
		view.enabled = enabled
		view.onRightClick = onRightClick
	}

	final class CatcherView: NSView {
		var enabled: () -> Bool = { true }
		var onRightClick: () -> Void = {}

		override func hitTest(_ point: NSPoint) -> NSView? {
			guard let e = NSApp.currentEvent, enabled() else { return nil }
			let right =
				e.type == .rightMouseDown
				|| (e.type == .leftMouseDown && e.modifierFlags.contains(.control))
			return right ? super.hitTest(point) : nil
		}

		override func rightMouseDown(with event: NSEvent) { onRightClick() }
		override func mouseDown(with event: NSEvent) { onRightClick() }
	}
}


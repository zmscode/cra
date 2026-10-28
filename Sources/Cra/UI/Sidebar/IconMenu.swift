import AppKit
import SwiftUI

/// One button of an icon menu; its title shows as the tooltip.
struct IconMenuItem {
	let title: String
	let symbol: String
	var destructive = false
	let action: () -> Void
}

/// Cra's right-click menus: a small panel of icon buttons in groups, like the space dock,
/// instead of the system menu. Opens centred just below the pointer.
@MainActor
enum IconMenu {
	private static var panel: IconMenuPanel?
	/// The hovered button's name, in the sidebar's tooltip style, above the menu.
	private static var tip: LittleTooltipPanel?
	/// The palette of the space the menu belongs to; the tip takes its colours.
	private static var palette: SpacePalette?
	private static var monitors: [Any] = []
	private static var resignObserver: NSObjectProtocol?

	/// Opens a menu of these groups (empty groups are skipped).
	static func show(_ groups: [[IconMenuItem]], palette: SpacePalette) {
		let groups = groups.filter { !$0.isEmpty }
		guard !groups.isEmpty else { return }
		show(AnyView(IconMenuView(groups: groups)), dark: palette.isDark)
		self.palette = palette
	}

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
		let p = IconMenuPanel(
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

	private(set) static var tipTitle: String?

	/// Shows `title` centred above a button (its frame in the menu's own coordinates, top-left
	/// origin), at once: a menu shouldn't make you wait for a tip. nil hides it.
	static func showTip(_ title: String?, over button: CGRect) {
		tipTitle = title
		guard let title, let panel else {
			tip?.orderOut(nil)
			tip = nil
			return
		}
		let host = NSHostingView(rootView: IconMenuTip(text: title, palette: palette))
		let size = host.fittingSize
		host.setFrameSize(size)
		let t = tip ?? LittleTooltipPanel()
		t.level = .popUpMenu
		t.contentView = host
		let midX = panel.frame.minX + button.midX
		let screen = panel.screen?.visibleFrame ?? .infinite
		let x = min(max(screen.minX + 4, midX - size.width / 2), screen.maxX - size.width - 4)
		t.setFrame(
			NSRect(x: x, y: panel.frame.maxY + 4, width: size.width, height: size.height),
			display: true)
		if t.parent == nil { panel.addChildWindow(t, ordered: .above) }
		t.orderFrontRegardless()
		tip = t
	}

	static func close() {
		showTip(nil, over: .zero)
		monitors.forEach(NSEvent.removeMonitor)
		monitors = []
		if let o = resignObserver { NotificationCenter.default.removeObserver(o) }
		resignObserver = nil
		palette = nil
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

final class IconMenuPanel: NSPanel {
	override var canBecomeKey: Bool { false }
}

extension View {
	/// Right-click (or ⌃-click) opens an icon menu of `items`, built at the click so it
	/// reflects the state then. While `enabled` is false the click passes to the view.
	func iconMenu(
		palette: SpacePalette, enabled: @escaping () -> Bool = { true },
		items: @escaping () -> [[IconMenuItem]]
	) -> some View {
		overlay(RightClickCatcher(enabled: enabled) { IconMenu.show(items(), palette: palette) })
	}
}

/// A button's name over the menu, in its space's colours: the space's gradient behind the
/// space's own text colour, the sidebar tip's shape.
private struct IconMenuTip: View {
	let text: String
	let palette: SpacePalette?

	var body: some View {
		let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
		Text(text)
			.font(.system(size: 12, weight: .medium))
			.foregroundStyle(palette?.textPrimary ?? .white)
			.padding(.horizontal, 9)
			.frame(height: 24)
			.background(
				shape.fill(
					palette.map { AnyShapeStyle($0.gradient) }
						?? AnyShapeStyle(Color(white: 0.15))))
			.overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
			.fixedSize()
	}
}

/// The menu's buttons in a row, groups split by hairlines.
struct IconMenuView: View {
	let groups: [[IconMenuItem]]

	var body: some View {
		HStack(spacing: 2) {
			ForEach(groups.indices, id: \.self) { g in
				if g > 0 {
					Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 0.5, height: 16)
						.padding(.horizontal, 3)
				}
				ForEach(groups[g].indices, id: \.self) { i in
					button(groups[g][i])
				}
			}
		}
		.padding(4)
		.fixedSize()
		.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: 10, style: .continuous)
				.strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
	}

	private func button(_ item: IconMenuItem) -> some View {
		IconMenuButton(item: item)
	}
}

/// One button of the menu; hovering it shows its name above the menu (IconMenu.showTip).
private struct IconMenuButton: View {
	let item: IconMenuItem
	@State private var frame: CGRect = .zero

	var body: some View {
		Button {
			IconMenu.close()
			item.action()
		} label: {
			Image(systemName: item.symbol)
				.font(.system(size: 13))
				.foregroundStyle(item.destructive ? Color.red : Color.primary)
				.frame(width: 28, height: 28)
				.contentShape(Rectangle())
		}
		.buttonStyle(MenuHoverStyle(cornerRadius: 6))
		.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
		.onHover { inside in
			if inside {
				IconMenu.showTip(item.title, over: frame)
			} else if IconMenu.tipTitle == item.title {
				IconMenu.showTip(nil, over: .zero)
			}
		}
		.accessibilityLabel(item.title)
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
/// to the SwiftUI content underneath. Where menus nest (a split row and its panes, the list and
/// its rows), the smallest one under the pointer takes the click, like nested context menus.
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
		private static let all = NSHashTable<CatcherView>.weakObjects()

		override init(frame: NSRect) {
			super.init(frame: frame)
			Self.all.add(self)
		}
		required init?(coder: NSCoder) { fatalError() }

		override func hitTest(_ point: NSPoint) -> NSView? {
			guard let e = NSApp.currentEvent, enabled() else { return nil }
			let right =
				e.type == .rightMouseDown
				|| (e.type == .leftMouseDown && e.modifierFlags.contains(.control))
			guard right, let hit = super.hitTest(point) else { return nil }
			let area = bounds.width * bounds.height
			let inner = Self.all.allObjects.contains { other in
				// A switched-off inner catcher still keeps the click from the outer one: its
				// view's own system menu (a live folder's) gets it.
				other !== self && other.window === window && !other.isHiddenOrHasHiddenAncestor
					&& other.bounds.width * other.bounds.height < area
					&& other.bounds.contains(other.convert(e.locationInWindow, from: nil))
			}
			return inner ? nil : hit
		}

		override func rightMouseDown(with event: NSEvent) { onRightClick() }
		override func mouseDown(with event: NSEvent) { onRightClick() }
	}
}

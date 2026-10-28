import AppKit
import SwiftUI

/// Focus for an inline rename field: it takes the cursor as soon as it appears (its window
/// becoming key first, since a page window may hold the keyboard) and keeps it until the
/// rename ends: Return or Escape in the field, or a click anywhere outside it. Focus that
/// wanders off without such a click (a page taking the keyboard back) is taken back.
struct RenameFieldFocus: ViewModifier {
	let focused: FocusState<Bool>.Binding
	let isEditing: () -> Bool
	/// Ends the rename, keeping the text (a click outside the field).
	let commit: () -> Void
	@State private var anchor = RenameFieldAnchor()

	func body(content: Content) -> some View {
		content
			.focused(focused)
			.background(RenameFieldAnchor.Marker(anchor: anchor))
			.onAppear {
				anchor.start(isEditing: isEditing, commit: commit)
				takeFocus()
			}
			.onDisappear { anchor.stop() }
			.onChange(of: focused.wrappedValue) { _, f in
				if !f, isEditing() { takeFocus() }
			}
	}

	/// On the next pass: a field asked for focus in the pass that adds it isn't in its window
	/// yet, and the request was dropped.
	private func takeFocus() {
		DispatchQueue.main.async {
			guard isEditing() else { return }
			if let w = anchor.view?.window, !w.isKeyWindow { w.makeKey() }
			focused.wrappedValue = true
		}
	}
}

/// Where the field is, and the click monitor that ends the rename on a click outside it.
@MainActor
final class RenameFieldAnchor {
	weak var view: NSView?
	private var monitor: Any?

	func start(isEditing: @escaping () -> Bool, commit: @escaping () -> Void) {
		stop()
		monitor = NSEvent.addLocalMonitorForEvents(matching: [
			.leftMouseDown, .rightMouseDown, .otherMouseDown,
		]) { [weak self] e in
			guard let v = self?.view, isEditing() else { return e }
			let inside =
				e.window === v.window && v.bounds.contains(v.convert(e.locationInWindow, from: nil))
			// After the click has gone where it was aimed (a row it selects, a button).
			if !inside { DispatchQueue.main.async { if isEditing() { commit() } } }
			return e
		}
	}

	func stop() {
		if let monitor { NSEvent.removeMonitor(monitor) }
		monitor = nil
	}

	struct Marker: NSViewRepresentable {
		let anchor: RenameFieldAnchor
		func makeNSView(context: Context) -> NSView { PassThrough() }
		func updateNSView(_ view: NSView, context: Context) { anchor.view = view }
	}

	private final class PassThrough: NSView {
		override func hitTest(_ point: NSPoint) -> NSView? { nil }
	}
}

extension View {
	/// See RenameFieldFocus.
	func renameFocus(
		_ focused: FocusState<Bool>.Binding, isEditing: @escaping () -> Bool,
		commit: @escaping () -> Void
	) -> some View {
		modifier(RenameFieldFocus(focused: focused, isEditing: isEditing, commit: commit))
	}
}

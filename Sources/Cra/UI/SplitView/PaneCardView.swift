import AppKit
import SwiftUI

/// One content pane: Arc's rounded card with its toolbar strip on top and the
/// page below (ARCUI.SplitViewContentPaneView + Arc.WindowContentViewController).
/// A pane without a page (Arc's "Search or Enter URL…" pane) is a translucent
/// tinted card with nothing but the toolbar.
final class PaneCardView: NSView {
	let tabID: UUID
	let toolbarHost: NSHostingView<AnyView>
	/// Where the Chromium view lives (or where the page window is positioned).
	let webArea = NSView()
	/// Hairline under the toolbar when the pane has no page (Arc draws it on the tinted card).
	private let hairline = NSView()
	/// The card behind the toolbar, in the toolbar's colour. A card with a page paints nothing else:
	/// under the page window's anti-aliased corners any fill of the card's shape shows as a light rim.
	private let toolbarBackground = NSView()
	/// The page's stand-in fill under the page window, inset from the card's rounded edges: the
	/// page window's corners are anti-aliased, so a fill reaching the card's edge showed through
	/// them as a light rim in every rounded corner.
	private let pageBackground = NSView()
	var showToolbar = true { didSet { needsLayout = true } }
	var toolbarHeight: CGFloat = CraMetrics.toolbarHeight { didSet { needsLayout = true } }
	var cornerRadius: CGFloat = CraMetrics.contentCornerRadius {
		didSet {
			layer?.cornerRadius = cornerRadius
			needsLayout = true
			syncShadow()
		}
	}
	/// Drop shadow and faint glow around the card. The card clips its own layer, so they live
	/// in a sibling view right below it that follows its frame.
	private let shadowView = CardShadowView()
	/// White page card, or Arc's tinted translucent empty pane.
	var hasPage = true { didSet { refreshBackground() } }
	var isDark = false {
		didSet {
			refreshBackground()
			shadowView.isDark = isDark
		}
	}
	/// The page's own background ("#RRGGBB"; white until it reports one). The page window trails
	/// the card by a frame or more while the window is resized quickly; in that gap the
	/// page area must look like the page, not like a white card.
	var pageColor: String? { didSet { refreshBackground() } }
	/// The toolbar's colour (the page's theme-color, white until it reports one). A white backing
	/// under a dark bar shows through the bar's anti-aliased left edge as a 1px light line.
	var toolbarColor: String? { didSet { refreshBackground() } }
	/// The no-tab stand-in: toolbar on the gradient, no card at all.
	var transparent = false {
		didSet {
			refreshBackground()
			syncShadow()
		}
	}
	/// While a pane is being dragged open/closed its page keeps its last size.
	var frozenWebBounds: NSRect?
	/// The page is on screen in another window: Arc keeps the tab selected here and shows a
	/// blurred snapshot of it (BlurredItemContent) until this window is used again.
	var elsewhereSnapshot: NSImage? {
		didSet {
			guard elsewhereSnapshot !== oldValue else { return }
			elsewhereView.layer?.contents = elsewhereSnapshot.flatMap(Self.blurred)
		}
	}
	var showsElsewhere = false { didSet { elsewhereView.isHidden = !showsElsewhere } }
	private let elsewhereView = NSView()

	init(tabID: UUID, toolbar: AnyView) {
		self.tabID = tabID
		toolbarHost = NSHostingView(rootView: toolbar)
		super.init(frame: .zero)
		wantsLayer = true
		layer?.cornerRadius = cornerRadius
		layer?.cornerCurve = .continuous
		layer?.masksToBounds = true
		toolbarHost.sizingOptions = []
		webArea.wantsLayer = true
		webArea.autoresizesSubviews = false
		pageBackground.wantsLayer = true
		pageBackground.layer?.cornerCurve = .continuous
		toolbarBackground.wantsLayer = true
		hairline.wantsLayer = true
		hairline.isHidden = true
		elsewhereView.wantsLayer = true
		elsewhereView.layer?.contentsGravity = .resizeAspectFill
		elsewhereView.layer?.cornerCurve = .continuous
		elsewhereView.layer?.masksToBounds = true
		elsewhereView.isHidden = true
		addSubview(pageBackground)
		addSubview(elsewhereView)
		addSubview(webArea)
		addSubview(toolbarBackground)
		addSubview(hairline)
		addSubview(toolbarHost)
		refreshBackground()
	}

	required init?(coder: NSCoder) { fatalError() }

	override func viewDidMoveToSuperview() {
		super.viewDidMoveToSuperview()
		if let superview {
			superview.addSubview(shadowView, positioned: .below, relativeTo: self)
		} else {
			shadowView.removeFromSuperview()
		}
		syncShadow()
	}

	override func setFrameOrigin(_ newOrigin: NSPoint) {
		super.setFrameOrigin(newOrigin)
		syncShadow()
	}

	override func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		syncShadow()
	}

	override var isHidden: Bool { didSet { syncShadow() } }

	private func syncShadow() {
		// A square card fills the window (fullscreen) and the no-tab stand-in has no card.
		shadowView.isHidden = isHidden || transparent || cornerRadius == 0
		shadowView.update(card: frame, cornerRadius: cornerRadius)
	}

	private func refreshBackground() {
		// Measured on Arc 1.170 (Victor theme, 2x): the empty pane is the
		// gradient plus about +9/+11/+12 per channel, i.e. a white veil at ~0.2.
		layer?.backgroundColor =
			transparent || hasPage
			? NSColor.clear.cgColor : NSColor(white: 1, alpha: isDark ? 0.08 : 0.2).cgColor
		let bar = toolbarColor.map { NSColor(Color(hex: $0)) } ?? .white
		toolbarBackground.layer?.backgroundColor =
			(hasPage && !transparent ? bar : NSColor.clear).cgColor
		let page = pageColor.map { NSColor(Color(hex: $0)) } ?? .white
		pageBackground.layer?.backgroundColor =
			(hasPage && !transparent ? page : NSColor.clear).cgColor
		hairline.isHidden = hasPage || transparent || !showToolbar
		hairline.layer?.backgroundColor = NSColor(white: isDark ? 1 : 0, alpha: 0.08).cgColor
	}

	override func layout() {
		super.layout()
		let b = bounds
		let th: CGFloat = showToolbar ? toolbarHeight : 0
		toolbarHost.isHidden = th == 0
		toolbarHost.frame = NSRect(x: 0, y: b.height - th, width: b.width, height: th)
		toolbarBackground.frame = toolbarHost.frame
		hairline.frame = NSRect(x: 0, y: b.height - th - 1, width: b.width, height: 1)
		hairline.isHidden = hasPage || transparent || th == 0
		webArea.frame = NSRect(x: 0, y: 0, width: b.width, height: max(0, b.height - th))
		// The page window rounds the card's corners itself. Its stand-in fill keeps 1 pt clear of
		// every rounded edge: the same radius on the inset rect stays at least 1 pt inside the
		// page's curve, so the page's edge pixels only ever blend with the gradient behind the card.
		let rounded = cornerRadius > 0
		let inset: CGFloat = rounded ? 1 : 0
		var fill = webArea.frame.insetBy(dx: inset, dy: 0)
		fill.origin.y += inset
		fill.size.height = max(0, fill.height - (th == 0 ? 2 * inset : inset))
		pageBackground.frame = fill
		pageBackground.layer?.cornerRadius = rounded ? cornerRadius : 0
		pageBackground.layer?.maskedCorners =
			th == 0
			? [
				.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner,
				.layerMaxXMaxYCorner,
			]
			: [.layerMinXMinYCorner, .layerMaxXMinYCorner]
		elsewhereView.frame = fill
		elsewhereView.layer?.cornerRadius = pageBackground.layer?.cornerRadius ?? 0
		elsewhereView.layer?.maskedCorners = pageBackground.layer?.maskedCorners ?? []
		let wb = frozenWebBounds ?? webArea.bounds
		for sub in webArea.subviews where sub.frame != wb { sub.frame = wb }
	}

	/// The snapshot (the tab switcher's thumbnail of the top of the page), blurred hard enough
	/// that its low resolution doesn't show, cropped back to its own size so the edges stay opaque.
	private static func blurred(_ image: NSImage) -> CGImage? {
		guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
			return nil
		}
		let input = CIImage(cgImage: cg)
		let radius = Double(cg.width) * 0.03
		guard
			let filter = CIFilter(
				name: "CIGaussianBlur",
				parameters: [kCIInputImageKey: input.clampedToExtent(), kCIInputRadiusKey: radius]),
			let output = filter.outputImage?.cropped(to: input.extent),
			let result = CIContext().createCGImage(output, from: input.extent)
		else { return nil }
		return result
	}
}

/// The shadow and glow of a PaneCardView, drawn only outside the card's rounded rect: anything
/// under the page window's anti-aliased corners would show through them as a rim.
final class CardShadowView: NSView {
	static let outset: CGFloat = 32
	var isDark = false { didSet { updateColors() } }
	private let shadowLayer = CALayer()
	private let glowLayer = CALayer()

	override init(frame: NSRect) {
		super.init(frame: frame)
		wantsLayer = true
		for l in [shadowLayer, glowLayer] {
			l.shadowOpacity = 1
			l.mask = CAShapeLayer()
			layer?.addSublayer(l)
		}
		shadowLayer.shadowRadius = 10
		shadowLayer.shadowOffset = CGSize(width: 0, height: -2)
		glowLayer.shadowRadius = 4
		glowLayer.shadowOffset = .zero
		updateColors()
	}

	required init?(coder: NSCoder) { fatalError() }

	/// The shadow never takes clicks meant for the sidebar or the window background.
	override func hitTest(_ point: NSPoint) -> NSView? { nil }

	func update(card: NSRect, cornerRadius: CGFloat) {
		let o = Self.outset
		let target = card.insetBy(dx: -o, dy: -o)
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		if frame != target { frame = target }
		let local = NSRect(x: o, y: o, width: card.width, height: card.height)
		// The card and the page window round with `.continuous` corners; a circular arc
		// leaves a sliver of glow inside each corner where the two curves differ.
		let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
			.path(in: local).cgPath
		// Everything but the card: the shadows show around it and never under it.
		let outside = CGMutablePath()
		outside.addRect(bounds)
		outside.addPath(shape)
		for l in [shadowLayer, glowLayer] {
			l.frame = bounds
			l.shadowPath = shape
			if let mask = l.mask as? CAShapeLayer {
				mask.frame = bounds
				mask.path = outside
				mask.fillRule = .evenOdd
			}
		}
		CATransaction.commit()
	}

	private func updateColors() {
		shadowLayer.shadowColor = NSColor.black.withAlphaComponent(isDark ? 0.35 : 0.18).cgColor
		glowLayer.shadowColor = NSColor.white.withAlphaComponent(isDark ? 0.10 : 0.35).cgColor
	}
}

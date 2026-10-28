import SwiftUI

/// A space's look in one panel: appearance, a dot field of colours with one handle per
/// gradient colour, preset swatches, and wave (intensity) and grain sliders. Modelled on
/// Yab's Settings › Appearance › Look.
struct SpaceLookPicker: View {
	@Binding var theme: SpaceTheme
	/// Where each colour's handle sits in the field, 0...1 on both axes.
	@State private var handles: [CGPoint] = []
	@State private var presetPage = 0

	static let maxColors = 3
	private static let swatchesPerPage = 9

	var body: some View {
		VStack(spacing: 12) {
			ZStack(alignment: .top) {
				ColorDotField(handles: $handles, brightness: brightness) { syncColors() }
					.frame(height: 170)
				appearanceSwitch.padding(.top, 8)
				HStack(spacing: 18) {
					Button {
						removeColor()
					} label: {
						Image(systemName: "minus")
					}
					.disabled(handles.count <= 1)
					.help("Remove Color")
					Button {
						addColor()
					} label: {
						Image(systemName: "plus")
					}
					.disabled(handles.count >= Self.maxColors)
					.help("Add Color")
				}
				.buttonStyle(.plain)
				.font(.system(size: 13, weight: .medium))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 12)
				.frame(height: 24)
				.background(Capsule().fill(.regularMaterial))
				.frame(maxHeight: .infinity, alignment: .bottom)
				.padding(.bottom, 8)
			}
			.frame(height: 170)
			.background(
				RoundedRectangle(cornerRadius: 12, style: .continuous).fill(
					Color.primary.opacity(0.05)))
			swatches
			WaveSlider(value: $theme.intensity, knob: knobColor)
				.frame(height: 26)
				.help("Intensity")
			GrainSlider(value: $theme.noise)
				.frame(height: 22)
				.help("Grain")
		}
		.onAppear { handles = theme.colors.prefix(Self.maxColors).map(Self.point(forHex:)) }
		.onChange(of: theme.appearance) { syncColors() }
	}

	// MARK: Appearance

	private var appearanceSwitch: some View {
		HStack(spacing: 2) {
			ForEach(
				[
					("auto", "sparkles", "Auto"), ("light", "sun.max", "Light"),
					("dark", "moon.stars", "Dark"),
				],
				id: \.0
			) { tag, symbol, help in
				let on = theme.appearance == tag
				Button {
					theme.appearance = tag
				} label: {
					Image(systemName: symbol)
						.font(.system(size: 12, weight: .medium))
						.frame(width: 30, height: 24)
						.background(Capsule().fill(on ? Color.primary.opacity(0.14) : .clear))
						.contentShape(Capsule())
				}
				.buttonStyle(.plain)
				.foregroundStyle(on ? .primary : .secondary)
				.help(help)
			}
		}
		.padding(3)
		.background(Capsule().fill(.regularMaterial))
	}

	// MARK: Presets

	private var swatches: some View {
		let presets = SpaceTheme.allPresets
		let pages = max(1, Int(ceil(Double(presets.count) / Double(Self.swatchesPerPage))))
		let start = presetPage * Self.swatchesPerPage
		let shown = Array(presets[start..<min(presets.count, start + Self.swatchesPerPage)])
		return HStack(spacing: 8) {
			Button {
				presetPage = (presetPage + pages - 1) % pages
			} label: {
				Image(systemName: "chevron.left")
			}
			.disabled(pages == 1)
			ForEach(shown.indices, id: \.self) { i in
				let p = shown[i]
				Circle().fill(p.palette.gradient).frame(width: 24, height: 24)
					.overlay(
						Circle().strokeBorder(
							p.colors == theme.colors ? Color.primary : Color.primary.opacity(0.15),
							lineWidth: p.colors == theme.colors ? 2 : 1)
					)
					.contentShape(Circle())
					.onTapGesture { apply(p) }
			}
			Button {
				presetPage = (presetPage + 1) % pages
			} label: {
				Image(systemName: "chevron.right")
			}
			.disabled(pages == 1)
		}
		.buttonStyle(.plain)
		.font(.system(size: 12, weight: .semibold))
		.foregroundStyle(.secondary)
	}

	private func apply(_ preset: SpaceTheme) {
		theme.colors = preset.colors
		theme.intensity = preset.intensity
		theme.noise = preset.noise
		theme.appearance = preset.appearance
		theme.vibrant = preset.vibrant
		theme.accent = preset.accent
		handles = preset.colors.prefix(Self.maxColors).map(Self.point(forHex:))
	}

	// MARK: Colours

	/// Picked colours are stored darker for a dark space and lighter for a light one, so
	/// the same spot in the field reads well either way. Dark stays at 55% so a colour keeps
	/// its hue instead of going muddy.
	private var brightness: Double {
		switch theme.appearance {
		case "dark": return 0.55
		case "light": return 0.93
		default: return 0.85
		}
	}

	private var knobColor: Color { Color(hex: theme.colors.first ?? "#888888") }

	private func addColor() {
		guard handles.count < Self.maxColors, let last = handles.last else { return }
		// The next colour a third of the way round the wheel, at the same strength.
		let (hue, sat) = Self.hueSaturation(at: last)
		handles.append(
			Self.point(hue: (hue + 1.0 / 3).truncatingRemainder(dividingBy: 1), saturation: sat))
		syncColors()
	}

	private func removeColor() {
		guard handles.count > 1 else { return }
		handles.removeLast()
		syncColors()
	}

	private func syncColors() {
		guard !handles.isEmpty else { return }
		theme.colors = handles.map { Self.hex(at: $0, brightness: brightness) }
		// The toolbar band follows the picked colour, not a preset's old accent.
		theme.accent = nil
	}

	// MARK: Field geometry: hue goes round the centre, saturation grows outward.

	static func hueSaturation(at p: CGPoint) -> (Double, Double) {
		let dx = Double(p.x - 0.5) * 2
		let dy = Double(p.y - 0.5) * 2
		let angle = atan2(dy, dx)
		let hue = (angle / (2 * .pi) + 1).truncatingRemainder(dividingBy: 1)
		return (hue, min(1, hypot(dx, dy) / sqrt(2) * 1.25))
	}

	static func point(hue: Double, saturation: Double) -> CGPoint {
		let r = min(1, saturation) * sqrt(2) / 1.25
		let a = hue * 2 * .pi
		return CGPoint(
			x: min(1, max(0, 0.5 + cos(a) * r / 2)), y: min(1, max(0, 0.5 + sin(a) * r / 2)))
	}

	static func point(forHex hex: String) -> CGPoint {
		let ns = NSColor(Color(hex: hex)).usingColorSpace(.sRGB) ?? .gray
		return point(hue: Double(ns.hueComponent), saturation: Double(ns.saturationComponent))
	}

	static func color(at p: CGPoint, brightness: Double) -> Color {
		let (h, s) = hueSaturation(at: p)
		return Color(hue: h, saturation: s, brightness: brightness)
	}

	static func hex(at p: CGPoint, brightness: Double) -> String {
		color(at: p, brightness: brightness).hexString
	}
}

/// The grid of coloured dots. Dots near a handle swell, and each handle is a ringed disc
/// in its colour that follows the pointer.
private struct ColorDotField: View {
	@Binding var handles: [CGPoint]
	let brightness: Double
	let onChange: () -> Void
	@State private var dragging: Int?

	private let columns = 30, rows = 14

	var body: some View {
		GeometryReader { geo in
			let size = geo.size
			Canvas { ctx, _ in
				let inset: CGFloat = 14
				let w = size.width - 2 * inset
				let h = size.height - 2 * inset
				for row in 0..<rows {
					for col in 0..<columns {
						let p = CGPoint(
							x: CGFloat(col) / CGFloat(columns - 1),
							y: CGFloat(row) / CGFloat(rows - 1))
						let at = CGPoint(x: inset + p.x * w, y: inset + p.y * h)
						let near =
							handles.map { hypot($0.x * w - p.x * w, $0.y * h - p.y * h) }.min()
							?? 99
						let r = 1.6 + max(0, 1 - near / 46) * 2.6
						ctx.fill(
							Path(
								ellipseIn: CGRect(
									x: at.x - r, y: at.y - r, width: 2 * r, height: 2 * r)),
							with: .color(SpaceLookPicker.color(at: p, brightness: 0.92)))
					}
				}
				for (i, hp) in handles.enumerated() {
					let at = CGPoint(x: inset + hp.x * w, y: inset + hp.y * h)
					let r: CGFloat = i == 0 ? 15 : 11
					let disc = CGRect(x: at.x - r, y: at.y - r, width: 2 * r, height: 2 * r)
					ctx.fill(Path(ellipseIn: disc.insetBy(dx: -3, dy: -3)), with: .color(.white))
					ctx.fill(
						Path(ellipseIn: disc),
						with: .color(
							SpaceLookPicker.color(at: hp, brightness: max(brightness, 0.55))))
				}
			}
			.contentShape(Rectangle())
			.gesture(
				DragGesture(minimumDistance: 0)
					.onChanged { g in
						let inset: CGFloat = 14
						let p = CGPoint(
							x: min(1, max(0, (g.location.x - inset) / (size.width - 2 * inset))),
							y: min(1, max(0, (g.location.y - inset) / (size.height - 2 * inset))))
						if dragging == nil {
							// Grab the nearest handle; a press away from all of them moves the main one.
							let d = handles.enumerated().map {
								(
									$0.offset,
									hypot(
										($0.element.x - p.x) * size.width,
										($0.element.y - p.y) * size.height)
								)
							}
							dragging = d.filter { $0.1 < 24 }.min { $0.1 < $1.1 }?.0 ?? 0
						}
						if let i = dragging, handles.indices.contains(i) {
							handles[i] = p
							onChange()
						}
					}
					.onEnded { _ in dragging = nil }
			)
		}
	}
}

/// Intensity as a wave: flat when washed out, taller as the colour gets stronger. The knob
/// shows the space's main colour.
private struct WaveSlider: View {
	@Binding var value: Double
	let knob: Color

	var body: some View {
		GeometryReader { geo in
			let w = geo.size.width
			let h = geo.size.height
			let knobR: CGFloat = 11
			let x = knobR + CGFloat(value) * (w - 2 * knobR)
			ZStack(alignment: .leading) {
				Path { p in
					let amp = 1 + CGFloat(value) * (h / 2 - 4)
					p.move(to: CGPoint(x: 0, y: h / 2))
					for px in stride(from: CGFloat(0), through: w, by: 1) {
						p.addLine(to: CGPoint(x: px, y: h / 2 + sin(px / 9) * amp))
					}
				}
				.stroke(Color.primary.opacity(0.35), lineWidth: 1.6)
				Circle().fill(knob)
					.overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
					.frame(width: 2 * knobR, height: 2 * knobR)
					.shadow(color: .black.opacity(0.25), radius: 2, y: 1)
					.offset(x: x - knobR)
			}
			.contentShape(Rectangle())
			.gesture(
				DragGesture(minimumDistance: 0).onChanged { g in
					value = Double(min(1, max(0, (g.location.x - knobR) / (w - 2 * knobR))))
				})
		}
	}
}

/// Grain as scattered dots that thicken to the right, with a capsule thumb.
private struct GrainSlider: View {
	@Binding var value: Double

	var body: some View {
		GeometryReader { geo in
			let w = geo.size.width
			let h = geo.size.height
			let x = 4 + CGFloat(value) * (w - 8)
			ZStack(alignment: .leading) {
				Canvas { ctx, size in
					var rng = SeededRandom(seed: 7)
					for _ in 0..<420 {
						let u = rng.next()
						// Denser toward the right: keep a dot with probability u.
						guard rng.next() < u * u else { continue }
						let px = u * size.width
						let py = 3 + rng.next() * (size.height - 6)
						ctx.fill(
							Path(ellipseIn: CGRect(x: px, y: py, width: 1.6, height: 1.6)),
							with: .color(Color.primary.opacity(0.55)))
					}
				}
				Capsule().fill(Color.white)
					.frame(width: 7, height: h)
					.shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
					.offset(x: x - 3.5)
			}
			.contentShape(Rectangle())
			.gesture(
				DragGesture(minimumDistance: 0).onChanged { g in
					value = Double(min(1, max(0, (g.location.x - 4) / (w - 8))))
				})
		}
	}
}

/// Same dots on every redraw.
private struct SeededRandom {
	var state: UInt64
	init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 }
	mutating func next() -> CGFloat {
		state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
		return CGFloat(state >> 11) / CGFloat(1 << 53)
	}
}

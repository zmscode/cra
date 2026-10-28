import AppKit
import SwiftUI

/// Spaces show an SF Symbol instead of their emoji. `Space.emoji` is still stored (importers
/// and upstream files fill it); `Space.symbol` wins when set, otherwise the emoji maps to a
/// close symbol.
extension Space {
	static let defaultSymbol = "leaf"

	var symbolName: String { Self.validSymbol(symbol) ?? Self.symbol(forEmoji: emoji) }

	static func validSymbol(_ name: String?) -> String? {
		guard let name, !name.isEmpty,
			NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
		else { return nil }
		return name
	}

	static func symbol(forEmoji emoji: String) -> String {
		let key = emoji.unicodeScalars.filter { $0.value != 0xFE0F }.map(String.init).joined()
		return emojiSymbols[key] ?? defaultSymbol
	}

	/// The editor's grid, in order.
	static let pickerSymbols = [
		"leaf", "briefcase", "house", "paintpalette", "flask", "books.vertical", "gamecontroller",
		"music.note", "cart", "airplane", "lightbulb", "flame", "water.waves", "fork.knife",
		"bird", "laptopcomputer", "chart.line.uptrend.xyaxis", "brain", "heart", "star", "moon",
		"cup.and.saucer", "figure.run", "camera", "film", "puzzlepiece", "tree", "mountain.2",
		"hammer", "dollarsign.circle", "pencil", "target", "globe", "folder", "bookmark",
		"graduationcap", "person", "person.2", "building.2", "terminal",
	]

	private static let emojiSymbols: [String: String] = [
		"🌱": "leaf", "💼": "briefcase", "🏠": "house", "🎨": "paintpalette", "🧪": "flask",
		"📚": "books.vertical", "🎮": "gamecontroller", "🎵": "music.note", "🛒": "cart",
		"✈": "airplane", "💡": "lightbulb", "🔥": "flame", "🌊": "water.waves",
		"🍕": "fork.knife", "🐦": "bird", "🧑‍💻": "laptopcomputer",
		"📈": "chart.line.uptrend.xyaxis", "🧠": "brain", "❤": "heart", "⭐": "star",
		"🌙": "moon", "☕": "cup.and.saucer", "🏃": "figure.run", "📷": "camera", "🎬": "film",
		"🧩": "puzzlepiece", "🪴": "tree", "🏔": "mountain.2", "🛠": "hammer",
		"💰": "dollarsign.circle", "📝": "pencil", "🎯": "target", "🕶": "eyeglasses",
		"🗂": "folder", "🌐": "globe", "🌀": "tornado", "📁": "folder", "🔖": "bookmark",
		"🧭": "safari", "🦊": "pawprint", "🏢": "building.2", "🎓": "graduationcap",
		"👤": "person", "👥": "person.2", "💻": "laptopcomputer",
	]
}

/// A space's symbol, sized like the emoji text it replaces.
struct SpaceIcon: View {
	let name: String
	var size: CGFloat = 13

	init(_ space: Space, size: CGFloat = 13) {
		name = space.symbolName
		self.size = size
	}

	init(symbol: String, size: CGFloat = 13) {
		name = symbol
		self.size = size
	}

	var body: some View {
		Image(systemName: name)
			.font(.system(size: size * 0.9, weight: .medium))
			.symbolRenderingMode(.hierarchical)
			.frame(width: size * 1.3, height: size * 1.3)
	}
}

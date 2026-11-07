// Jauge de progression dans l'icône du Dock : pastille du pourcentage en haut à droite, barre en bas.
// `clear()` rend l'icône d'origine.

import AppKit

@MainActor
final class DockProgress {
    private let base: NSImage?
    private var last: Int?
    private let fill = NSColor(srgbRed: 0xe5 / 255, green: 0x48 / 255, blue: 0x3a / 255, alpha: 1)  // couleur du logo

    init() { base = NSApp?.applicationIconImage }

    func set(_ percent: Int) {
        let p = max(0, min(100, percent))
        guard let base, p != last else { return }
        last = p
        let size = NSSize(width: 512, height: 512)
        let img = NSImage(size: size, flipped: true) { rect in
            base.draw(in: rect)
            let s = rect.width
            // Pastille du pourcentage
            let badge = NSRect(x: s * 0.42, y: s * 0.04, width: s * 0.56, height: s * 0.26)
            NSColor(white: 0, alpha: 200 / 255).setFill()
            NSBezierPath(roundedRect: badge, xRadius: badge.height / 2, yRadius: badge.height / 2).fill()
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: s * 0.17), .foregroundColor: NSColor.white]
            let text = NSAttributedString(string: "\(p) %", attributes: attrs)
            let ts = text.size()
            text.draw(at: NSPoint(x: badge.midX - ts.width / 2, y: badge.midY - ts.height / 2))
            // Barre de progression
            let track = NSRect(x: s * 0.08, y: s * 0.82, width: s * 0.84, height: s * 0.11)
            NSColor(white: 0, alpha: 200 / 255).setFill()
            NSBezierPath(roundedRect: track, xRadius: track.height / 2, yRadius: track.height / 2).fill()
            let inner = track.insetBy(dx: 6, dy: 6)
            if p > 0 {
                let done = NSRect(x: inner.minX, y: inner.minY, width: max(inner.height, inner.width * CGFloat(p) / 100), height: inner.height)
                self.fill.setFill()
                NSBezierPath(roundedRect: done, xRadius: inner.height / 2, yRadius: inner.height / 2).fill()
            }
            return true
        }
        NSApp.applicationIconImage = img
    }

    func clear() {
        guard last != nil else { return }
        last = nil
        NSApp.applicationIconImage = base
    }
}

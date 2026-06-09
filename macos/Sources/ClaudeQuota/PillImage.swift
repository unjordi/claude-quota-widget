import AppKit

/// Renders the self-contained colored pill shown in the menu bar — a rounded
/// rect filled with the status color and the percentage in white, with no
/// dependency on the system icon theme. The AppKit analogue of the Rectangle +
/// Label in the plasmoid's compactRepresentation.
enum PillImage {
    static func render(text: String, color: NSColor) -> NSImage {
        let font = NSFont.systemFont(ofSize: 11, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)

        let height: CGFloat = 16          // leaves margin inside the ~22pt menu bar
        let hPadding: CGFloat = 6
        let width = max(height, ceil(textSize.width) + hPadding * 2)

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()

        let rect = NSRect(x: 0, y: 0, width: width, height: height).insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        color.setFill()
        path.fill()
        // Subtle darker border, matching Qt.darker(color, 1.3) in the plasmoid.
        NSColor(white: 0, alpha: 0.25).setStroke()
        path.lineWidth = 1
        path.stroke()

        let textRect = NSRect(
            x: (width - textSize.width) / 2,
            y: (height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        (text as NSString).draw(in: textRect, withAttributes: attrs)

        image.unlockFocus()
        image.isTemplate = false          // keep the color — not a monochrome template
        return image
    }
}

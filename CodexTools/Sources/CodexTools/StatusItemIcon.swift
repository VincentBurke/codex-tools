import AppKit

private let statusIconCanvasSize = NSSize(width: 18, height: 18)

func makeStatusItemImage() -> NSImage {
    let image = NSImage(size: statusIconCanvasSize, flipped: false) { rect in
        NSColor.black.setFill()
        NSColor.black.setStroke()
        drawCTRounded(rect)
        return true
    }
    image.isTemplate = true
    return image
}

private func drawCTRounded(_ rect: NSRect) {
    let stroke: CGFloat = 1.9

    let cPath = NSBezierPath()
    cPath.lineWidth = stroke
    cPath.lineCapStyle = .round
    cPath.appendArc(
        withCenter: CGPoint(x: rect.minX + 6.0, y: rect.midY),
        radius: 4.0,
        startAngle: 40,
        endAngle: 320,
        clockwise: false
    )
    cPath.stroke()

    let top = NSBezierPath(
        roundedRect: NSRect(x: rect.minX + 8.4, y: rect.minY + 11.4, width: 6.3, height: 1.8),
        xRadius: 0.9,
        yRadius: 0.9
    )
    top.fill()

    let stem = NSBezierPath(
        roundedRect: NSRect(x: rect.minX + 10.9, y: rect.minY + 4.1, width: 1.8, height: 9.6),
        xRadius: 0.9,
        yRadius: 0.9
    )
    stem.fill()
}

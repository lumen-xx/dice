import AppKit
import SwiftUI

final class DiceHostingView: NSHostingView<DiceView> {
    private func edges(at point: NSPoint) -> (left: Bool, right: Bool, top: Bool, bottom: Bool) {
        let corner = (point.x < 10 || point.x > bounds.width - 10) && (point.y < 10 || point.y > bounds.height - 10)
        let margin: CGFloat = corner ? 10 : 4
        let low = point.y < margin, high = point.y > bounds.height - margin
        return (point.x < margin, point.x > bounds.width - margin, isFlipped ? low : high, isFlipped ? high : low)
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if bounds.contains(local) {
            let edge = edges(at: local)
            if edge.left || edge.right || edge.top || edge.bottom { return self }
        }
        return super.hitTest(point)
    }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let edge = edges(at: convert(event.locationInWindow, from: nil))
        guard edge.left || edge.right || edge.top || edge.bottom else { super.mouseDown(with: event); return }
        let initial = window.frame, origin = NSEvent.mouseLocation
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            let mouse = NSEvent.mouseLocation, dx = mouse.x - origin.x, dy = mouse.y - origin.y
            var frame = initial
            if edge.left { frame.size.width = max(520, initial.width - dx); frame.origin.x = initial.maxX - frame.width }
            if edge.right { frame.size.width = max(520, initial.width + dx) }
            if edge.bottom { frame.size.height = max(420, initial.height - dy); frame.origin.y = initial.maxY - frame.height }
            if edge.top { frame.size.height = max(420, initial.height + dy) }
            window.setFrame(frame, display: true)
        }
        window.invalidateCursorRects(for: self)
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        let edge: CGFloat = 4, corner: CGFloat = 10
        let w = bounds.width, h = bounds.height
        guard w > corner * 2, h > corner * 2 else { return }
        let top = isFlipped ? CGFloat(0) : h - edge
        let bottom = isFlipped ? h - edge : CGFloat(0)
        addCursorRect(NSRect(x: 0, y: corner, width: edge, height: h - corner * 2), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: w - edge, y: corner, width: edge, height: h - corner * 2), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: corner, y: top, width: w - corner * 2, height: edge), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: corner, y: bottom, width: w - corner * 2, height: edge), cursor: .resizeUpDown)
        let topCorner = isFlipped ? CGFloat(0) : h - corner
        let bottomCorner = isFlipped ? h - corner : CGFloat(0)
        if #available(macOS 15.0, *) {
            addCursorRect(NSRect(x: 0, y: topCorner, width: corner, height: corner), cursor: .frameResize(position: .topLeft, directions: .all))
            addCursorRect(NSRect(x: w - corner, y: topCorner, width: corner, height: corner), cursor: .frameResize(position: .topRight, directions: .all))
            addCursorRect(NSRect(x: 0, y: bottomCorner, width: corner, height: corner), cursor: .frameResize(position: .bottomLeft, directions: .all))
            addCursorRect(NSRect(x: w - corner, y: bottomCorner, width: corner, height: corner), cursor: .frameResize(position: .bottomRight, directions: .all))
        } else {
            let descending = Self.diagonalCursor(reverse: false), ascending = Self.diagonalCursor(reverse: true)
            addCursorRect(NSRect(x: 0, y: topCorner, width: corner, height: corner), cursor: descending)
            addCursorRect(NSRect(x: w - corner, y: bottomCorner, width: corner, height: corner), cursor: descending)
            addCursorRect(NSRect(x: w - corner, y: topCorner, width: corner, height: corner), cursor: ascending)
            addCursorRect(NSRect(x: 0, y: bottomCorner, width: corner, height: corner), cursor: ascending)
        }
    }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        window?.invalidateCursorRects(for: self)
    }
    private static func diagonalCursor(reverse: Bool) -> NSCursor {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let path = NSBezierPath()
            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: reverse ? 18 - y : y) }
            path.move(to: point(3, 3)); path.line(to: point(15, 15))
            path.move(to: point(3, 7)); path.line(to: point(3, 3)); path.line(to: point(7, 3))
            path.move(to: point(11, 15)); path.line(to: point(15, 15)); path.line(to: point(15, 11))
            path.lineCapStyle = .round; path.lineJoinStyle = .round
            NSColor.black.setStroke(); path.lineWidth = 3.5; path.stroke()
            NSColor.white.setStroke(); path.lineWidth = 1.5; path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 9, y: 9))
    }
}

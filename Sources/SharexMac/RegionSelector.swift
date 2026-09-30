import AppKit

final class RegionSelector {
    private var overlays: [OverlayWindow] = []
    private var completion: ((CapturedImage?) -> Void)?

    func begin(snapshots: [ScreenSnapshot], windows: [WindowInfo], completion: @escaping (CapturedImage?) -> Void) {
        self.completion = completion
        for snapshot in snapshots {
            let window = OverlayWindow(screen: snapshot.screen)
            let origin = snapshot.screen.globalFrame.origin
            let windowRects = windows.map { $0.frame.offsetBy(dx: -origin.x, dy: -origin.y) }
            let selectionView = SelectionView(
                frame: CGRect(origin: .zero, size: snapshot.screen.frame.size),
                snapshot: snapshot.image,
                windowRects: windowRects
            )
            selectionView.onFinish = { [weak self] result in self?.finish(result) }
            window.contentView = selectionView
            window.orderFrontRegardless()
            overlays.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        let initial = overlays.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? overlays.first
        initial?.makeKey()
        NSCursor.crosshair.set()
    }

    private func finish(_ result: CapturedImage?) {
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        let completion = completion
        self.completion = nil
        completion?(result)
    }
}

private final class OverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = true
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class SelectionView: NSView {
    var onFinish: ((CapturedImage?) -> Void)?

    private let snapshot: CGImage
    private let snapshotImage: NSImage
    private let windowRects: [CGRect]
    private var mouseLocation: CGPoint?
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?

    private let dragThreshold: CGFloat = 3
    private let magnifierPixelCount = 15
    private let magnifierSize: CGFloat = 120
    private let accentColor = NSColor(calibratedRed: 0.18, green: 0.62, blue: 1, alpha: 1)

    init(frame: CGRect, snapshot: CGImage, windowRects: [CGRect]) {
        self.snapshot = snapshot
        self.snapshotImage = NSImage(cgImage: snapshot, size: frame.size)
        self.windowRects = windowRects
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var pixelScale: CGFloat { CGFloat(snapshot.width) / bounds.width }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect, .cursorUpdate],
            owner: self
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseEntered(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        NSCursor.crosshair.set()
    }

    override func mouseExited(with event: NSEvent) {
        mouseLocation = nil
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        mouseLocation = convert(event.locationInWindow, from: nil)
        NSCursor.crosshair.set()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point
        dragCurrent = point
        mouseLocation = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = clamped(convert(event.locationInWindow, from: nil))
        dragCurrent = point
        mouseLocation = point
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let selection = currentSelection
        dragStart = nil
        dragCurrent = nil
        guard let selection, let image = crop(selection) else {
            needsDisplay = true
            return
        }
        onFinish?(CapturedImage(image: image, scale: pixelScale))
    }

    override func rightMouseDown(with event: NSEvent) {
        if dragStart != nil {
            dragStart = nil
            dragCurrent = nil
            needsDisplay = true
        } else {
            onFinish?(nil)
        }
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 53:
            onFinish?(nil)
        case 36, 76:
            if let image = crop(bounds) {
                onFinish?(CapturedImage(image: image, scale: pixelScale))
            }
        default:
            super.keyDown(with: event)
        }
    }

    private var dragRect: CGRect? {
        guard let dragStart, let dragCurrent else { return nil }
        let rect = CGRect(
            x: min(dragStart.x, dragCurrent.x),
            y: min(dragStart.y, dragCurrent.y),
            width: abs(dragStart.x - dragCurrent.x),
            height: abs(dragStart.y - dragCurrent.y)
        )
        return rect.width >= dragThreshold || rect.height >= dragThreshold ? rect : nil
    }

    private var hoveredWindowRect: CGRect? {
        guard let mouseLocation else { return nil }
        return windowRects
            .first { $0.contains(mouseLocation) }
            .map { $0.intersection(bounds) }
            .flatMap { $0.isNull || $0.isEmpty ? nil : $0 }
    }

    private var currentSelection: CGRect? {
        dragRect ?? hoveredWindowRect
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    private func crop(_ rect: CGRect) -> CGImage? {
        let scale = pixelScale
        let pixelRect = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
            .integral
            .intersection(CGRect(x: 0, y: 0, width: snapshot.width, height: snapshot.height))
        guard !pixelRect.isNull, pixelRect.width >= 1, pixelRect.height >= 1 else { return nil }
        return snapshot.cropping(to: pixelRect)
    }

    override func draw(_ dirtyRect: NSRect) {
        snapshotImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)

        let selection = currentSelection
        let dimPath = NSBezierPath(rect: bounds)
        if let selection {
            dimPath.appendRect(selection)
            dimPath.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.4).setFill()
        dimPath.fill()

        if let mouseLocation, dragRect == nil {
            drawCrosshair(at: mouseLocation)
        }

        if let selection {
            accentColor.setStroke()
            let border = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
            drawSizeLabel(for: selection)
        }

        if let mouseLocation {
            drawMagnifier(at: mouseLocation)
        }
    }

    private func drawCrosshair(at point: CGPoint) {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: bounds.minX, y: point.y + 0.5))
        path.line(to: CGPoint(x: bounds.maxX, y: point.y + 0.5))
        path.move(to: CGPoint(x: point.x + 0.5, y: bounds.minY))
        path.line(to: CGPoint(x: point.x + 0.5, y: bounds.maxY))
        path.lineWidth = 1
        path.setLineDash([4, 4], count: 2, phase: 0)
        NSColor.white.withAlphaComponent(0.6).setStroke()
        path.stroke()
    }

    private func drawSizeLabel(for selection: CGRect) {
        let scale = pixelScale
        let text = "\(Int((selection.width * scale).rounded())) × \(Int((selection.height * scale).rounded()))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let padding = CGSize(width: 6, height: 3)
        var origin = CGPoint(x: selection.minX, y: selection.minY - size.height - padding.height * 2 - 4)
        if origin.y < bounds.minY { origin.y = selection.minY + 4 }
        let background = CGRect(origin: origin, size: CGSize(width: size.width + padding.width * 2, height: size.height + padding.height * 2))
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: background, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(at: CGPoint(x: origin.x + padding.width, y: origin.y + padding.height), withAttributes: attributes)
    }

    private func drawMagnifier(at point: CGPoint) {
        let scale = pixelScale
        let count = magnifierPixelCount
        let centerX = Int(point.x * scale)
        let centerY = Int(point.y * scale)
        let originX = min(max(centerX - count / 2, 0), snapshot.width - count)
        let originY = min(max(centerY - count / 2, 0), snapshot.height - count)
        guard let region = snapshot.cropping(to: CGRect(x: originX, y: originY, width: count, height: count)) else { return }

        let offset: CGFloat = 24
        var frame = CGRect(x: point.x + offset, y: point.y + offset, width: magnifierSize, height: magnifierSize)
        if frame.maxX > bounds.maxX { frame.origin.x = point.x - offset - magnifierSize }
        if frame.maxY + 24 > bounds.maxY { frame.origin.y = point.y - offset - magnifierSize - 24 }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.imageInterpolation = .none
        NSImage(cgImage: region, size: frame.size).draw(in: frame, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()

        let cell = magnifierSize / CGFloat(count)
        let centerCell = CGRect(
            x: frame.minX + CGFloat(centerX - originX) * cell,
            y: frame.minY + CGFloat(centerY - originY) * cell,
            width: cell,
            height: cell
        )
        NSColor.black.setStroke()
        NSBezierPath(rect: centerCell).stroke()
        NSColor.white.setStroke()
        NSBezierPath(rect: frame).stroke()

        let text = "X: \(centerX)  Y: \(centerY)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.white,
        ]
        let labelFrame = CGRect(x: frame.minX, y: frame.maxY, width: frame.width, height: 20)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(rect: labelFrame).fill()
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(
            at: CGPoint(x: labelFrame.midX - size.width / 2, y: labelFrame.midY - size.height / 2),
            withAttributes: attributes
        )
    }
}

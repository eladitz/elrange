// Drag a window to a screen edge or corner and it snaps there, with a preview of where it will land:
// top = maximize, left/right = halves, corners = quarters, bottom edge = thirds (by where along it you are).

import AppKit

@MainActor
final class Snapper {
    static let shared = Snapper()
    private var monitors: [Any] = []
    private var window: Win?
    private var startFrame: CGRect?
    private var dragging = false
    private var zone: (action: Action, screen: NSScreen)?
    private let footprint = Footprint()

    func start() {
        guard monitors.isEmpty else { return }
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { _ in MainActor.assumeIsolated { Snapper.shared.down() } },
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { _ in MainActor.assumeIsolated { Snapper.shared.drag() } },
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in MainActor.assumeIsolated { Snapper.shared.up() } },
        ].compactMap { $0 }
    }

    private func down() {
        reset()
        guard Prefs.shared.snapping, AX.trusted, let w = AX.window(at: Screen.axPoint(NSEvent.mouseLocation)), !Prefs.shared.isIgnored(w) else { return }
        window = w
        startFrame = w.currentFrame
    }

    private func drag() {
        guard let w = window, let start = startFrame else { return }
        if !dragging {
            // It's a window drag once the window has moved without changing size (not a resize, not a text selection).
            let now = w.currentFrame
            guard now.origin != start.origin, abs(now.width - start.width) < 1, abs(now.height - start.height) < 1 else { return }
            dragging = true
            Manager.shared.unsnap(w, pointer: Screen.axPoint(NSEvent.mouseLocation))
            Manager.shared.remember(w)
        }
        let found = Self.zone(at: NSEvent.mouseLocation)
        if found?.action != zone?.action || found?.screen != zone?.screen {
            zone = found
            if let found, let frame = Self.frame(found.action, on: found.screen, window: w.currentFrame) {
                footprint.show(Screen.cocoa(frame))
            } else {
                footprint.hide()
            }
        }
    }

    private func up() {
        defer { reset() }
        guard dragging, let w = window, let zone, let frame = Self.frame(zone.action, on: zone.screen, window: w.currentFrame) else { return }
        // Let the app finish its own drag first, or it puts the window back where the pointer left it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { Manager.shared.place(w, frame) }
    }

    private func reset() {
        window = nil
        startFrame = nil
        dragging = false
        zone = nil
        footprint.hide()
    }

    private static func frame(_ action: Action, on screen: NSScreen, window: CGRect) -> CGRect? {
        let usable = Screen.usable(screen)
        return action.frame(in: usable, window: window, cycle: 0)?.gapped(Prefs.shared.gap, in: usable)
    }

    /// The snap area under the pointer (AppKit coordinates), if any.
    static func zone(at p: CGPoint) -> (action: Action, screen: NSScreen)? {
        guard let screen = NSScreen.screens.first(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(p) }) else { return nil }
        let f = screen.frame
        let edge: CGFloat = 6, corner: CGFloat = 40
        let left = p.x - f.minX < edge, right = f.maxX - p.x < edge
        let top = f.maxY - p.y < edge, bottom = p.y - f.minY < edge
        let nearLeft = p.x - f.minX < corner, nearRight = f.maxX - p.x < corner
        let nearTop = f.maxY - p.y < corner, nearBottom = p.y - f.minY < corner
        if (left && nearTop) || (top && nearLeft) { return (.topLeft, screen) }
        if (right && nearTop) || (top && nearRight) { return (.topRight, screen) }
        if (left && nearBottom) || (bottom && nearLeft) { return (.bottomLeft, screen) }
        if (right && nearBottom) || (bottom && nearRight) { return (.bottomRight, screen) }
        if left { return (.leftHalf, screen) }
        if right { return (.rightHalf, screen) }
        if top { return (.maximize, screen) }
        if bottom {
            let third = (p.x - f.minX) / f.width
            return (third < 1.0 / 3 ? .firstThird : third < 2.0 / 3 ? .centerThird : .lastThird, screen)
        }
        return nil
    }
}

/// The translucent rectangle that shows where a dragged window will land.
final class Footprint {
    private let panel: NSPanel

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.state = .active
        view.blendingMode = .behindWindow
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.borderWidth = 2
        view.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
        view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
        panel.contentView = view
    }

    func show(_ rect: CGRect) {
        let r = rect.insetBy(dx: 4, dy: 4)
        if panel.isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().setFrame(r, display: true)
            }
        } else {
            panel.setFrame(r, display: true)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }
}

/// A short message near the bottom of the screen ("Marked 2 — Safari"), gone after a moment.
@MainActor
enum HUD {
    private static var panel: NSPanel?
    private static var hideTask: DispatchWorkItem?

    static func show(_ title: String, _ text: String, detail: String?) {
        let panel = self.panel ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.ignoresMouseEvents = true
            p.level = .statusBar
            p.collectionBehavior = [.canJoinAllSpaces, .transient]
            self.panel = p
            return p
        }()
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 3
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 18, bottom: 12, right: 18)
        let head = NSTextField(labelWithString: title)
        head.font = .systemFont(ofSize: 15, weight: .semibold)
        stack.addArrangedSubview(head)
        for line in [text, detail ?? ""] where !line.isEmpty {
            let label = NSTextField(labelWithString: line)
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingMiddle
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 420).isActive = true
            stack.addArrangedSubview(label)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor), stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
                                     stack.topAnchor.constraint(equalTo: effect.topAnchor), stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor)])
        panel.contentView = effect
        let size = stack.fittingSize
        let screen = Tour.active ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main!
        panel.setFrame(NSRect(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.minY + 90, width: size.width, height: size.height), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        hideTask?.cancel()
        let task = DispatchWorkItem { panel.animator().alphaValue = 0 }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: task)
    }
}

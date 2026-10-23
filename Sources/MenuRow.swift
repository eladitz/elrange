// The menu's rows: a picture of where the window goes, the action's name, and its shortcut, which you
// can click to change. Clicking anywhere else on the row runs the action, like a normal menu item.

import AppKit

/// Small template pictures of each action, drawn from the same geometry the actions use.
@MainActor
enum ActionIcon {
    private static var cache: [Action: NSImage] = [:]

    static func image(_ action: Action) -> NSImage {
        if let cached = cache[action] { return cached }
        let image = symbol(action) ?? drawn(action)
        image.isTemplate = true
        cache[action] = image
        return image
    }

    private static func symbol(_ action: Action) -> NSImage? {
        let name: String? = switch action {
        case .restore: "arrow.uturn.backward.square"
        case .nextDisplay: "arrow.right.square"
        case .previousDisplay: "arrow.left.square"
        case .smaller: "arrow.down.right.and.arrow.up.left.square"
        case .larger: "arrow.up.left.and.arrow.down.right.square"
        case .markWindow: "checkmark.square"
        case .arrangeMarked: "square.grid.2x2"
        case .clearMarks: "xmark.square"
        default: nil
        }
        return name.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: action.title)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular)) }
    }

    /// A screen outline with the window's new place filled in.
    private static func drawn(_ action: Action) -> NSImage {
        let size = NSSize(width: 20, height: 14)
        return NSImage(size: size, flipped: true) { _ in
            let screen = CGRect(x: 1, y: 1.5, width: 18, height: 11)
            NSColor.black.setStroke()
            let outline = NSBezierPath(roundedRect: screen, xRadius: 2, yRadius: 2)
            outline.lineWidth = 1.1
            outline.stroke()
            let inner = screen.insetBy(dx: 2, dy: 2)
            let sample = CGRect(x: inner.minX + inner.width * 0.3, y: inner.minY + inner.height * 0.3, width: inner.width * 0.4, height: inner.height * 0.4)
            func fill(_ r: CGRect, alpha: CGFloat = 1) {
                NSColor.black.withAlphaComponent(alpha).setFill()
                NSBezierPath(roundedRect: r, xRadius: 0.8, yRadius: 0.8).fill()
            }
            switch action {
            case .cascade, .sideBySide, .stacked:
                let layout: Layout = action == .cascade ? .cascade : action == .sideBySide ? .columns : .rows
                // At icon size the real cascade step is under a point, so draw a bolder staircase.
                let frames = layout == .cascade
                    ? (0..<3).map { k in CGRect(x: inner.minX + CGFloat(2 - k) * 2.6, y: inner.minY + CGFloat(2 - k) * 1.6,
                                                width: inner.width * 0.62, height: inner.height * 0.6) }
                    : layout.frames(3, in: inner)
                for (i, f) in frames.enumerated().reversed() {
                    guard layout == .cascade else { fill(f.insetBy(dx: 0.5, dy: 0.5), alpha: i == 0 ? 1 : 0.45); continue }
                    // A staircase: each window clears what's behind it; the back ones are outlines, the front is solid.
                    let r = f.insetBy(dx: 0.5, dy: 0.5)
                    NSGraphicsContext.current?.compositingOperation = .clear
                    NSBezierPath(rect: r.insetBy(dx: -0.8, dy: -0.8)).fill()
                    NSGraphicsContext.current?.compositingOperation = .sourceOver
                    if i == 0 { fill(r) } else {
                        NSColor.black.setStroke()
                        let outline = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 0.8, yRadius: 0.8)
                        outline.lineWidth = 1
                        outline.stroke()
                    }
                }
            default:
                if let f = action.frame(in: inner, window: sample, cycle: 0) { fill(f.insetBy(dx: 0.25, dy: 0.25)) }
            }
            return true
        }
    }
}

/// One row of Elrange's menu.
final class MenuRow: NSView {
    private let action: Action
    private let run: (Action) -> Void
    private let change: (Action) -> Void
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let shortcut = NSTextField(labelWithString: "")
    private let hasShortcut: Bool

    init(_ action: Action, title text: String, shortcut keys: Shortcut?, run: @escaping (Action) -> Void, change: @escaping (Action) -> Void) {
        self.action = action
        self.run = run
        self.change = change
        hasShortcut = keys != nil
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        icon.image = MainActor.assumeIsolated { ActionIcon.image(action) }
        icon.imageScaling = .scaleProportionallyDown
        title.stringValue = text
        title.font = .menuFont(ofSize: 0)
        shortcut.stringValue = keys?.display ?? "Set shortcut"
        shortcut.font = .menuFont(ofSize: 0)
        shortcut.alignment = .right
        shortcut.toolTip = "Click to change this shortcut"
        for v in [icon, title, shortcut] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 16),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            shortcut.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 24),
            shortcut.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            shortcut.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 24),
        ])
        autoresizingMask = [.width]
    }

    required init?(coder: NSCoder) { fatalError() }

    private var highlighted: Bool { enclosingMenuItem?.isHighlighted ?? false }

    override func viewWillDraw() {
        super.viewWillDraw()
        let on = highlighted
        title.textColor = on ? .selectedMenuItemTextColor : .labelColor
        icon.contentTintColor = on ? .selectedMenuItemTextColor : .labelColor
        // Rows without a shortcut only show "Set shortcut" while you point at them.
        shortcut.textColor = on ? .selectedMenuItemTextColor.withAlphaComponent(hasShortcut ? 0.85 : 0.7) : .tertiaryLabelColor
        shortcut.isHidden = !hasShortcut && !on
    }

    override func draw(_ dirtyRect: NSRect) {
        guard highlighted else { return }
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 0), xRadius: 5, yRadius: 5).fill()
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let onShortcut = point.x > shortcut.frame.minX - 8
        enclosingMenuItem?.menu?.cancelTracking()
        // After the menu has closed, so the other app is in front again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [action, run, change] in
            if onShortcut { change(action) } else { run(action) }
        }
    }
}

/// "Press the new shortcut for Left Half": a small floating box opened from a row's shortcut.
@MainActor
final class ShortcutPanel {
    static let shared = ShortcutPanel()
    private var panel: NSPanel?
    private var monitor: Any?
    private var action: Action?
    private let hint = NSTextField(labelWithString: "")
    private let keys = NSTextField(labelWithString: "")
    var onChange: (() -> Void)?

    func open(_ action: Action) {
        self.action = action
        Hotkeys.shared.unregister()   // so pressing a taken shortcut records it instead of running it
        let panel = self.panel ?? build()
        self.panel = panel
        panel.title = "Shortcut for \(action.title)"
        hint.stringValue = "Press the new keys (with ⌃, ⌥, ⌘ or ⇧). Esc cancels."
        keys.stringValue = Hotkeys.shared.shortcuts[action]?.display ?? "None"
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel?.isKeyWindow == true else { return event }
            self.key(event)
            return nil
        }
    }

    private func build() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 150), styleMask: [.titled, .closable, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        keys.font = .systemFont(ofSize: 26, weight: .medium)
        keys.alignment = .center
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center
        let remove = NSButton(title: "Remove", target: self, action: #selector(removeShortcut))
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(close))
        let buttons = NSStackView(views: [remove, cancel])
        let stack = NSStackView(views: [keys, hint, buttons])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        panel.contentView = stack
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { _ in
            MainActor.assumeIsolated { ShortcutPanel.shared.finish() }
        }
        return panel
    }

    private func key(_ event: NSEvent) {
        guard let action else { return }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.keyCode == 53 { return close() }   // Esc
        let functionKey = (96...122).contains(Int(event.keyCode))
        guard !flags.isEmpty || functionKey else { NSSound.beep(); return }
        let shortcut = Shortcut(keyCode: UInt32(event.keyCode), flags: flags)
        keys.stringValue = shortcut.display
        Hotkeys.shared.set(shortcut, for: action)
        HUD.show(action.title, "is now \(shortcut.display)", detail: nil)
        close()
    }

    @objc private func removeShortcut() {
        if let action { Hotkeys.shared.set(nil, for: action) }
        close()
    }

    @objc private func close() { panel?.close() }

    private func finish() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        action = nil
        Hotkeys.shared.register()
        onChange?()
    }
}

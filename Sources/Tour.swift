// `--tour`: Elrange uses itself, step by step at a watchable pace, for the screen recording App Review asks
// new developers for. It makes three demo windows of its own (so none of yours are moved or shown), runs
// its real commands on them with a caption for each, on a plain backdrop, then quits.

import AppKit

@MainActor
enum Tour {
    /// The display with the menu bar: the one the recording is made of (not "the main screen", which is
    /// whichever screen the active window happens to be on).
    static var screen: NSScreen { NSScreen.screens.first! }
    /// Set while a tour runs; popups that follow the pointer's screen (captions, the switcher) use this one.
    nonisolated(unsafe) static var active: NSScreen?

    private static var keep: [NSWindow] = []

    static func run() {
        AX.onlySelf = true
        active = screen
        stage()
        let demos = [("Notes", NSColor.systemYellow), ("Photos", NSColor.systemPink), ("Music", NSColor.systemPurple)].enumerated().map { i, entry in
            window(entry.0, entry.1, at: NSPoint(x: 260 + i * 140, y: 260 + i * 70))
        }
        Task {
            func pause(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
            @MainActor func say(_ title: String, _ text: String) { HUD.show(title, text, detail: nil) }
            await pause(1.5)
            // The demo windows, through Accessibility like any app's, and the actions applied to them directly
            // (never "the window in front", which could be one of yours).
            let wins = AX.all().filter { w in demos.contains { $0.title == w.title } }
                .sorted { a, b in demos.firstIndex { $0.title == a.title }! < demos.firstIndex { $0.title == b.title }! }
            guard wins.count == demos.count, let first = wins.first else { NSApp.terminate(nil); return }
            demos[0].orderFrontRegardless()
            let usable = Screen.usable(Tour.screen)
            let start = first.currentFrame
            await pause(0.8)
            for (action, keys) in [(Action.leftHalf, "⌃⌥←"), (.rightHalf, "⌃⌥→"), (.topLeft, "⌃⌥U"), (.maximize, "⌃⌥↩"), (.center, "⌃⌥C"), (.restore, "⌃⌥⌫")] {
                say(action.title, keys)
                if action == .restore {
                    Manager.shared.place(first, start)
                } else if let frame = action.frame(in: usable, window: first.currentFrame, cycle: 0) {
                    Manager.shared.place(first, action.tiles ? frame.gapped(Prefs.shared.gap, in: usable) : frame)
                }
                await pause(1.6)
            }
            for layout in [Layout.cascade, .columns, .mainSide] {
                say(layout.title, layout.hint)
                Manager.shared.arrange(wins, layout, on: Tour.screen)
                await pause(2.2)
            }
            say("Arrange Windows…", "Mark windows, put them in order, pick a screen and a layout")
            Manager.shared.setMarked(wins)
            AppDelegate.shared?.openArrange(nil)
            if let arrange = NSApp.windows.first(where: { $0.title == "Arrange Windows" }) {
                let v = screen.visibleFrame, size = arrange.frame.size
                arrange.setFrameOrigin(NSPoint(x: v.midX - size.width / 2, y: v.midY - size.height / 2))
                arrange.orderFrontRegardless()
            }
            await pause(3.5)
            NSApp.windows.first { $0.title == "Arrange Windows" }?.close()
            say("Hold ⌃⌥ and scroll", "Flip through every open window")
            Switcher.shared.tourOpen()
            for _ in 0..<3 { await pause(0.9); Switcher.shared.tourStep() }
            await pause(0.9)
            Switcher.shared.tourPick()
            await pause(2)
            NSApp.terminate(nil)
        }
    }

    private static func window(_ title: String, _ color: NSColor, at origin: NSPoint) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(origin: origin, size: NSSize(width: 620, height: 400)),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = title
        w.isReleasedWhenClosed = false
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = color.withAlphaComponent(0.85).cgColor
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 44, weight: .bold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: view.centerXAnchor), label.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
        w.contentView = view
        w.level = .normal
        w.orderFrontRegardless()
        keep.append(w)
        return w
    }

    /// A plain dark backdrop over the main screen, behind the demo windows.
    private static func stage() {
        let screen = Tour.screen
        let w = NSWindow(contentRect: screen.visibleFrame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.backgroundColor = NSColor(srgbRed: 0.09, green: 0.10, blue: 0.14, alpha: 1)
        w.isReleasedWhenClosed = false
        w.ignoresMouseEvents = true
        w.level = .normal
        w.orderFrontRegardless()
        keep.append(w)
        NSApp.activate(ignoringOtherApps: true)
    }
}

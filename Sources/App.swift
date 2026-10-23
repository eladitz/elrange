// Elrange: arrange windows from the keyboard, by dragging, or Windows-style (cascade, side by side,
// marked windows in priority order on the screen you pick). Lives in the menu bar.

import SwiftUI

@MainActor
enum Windows {
    private static var open: [NSWindow] = []

    @discardableResult
    static func show<V: View>(_ title: String, size: NSSize, _ view: V) -> NSWindow {
        if let existing = open.first(where: { $0.title == title }) {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return existing
        }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.setContentSize(size)
        window.center()
        open.append(window)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { note in
            MainActor.assumeIsolated { open.removeAll { $0 === note.object as? NSWindow } }
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return window
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static weak var shared: AppDelegate?
    private var item: NSStatusItem!
    private var permissionTimer: Timer?
    private var settings: SettingsModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.split.2x2", accessibilityDescription: "Elrange")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu

        Hotkeys.shared.perform = { action in
            Manager.shared.perform(action)
            Donation.recordUse()
        }
        Hotkeys.shared.register()
        Donation.usageLine = { "You've arranged windows with it \($0) times so far." }
        Donation.start()
        Updater.start()

        // Development aid: `--self-test` prints where actions and layouts put windows on a 1000×800 screen.
        if CommandLine.arguments.contains("--self-test") {
            let screen = CGRect(x: 0, y: 25, width: 1000, height: 800), window = CGRect(x: 100, y: 100, width: 400, height: 300)
            for action in Action.allCases {
                if let f = action.frame(in: screen, window: window, cycle: 0) { print(action.rawValue, f.integral) }
            }
            for c in 1...3 { print("leftHalf cycle", c, Action.leftHalf.frame(in: screen, window: window, cycle: c)!.integral) }
            for layout in Layout.allCases { print(layout.rawValue, layout.frames(4, in: screen).map(\.integral)) }
            print("gapped 10", Action.leftHalf.frame(in: screen, window: window, cycle: 0)!.gapped(10, in: screen),
                  Action.rightHalf.frame(in: screen, window: window, cycle: 0)!.gapped(10, in: screen))
            exit(0)
        }
        // Development aid: `--snapshot out.png settings|arrange|welcome` opens that window, captures it and quits.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 2 < args.count {
            switch args[i + 2] {
            case "settings": openSettings(nil)
            case "arrange": openArrange(nil)
            default: Windows.show("Welcome to Elrange", size: NSSize(width: 520, height: 330), PermissionView())
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                // screencapture can't grab a menu bar app's windows, so the window draws itself.
                let titles = ["Arrange Windows", "Elrange Settings", "Welcome to Elrange"]
                if let frame = NSApp.windows.first(where: { $0.isVisible && titles.contains($0.title) })?.contentView?.superview,
                   let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) {
                    frame.cacheDisplay(in: frame.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
                }
                exit(0)
            }
            return
        }
        if AX.trusted { Snapper.shared.start() } else { showPermission() }
    }

    // MARK: Permission

    func showPermission() {
        Windows.show("Welcome to Elrange", size: NSSize(width: 520, height: 330), PermissionView())
        AX.askForTrust()
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            MainActor.assumeIsolated {
                guard AX.trusted else { return }
                timer.invalidate()
                NSApp.windows.first { $0.title == "Welcome to Elrange" }?.close()
                Snapper.shared.start()
                HUD.show("Elrange is ready", "Try ⌃⌥← and ⌃⌥→, or drag a window to a screen edge", detail: nil)
            }
        }
    }

    // MARK: Menu

    func rebuildMenu() { if let menu = item.menu { menuNeedsUpdate(menu) } }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let shortcuts = Hotkeys.shared.shortcuts

        func actionItem(_ action: Action, title: String? = nil) -> NSMenuItem {
            let i = NSMenuItem(title: title ?? action.title, action: #selector(run(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = action.rawValue
            if let s = shortcuts[action], let key = Self.keyEquivalent(s.keyCode) {
                i.keyEquivalent = key
                i.keyEquivalentModifierMask = s.flags
            }
            return i
        }
        func submenu(_ title: String, _ actions: [Action]) -> NSMenuItem {
            let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let sub = NSMenu()
            actions.forEach { sub.addItem(actionItem($0)) }
            parent.submenu = sub
            return parent
        }

        if !AX.trusted {
            let warn = NSMenuItem(title: "Allow Elrange to Move Windows…", action: #selector(permission(_:)), keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
            menu.addItem(.separator())
        }
        for (name, actions) in Action.groups {
            switch name {
            case "Fourths", "Sixths", "Move": menu.addItem(submenu(name, actions))
            case "Arrange":
                menu.addItem(.separator())
                actions.forEach { menu.addItem(actionItem($0)) }
                let arrange = NSMenuItem(title: "Arrange Windows…", action: #selector(openArrange(_:)), keyEquivalent: "")
                arrange.target = self
                menu.addItem(arrange)
            case "Marks":
                let count = Manager.shared.marked.count
                menu.addItem(actionItem(.markWindow))
                menu.addItem(actionItem(.arrangeMarked, title: count > 0 ? "Arrange \(count) Marked (\(Prefs.shared.lastLayout.title))" : "Arrange Marked Windows"))
                if count > 0 { menu.addItem(actionItem(.clearMarks)) }
            default:
                menu.addItem(.separator())
                actions.forEach { menu.addItem(actionItem($0)) }
            }
        }

        // Saved arrangements.
        menu.addItem(.separator())
        let saved = NSMenuItem(title: "Arrangements", action: nil, keyEquivalent: "")
        let savedMenu = NSMenu()
        for arrangement in Manager.shared.arrangements {
            let i = savedMenu.addItem(withTitle: arrangement.name, action: #selector(restoreArrangement(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = arrangement.name
        }
        if !Manager.shared.arrangements.isEmpty { savedMenu.addItem(.separator()) }
        let save = savedMenu.addItem(withTitle: "Save Current Arrangement…", action: #selector(saveArrangement(_:)), keyEquivalent: "")
        save.target = self
        if !Manager.shared.arrangements.isEmpty {
            let delete = NSMenuItem(title: "Delete", action: nil, keyEquivalent: "")
            let deleteMenu = NSMenu()
            for arrangement in Manager.shared.arrangements {
                let i = deleteMenu.addItem(withTitle: arrangement.name, action: #selector(deleteArrangement(_:)), keyEquivalent: "")
                i.target = self
                i.representedObject = arrangement.name
            }
            delete.submenu = deleteMenu
            savedMenu.addItem(delete)
        }
        saved.submenu = savedMenu
        menu.addItem(saved)

        // Leave the app in front alone.
        if let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier {
            let ignoring = Prefs.shared.ignored.contains(id)
            let i = menu.addItem(withTitle: "Ignore \(app.localizedName ?? "This App")", action: #selector(toggleIgnore(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = id
            i.state = ignoring ? .on : .off
        }

        menu.addItem(.separator())
        let settings = menu.addItem(withTitle: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settings.target = self
        let updates = menu.addItem(withTitle: "Check for Updates…", action: #selector(checkUpdates(_:)), keyEquivalent: "")
        updates.target = self
        let kofi = menu.addItem(withTitle: "Support Elrange on Ko-fi…", action: #selector(donate(_:)), keyEquivalent: "")
        kofi.target = self
        menu.addItem(withTitle: "Quit Elrange", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    /// The character a menu shows for a key (menus need one; the shortcut itself is the global hotkey).
    private static func keyEquivalent(_ code: UInt32) -> String? {
        switch code {
        case 123: return String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        case 124: return String(UnicodeScalar(NSRightArrowFunctionKey)!)
        case 125: return String(UnicodeScalar(NSDownArrowFunctionKey)!)
        case 126: return String(UnicodeScalar(NSUpArrowFunctionKey)!)
        case 36: return "\r"
        case 51: return "\u{8}"
        default:
            let name = Shortcut.keyName(code)
            return name.count == 1 ? name.lowercased() : nil
        }
    }

    @objc private func run(_ sender: NSMenuItem) {
        guard let action = (sender.representedObject as? String).flatMap(Action.init(rawValue:)) else { return }
        // Let the menu close and the other app come back to the front first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            Manager.shared.perform(action)
            Donation.recordUse()
        }
    }

    @objc private func permission(_ sender: Any?) { showPermission() }

    @objc func openArrange(_ sender: Any?) {
        let model = ArrangeModel()
        model.window = Windows.show("Arrange Windows", size: NSSize(width: 820, height: 560), ArrangeView(model: model))
    }

    @objc private func restoreArrangement(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let a = Manager.shared.arrangements.first(where: { $0.name == name }) else { return }
        Manager.shared.restore(a)
    }

    @objc private func saveArrangement(_ sender: Any?) { ArrangeModel().saveArrangement() }

    @objc private func deleteArrangement(_ sender: NSMenuItem) {
        if let name = sender.representedObject as? String { Manager.shared.deleteArrangement(name) }
    }

    @objc private func toggleIgnore(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        if Prefs.shared.ignored.contains(id) { Prefs.shared.ignored.removeAll { $0 == id } } else { Prefs.shared.ignored.append(id) }
    }

    @objc func openSettings(_ sender: Any?) {
        let model = settings ?? SettingsModel()
        settings = model
        Windows.show("Elrange Settings", size: NSSize(width: 560, height: 620), SettingsView(model: model))
    }

    @objc private func checkUpdates(_ sender: Any?) { Task { await Updater.check(manual: true) } }
    @objc private func donate(_ sender: Any?) { NSWorkspace.shared.open(Donation.page) }
}

struct PermissionView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("One permission, once").font(.title2.weight(.semibold))
                    Text("To move other apps' windows, macOS needs you to allow Elrange under Accessibility.").foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Label("Click Open Settings and switch Elrange on.", systemImage: "1.circle")
                Label("This window closes by itself when it's done.", systemImage: "2.circle")
                Label("Already on, but still asking? Switch it off and on again (needed after an update).", systemImage: "arrow.triangle.2.circlepath")
            }
            .font(.callout)
            Spacer()
            HStack {
                Text("Elrange only moves and sizes windows. It doesn't read what's in them.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Open Settings") {
                    AX.askForTrust()
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
}

@main
enum Entry {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

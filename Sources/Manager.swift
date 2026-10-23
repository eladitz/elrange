// Carries out actions: one window (halves, thirds, displays…), many (cascade, layouts), marks and saved
// arrangements. Remembers each window's frame from before Elrange first moved it, for Restore.

import AppKit
import ServiceManagement

@MainActor
final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    @Published var gap: Double { didSet { d.set(gap, forKey: "gap") } }
    @Published var snapping: Bool { didSet { d.set(snapping, forKey: "snapping") } }
    @Published var cycle: Bool { didSet { d.set(cycle, forKey: "cycle") } }
    @Published var restoreOnDragAway: Bool { didSet { d.set(restoreOnDragAway, forKey: "restoreOnDragAway") } }
    @Published var ignored: [String] { didSet { d.set(ignored, forKey: "ignored") } }   // bundle ids
    @Published var lastLayout: Layout { didSet { d.set(lastLayout.rawValue, forKey: "lastLayout") } }
    @Published var lastScreen: String { didSet { d.set(lastScreen, forKey: "lastScreen") } }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set { try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister(); objectWillChange.send() }
    }

    private init() {
        gap = d.object(forKey: "gap") as? Double ?? 0
        snapping = d.object(forKey: "snapping") as? Bool ?? true
        cycle = d.object(forKey: "cycle") as? Bool ?? true
        restoreOnDragAway = d.object(forKey: "restoreOnDragAway") as? Bool ?? true
        ignored = d.stringArray(forKey: "ignored") ?? []
        lastLayout = Layout(rawValue: d.string(forKey: "lastLayout") ?? "") ?? .columns
        lastScreen = d.string(forKey: "lastScreen") ?? ""
    }

    func isIgnored(_ w: Win) -> Bool { w.bundleID.map(ignored.contains) ?? false }
}

/// A saved setup: which app's window goes where, on which screen.
struct Arrangement: Codable, Identifiable {
    struct Entry: Codable {
        var bundleID: String
        var title: String
        var screen: String
        var fraction: CGRect   // of the screen's usable area
    }
    var name: String
    var entries: [Entry]
    var id: String { name }
}

@MainActor
final class Manager: ObservableObject {
    static let shared = Manager()
    private let prefs = Prefs.shared

    /// Marked windows, in priority order (first marked = number 1).
    @Published private(set) var marked: [Win] = []
    @Published var arrangements: [Arrangement] = []

    private var original: [String: CGRect] = [:]   // window id → frame before Elrange moved it
    private var snapped: Set<String> = []          // windows Elrange placed, for "restore when dragged away"
    private var last: (action: Action, window: String, frame: CGRect, at: Date, count: Int)?

    private init() {
        if let data = UserDefaults.standard.data(forKey: "arrangements"),
           let saved = try? JSONDecoder().decode([Arrangement].self, from: data) { arrangements = saved }
    }

    // MARK: One window

    func perform(_ action: Action) {
        switch action {
        case .cascade: return arrange(windowsOnActiveScreen(), .cascade, on: activeScreen)
        case .sideBySide: return arrange(windowsOnActiveScreen(), .columns, on: activeScreen)
        case .stacked: return arrange(windowsOnActiveScreen(), .rows, on: activeScreen)
        case .markWindow: return toggleMark()
        case .arrangeMarked: return arrangeMarked()
        case .clearMarks: return clearMarks()
        default: break
        }
        guard AX.trusted else { return AppDelegate.shared?.showPermission() ?? () }
        guard let w = AX.focused(), !prefs.isIgnored(w) else { return NSSound.beep() }
        let current = w.currentFrame

        switch action {
        case .restore:
            guard let frame = original[w.id] else { return NSSound.beep() }
            w.setFrame(frame)
            original[w.id] = nil
            snapped.remove(w.id)
            last = nil
            return
        case .nextDisplay, .previousDisplay:
            let screens = NSScreen.screens.sorted { $0.frame.minX < $1.frame.minX }
            guard screens.count > 1, let i = screens.firstIndex(of: w.screen) else { return NSSound.beep() }
            let target = screens[(i + (action == .nextDisplay ? 1 : screens.count - 1)) % screens.count]
            move(w, from: w.screen, to: target)
            return
        default: break
        }

        // Pressed again on the same window, soon after, and it hasn't been moved since: cycle.
        var count = 0
        if prefs.cycle, let last, last.action == action, last.window == w.id, Date().timeIntervalSince(last.at) < 2.5,
           last.frame.distance(to: current) < 4 {
            count = last.count + 1
        }
        let usable = Screen.usable(w.screen)
        guard var frame = action.frame(in: usable, window: current, cycle: count) else { return }
        if action.tiles { frame = frame.gapped(prefs.gap, in: usable) }
        place(w, frame)
        last = (action, w.id, w.currentFrame, Date(), count)
    }

    /// Moves a window, remembering where it was first.
    func place(_ w: Win, _ frame: CGRect) {
        if original[w.id] == nil { original[w.id] = w.currentFrame }
        w.setFrame(frame.integral)
        snapped.insert(w.id)
    }

    /// Same place and proportions on another screen.
    private func move(_ w: Win, from: NSScreen, to: NSScreen) {
        let a = Screen.usable(from), b = Screen.usable(to), f = w.currentFrame
        let rect = CGRect(x: b.minX + (f.minX - a.minX) / a.width * b.width, y: b.minY + (f.minY - a.minY) / a.height * b.height,
                          width: f.width / a.width * b.width, height: f.height / a.height * b.height)
        place(w, rect.fitted(in: b))
    }

    /// Dragging a window Elrange snapped: give it back its size from before, keeping it under the pointer.
    func unsnap(_ w: Win, pointer: CGPoint) {
        guard prefs.restoreOnDragAway, snapped.contains(w.id), let before = original[w.id] else { return }
        snapped.remove(w.id)
        original[w.id] = nil
        let f = w.currentFrame
        let ratio = (pointer.x - f.minX) / max(f.width, 1)
        w.setFrame(CGRect(x: pointer.x - before.width * ratio, y: f.minY, width: before.width, height: before.height))
    }

    func remember(_ w: Win) { if original[w.id] == nil { original[w.id] = w.currentFrame } }

    // MARK: Many windows

    /// The screen with the window you're working in (or the pointer).
    var activeScreen: NSScreen {
        AX.focused()?.screen ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main!
    }

    func windowsOnActiveScreen() -> [Win] {
        let screen = activeScreen
        return AX.all().filter { $0.screen == screen && !prefs.isIgnored($0) }
    }

    /// Puts `windows` (priority order) on `screen` in `layout`, then raises them so number 1 ends on top.
    func arrange(_ windows: [Win], _ layout: Layout, on screen: NSScreen) {
        guard AX.trusted else { return AppDelegate.shared?.showPermission() ?? () }
        guard !windows.isEmpty else { return NSSound.beep() }
        let usable = Screen.usable(screen)
        let frames = layout.frames(windows.count, in: usable)
        for (w, frame) in zip(windows, frames) {
            place(w, layout.tiles ? frame.gapped(prefs.gap, in: usable) : frame)
        }
        for w in windows.reversed() { w.raise() }
        prefs.lastLayout = layout
        prefs.lastScreen = Screen.id(screen)
    }

    // MARK: Marks

    func toggleMark() {
        guard let w = AX.focused() else { return NSSound.beep() }
        if let i = marked.firstIndex(where: { $0.same(as: w) }) {
            marked.remove(at: i)
            HUD.show("Unmarked", w.label, detail: marked.isEmpty ? nil : "\(marked.count) marked")
        } else {
            marked.append(w)
            HUD.show("Marked \(marked.count)", w.label, detail: "⌃⌥A arranges them; ⌃⌥M on another window to add it")
        }
    }

    func setMarked(_ windows: [Win]) { marked = windows }

    func moveMark(from: IndexSet, to: Int) { marked.move(fromOffsets: from, toOffset: to) }

    func clearMarks() {
        marked = []
        HUD.show("Marks cleared", "", detail: nil)
    }

    func isMarked(_ w: Win) -> Bool { marked.contains { $0.same(as: w) } }

    /// Marked windows that still exist, in priority order.
    func liveMarked() -> [Win] {
        let live = AX.all()
        marked = marked.compactMap { m in live.first { $0.same(as: m) } }
        return marked
    }

    func arrangeMarked() {
        let windows = liveMarked()
        guard !windows.isEmpty else {
            HUD.show("No windows marked", "Press ⌃⌥M on each window you want, or open Arrange Windows…", detail: nil)
            return
        }
        arrange(windows, prefs.lastLayout, on: Screen.named(prefs.lastScreen) ?? activeScreen)
    }

    // MARK: Saved arrangements

    /// Saves where every window on every screen is now.
    func saveArrangement(_ name: String, windows: [Win]? = nil) {
        let entries = (windows ?? AX.all()).compactMap { w -> Arrangement.Entry? in
            guard let bundle = w.bundleID else { return nil }
            let screen = w.screen, s = Screen.usable(screen), f = w.currentFrame
            return .init(bundleID: bundle, title: w.title, screen: Screen.id(screen),
                         fraction: CGRect(x: (f.minX - s.minX) / s.width, y: (f.minY - s.minY) / s.height,
                                          width: f.width / s.width, height: f.height / s.height))
        }
        arrangements.removeAll { $0.name == name }
        arrangements.append(Arrangement(name: name, entries: entries))
        storeArrangements()
        HUD.show("Saved “\(name)”", "\(entries.count) windows", detail: nil)
    }

    /// Puts each saved window back: matched by app and title, else the app's next unused window.
    func restore(_ arrangement: Arrangement) {
        guard AX.trusted else { return AppDelegate.shared?.showPermission() ?? () }
        var pool = AX.all()
        var placed: [Win] = []
        for entry in arrangement.entries {
            guard let i = pool.firstIndex(where: { $0.bundleID == entry.bundleID && $0.title == entry.title })
                    ?? pool.firstIndex(where: { $0.bundleID == entry.bundleID }) else { continue }
            let w = pool.remove(at: i)
            let screen = Screen.named(entry.screen) ?? NSScreen.main!
            let s = Screen.usable(screen), f = entry.fraction
            place(w, CGRect(x: s.minX + f.minX * s.width, y: s.minY + f.minY * s.height, width: f.width * s.width, height: f.height * s.height))
            placed.append(w)
        }
        // Saved front to back: raise back to front.
        for w in placed.reversed() { w.raise() }
        HUD.show("“\(arrangement.name)”", "\(placed.count) of \(arrangement.entries.count) windows placed", detail: nil)
    }

    func deleteArrangement(_ name: String) {
        arrangements.removeAll { $0.name == name }
        storeArrangements()
    }

    private func storeArrangements() {
        UserDefaults.standard.set(try? JSONEncoder().encode(arrangements), forKey: "arrangements")
    }
}

extension CGRect {
    func distance(to other: CGRect) -> CGFloat {
        abs(minX - other.minX) + abs(minY - other.minY) + abs(width - other.width) + abs(height - other.height)
    }
}

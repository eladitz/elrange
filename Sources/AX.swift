// Other apps' windows, through the Accessibility API: list them, read and set their frames, raise them.
// Accessibility uses top-left-origin coordinates from the main screen's top; AppKit uses bottom-left.
// `Screen.ax(_:)` and `Screen.cocoa(_:)` convert between the two.

import AppKit

struct Win: Identifiable {
    let element: AXUIElement
    let pid: pid_t
    let appName: String
    let bundleID: String?
    let title: String
    var frame: CGRect   // Accessibility coordinates
    var demoIcon: NSImage? = nil

    /// Stable while the window exists: the element's hash plus its app.
    var id: String { "\(pid)-\(CFHash(element))" }
    var icon: NSImage? { demoIcon ?? NSRunningApplication(processIdentifier: pid)?.icon }
    var label: String { title.isEmpty ? appName : "\(appName) — \(title)" }

    func same(as other: Win) -> Bool { CFEqual(element, other.element) }

    /// Size, then position, then size again: an app may refuse a size that doesn't fit where the
    /// window still is (moving between displays), so the second size lands once it has moved.
    func setFrame(_ rect: CGRect) {
        let app = AXUIElementCreateApplication(pid)
        // Some apps animate every change while this is on, which makes moving them slow and jumpy.
        let enhanced = AX.bool(app, "AXEnhancedUserInterface")
        if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }
        AX.set(element, kAXSizeAttribute, rect.size)
        AX.set(element, kAXPositionAttribute, rect.origin)
        AX.set(element, kAXSizeAttribute, rect.size)
        if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) }
    }

    var currentFrame: CGRect { AX.frame(element) ?? frame }

    func raise() {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    /// The screen the window's middle is on.
    var screen: NSScreen { Screen.containing(Screen.cocoa(currentFrame)) }
}

enum AX {
    static var trusted: Bool { AXIsProcessTrusted() }
    /// The tour works on Elrange's own demo windows only, so nothing of yours is moved or shown; normally
    /// Elrange leaves itself alone.
    nonisolated(unsafe) static var onlySelf = false
    private static func isSelf(_ app: NSRunningApplication?) -> Bool { !onlySelf && app?.bundleIdentifier == Bundle.main.bundleIdentifier }

    /// Shows macOS's own "allow Elrange to control your computer" prompt (once) and adds Elrange to the list.
    static func askForTrust() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    /// Whether the window's size can be changed at all (some, like dialogs and calculators, can't).
    static func resizable(_ element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &settable) == .success && settable.boolValue
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool {
        (copy(element, attribute) as? Bool) ?? false
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let p = copy(element, kAXPositionAttribute), let s = copy(element, kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &point)
        AXValueGetValue(s as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    static func set(_ element: AXUIElement, _ attribute: String, _ point: CGPoint) {
        var p = point
        if let value = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(element, attribute as CFString, value) }
    }

    static func set(_ element: AXUIElement, _ attribute: String, _ size: CGSize) {
        var s = size
        if let value = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(element, attribute as CFString, value) }
    }

    private static func win(_ element: AXUIElement, app: NSRunningApplication) -> Win? {
        guard let frame = frame(element) else { return nil }
        return Win(element: element, pid: app.processIdentifier, appName: app.localizedName ?? "App",
                   bundleID: app.bundleIdentifier, title: copy(element, kAXTitleAttribute) as? String ?? "", frame: frame)
    }

    /// The window you're working in.
    static func focused() -> Win? {
        guard let app = NSWorkspace.shared.frontmostApplication, !isSelf(app) else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        guard let window = copy(element, kAXFocusedWindowAttribute) ?? copy(element, kAXMainWindowAttribute) else { return nil }
        return win(window as! AXUIElement, app: app)
    }

    /// The window under a point (Accessibility coordinates), for drag-to-snap.
    static func window(at point: CGPoint) -> Win? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success,
              var element = hit else { return nil }
        // Climb from whatever was hit (a button, the title) to its window.
        for _ in 0..<12 {
            if (copy(element, kAXRoleAttribute) as? String) == kAXWindowRole { break }
            if let window = copy(element, kAXWindowAttribute) { element = window as! AXUIElement; break }
            guard let parent = copy(element, kAXParentAttribute) else { return nil }
            element = parent as! AXUIElement
        }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard let app = NSRunningApplication(processIdentifier: pid), !isSelf(app) else { return nil }
        return win(element, app: app)
    }

    /// Every ordinary, visible window, front to back.
    static func all() -> [Win] {
        var windows: [Win] = []
        for app in NSWorkspace.shared.runningApplications where (onlySelf ? app.processIdentifier == getpid()
            : app.activationPolicy == .regular && !app.isHidden && !isSelf(app)) {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            guard let list = copy(element, kAXWindowsAttribute) as? [AXUIElement] else { continue }
            for window in list {
                guard (copy(window, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole,
                      !bool(window, kAXMinimizedAttribute),
                      let w = win(window, app: app), w.frame.width > 60, w.frame.height > 40 else { continue }
                windows.append(w)
            }
        }
        // Front-to-back order comes from the window server; match by app and frame.
        let order = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? [])
            .compactMap { info -> (pid_t, CGRect)? in
                guard (info[kCGWindowLayer as String] as? Int) == 0, let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                      let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
                return (pid, CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0))
            }
        func rank(_ w: Win) -> Int {
            order.firstIndex { $0.0 == w.pid && abs($0.1.minX - w.frame.minX) < 2 && abs($0.1.minY - w.frame.minY) < 2
                && abs($0.1.width - w.frame.width) < 2 } ?? Int.max
        }
        return windows.sorted { rank($0) < rank($1) }
    }
}

/// Made-up windows of Apple's own apps, for screenshots (ELRANGE_DEMO), so no real window or title shows.
enum Demo {
    static var on: Bool { ProcessInfo.processInfo.environment["ELRANGE_DEMO"] != nil }

    static func windows() -> [Win] {
        let apps: [(String, String, String)] = [
            ("com.apple.Safari", "Safari", "Apple Start Page"), ("com.apple.mail", "Mail", "Inbox"),
            ("com.apple.Notes", "Notes", "Shopping list"), ("com.apple.iCal", "Calendar", "October 2026"),
            ("com.apple.finder", "Finder", "Documents"), ("com.apple.Music", "Music", "Library"),
            ("com.apple.Preview", "Preview", "Holiday photos"),
        ]
        return apps.enumerated().map { n, app in
            let (id, name, title) = app
            let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { NSWorkspace.shared.icon(forFile: $0.path) }
            // A made-up process number each, so every demo window is its own window.
            let pid = pid_t(900_000 + n)
            return Win(element: AXUIElementCreateApplication(pid), pid: pid, appName: name, bundleID: id, title: title,
                       frame: CGRect(x: 100, y: 100, width: 800, height: 600), demoIcon: icon)
        }
    }
}

enum Screen {
    /// The top of the main screen, which Accessibility coordinates count down from.
    private static var top: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }

    static func ax(_ cocoa: CGRect) -> CGRect { CGRect(x: cocoa.minX, y: top - cocoa.maxY, width: cocoa.width, height: cocoa.height) }
    static func cocoa(_ ax: CGRect) -> CGRect { CGRect(x: ax.minX, y: top - ax.maxY, width: ax.width, height: ax.height) }
    static func axPoint(_ cocoa: CGPoint) -> CGPoint { CGPoint(x: cocoa.x, y: top - cocoa.y) }

    static func containing(_ cocoa: CGRect) -> NSScreen {
        let middle = CGPoint(x: cocoa.midX, y: cocoa.midY)
        return NSScreen.screens.first { $0.frame.contains(middle) }
            ?? NSScreen.screens.max { $0.frame.intersection(cocoa).area < $1.frame.intersection(cocoa).area }
            ?? NSScreen.main!
    }

    static func id(_ screen: NSScreen) -> String {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { "\($0)" } ?? screen.localizedName
    }

    static func named(_ id: String) -> NSScreen? { NSScreen.screens.first { Self.id($0) == id || $0.localizedName == id } }

    /// The usable part of a screen (no menu bar or Dock), in Accessibility coordinates.
    static func usable(_ screen: NSScreen) -> CGRect { ax(screen.visibleFrame) }
}

extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}

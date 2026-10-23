// The window switcher: hold the combo (⌃⌥ by default) and turn the mouse wheel to flip through previews
// of every open window; let go to bring the highlighted one to the front. Esc cancels.
// An event tap (covered by the Accessibility permission) swallows those scrolls so the page underneath
// doesn't scroll too. Previews come from ScreenCaptureKit and need Screen Recording; without it, app icons.

import AppKit
import ScreenCaptureKit
import SwiftUI

@MainActor
final class Switcher: ObservableObject {
    static let shared = Switcher()

    struct Item: Identifiable {
        let window: Win
        var preview: NSImage?
        var id: String { window.id }
    }

    @Published var items: [Item] = []
    @Published var index = 0
    @Published var previewsAllowed = true

    /// From the switcher's strip: the Screen Recording page, where Elrange is listed.
    func allowPreviews() {
        hide()
        CGRequestScreenCaptureAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        HUD.show("Switch Elrange on, then reopen it", "macOS offers “Quit & Reopen” after you switch it on; choose it.", detail: nil)
    }
    private(set) var showing = false
    private var panel: NSPanel?
    private var tap: CFMachPort?
    private var wheel: CGFloat = 0          // trackpads send many small deltas: add them up into steps
    private var previews: [String: NSImage] = [:]   // window id → last preview, shown at once next time

    /// The keys to hold while scrolling, from Settings.
    static let combos: [(name: String, flags: CGEventFlags)] = [
        ("⌃⌥ Control-Option", [.maskControl, .maskAlternate]),
        ("⌥ Option", [.maskAlternate]),
        ("⌃ Control", [.maskControl]),
        ("⌘⌥ Command-Option", [.maskCommand, .maskAlternate]),
        ("⌃⇧ Control-Shift", [.maskControl, .maskShift]),
    ]

    var combo: CGEventFlags {
        let name = UserDefaults.standard.string(forKey: "switcherCombo") ?? Self.combos[0].name
        return Self.combos.first { $0.name == name }?.flags ?? Self.combos[0].flags
    }

    var enabled: Bool { UserDefaults.standard.object(forKey: "switcher") as? Bool ?? true }

    // MARK: Listening

    func start() {
        guard tap == nil else { return }
        let mask = (1 << CGEventType.scrollWheel.rawValue) | (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: CGEventMask(mask), callback: { _, type, event, _ in
            // Runs on the main run loop; decide synchronously whether the event goes on.
            MainActor.assumeIsolated { Switcher.shared.handle(type, event) ? nil : Unmanaged.passUnretained(event) }
        }, userInfo: nil) else { return }
        tap = port
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    /// True when the event was used here and shouldn't reach the app underneath.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .scrollWheel:
            guard enabled, held(event.flags) else { return false }
            let lines = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
            let points = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
            if !showing { open(); return true }
            if continuous {
                wheel += points
                while abs(wheel) >= 30 { step(wheel > 0 ? -1 : 1); wheel -= wheel > 0 ? 30 : -30 }
            } else if lines != 0 {
                step(lines > 0 ? -1 : 1)
            }
            return true
        case .flagsChanged:
            if showing && !held(event.flags) { commit() }
            return false
        case .keyDown:
            guard showing else { return false }
            switch event.getIntegerValueField(.keyboardEventKeycode) {
            case 53: cancel()                                // Esc
            case 36, 76: commit()                            // Return
            case 123, 126: step(-1)                          // ← ↑
            case 124, 125, 48: step(1)                       // → ↓ Tab
            default: return false
            }
            return true
        default:
            return false
        }
    }

    /// All of the combo's keys, and no other modifier keys.
    private func held(_ flags: CGEventFlags) -> Bool {
        let relevant: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift]
        return flags.intersection(relevant) == combo
    }

    // MARK: Showing

    private func open() {
        let windows = AX.all()
        guard !windows.isEmpty else { return NSSound.beep() }
        items = windows.map { Item(window: $0, preview: previews[$0.id]) }
        // Like Alt-Tab: start on the window behind the one in front.
        index = items.count > 1 ? 1 : 0
        wheel = 0
        showing = true
        present()
        Task { await loadPreviews() }
    }

    private func step(_ by: Int) {
        guard !items.isEmpty else { return }
        index = (index + by + items.count) % items.count
    }

    func choose(_ i: Int) {
        index = i
        commit()
    }

    private func commit() {
        guard showing else { return }
        let chosen = items.indices.contains(index) ? items[index].window : nil
        hide()
        chosen?.raise()
        Donation.recordUse()
    }

    private func cancel() { hide() }

    private func hide() {
        showing = false
        panel?.orderOut(nil)
    }

    private func present() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main!
        let panel = self.panel ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.level = .popUpMenu
            p.hasShadow = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            p.contentView = NSHostingView(rootView: SwitcherView(switcher: self))
            self.panel = p
            return p
        }()
        let card = CGSize(width: 240, height: 200)
        let width = min(screen.visibleFrame.width - 80, CGFloat(items.count) * (card.width + 14) + 40)
        let size = NSSize(width: max(width, 420), height: card.height + 64 + (Self.canPreview ? 0 : 34))
        panel.setFrame(NSRect(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.midY - size.height / 2,
                              width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
    }

    /// For screenshots: the switcher filled with the running apps (icons, no previews).
    func showSample() -> NSPanel? {
        items = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.prefix(6).map {
            Item(window: Win(element: AXUIElementCreateApplication($0.processIdentifier), pid: $0.processIdentifier, appName: $0.localizedName ?? "App",
                             bundleID: $0.bundleIdentifier, title: $0.localizedName ?? "", frame: .zero), preview: nil)
        }
        index = 1
        showing = true
        present()
        return panel
    }

    // MARK: Previews

    static var canPreview: Bool { CGPreflightScreenCaptureAccess() }

    private func loadPreviews() async {
        previewsAllowed = Self.canPreview
        if !previewsAllowed {
            // Puts Elrange in Settings' Screen Recording list (macOS prompts the first time only), so it's
            // there to switch on. Until then the cards show icons, and a strip says how to get previews.
            CGRequestScreenCaptureAccess()
            return
        }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else { return }
        for i in items.indices {
            let w = items[i].window
            // The same app's window whose frame is closest (apps round their frames differently).
            guard let match = content.windows
                .filter({ $0.owningApplication?.processID == w.pid && $0.windowLayer == 0 && $0.frame.width > 40 })
                .min(by: { $0.frame.distance(to: w.frame) < $1.frame.distance(to: w.frame) }),
                  match.frame.distance(to: w.frame) < 60 else { continue }
            let config = SCStreamConfiguration()
            let scale = min(1, 480 / max(match.frame.width, 1))
            config.width = Int(match.frame.width * scale * 2)
            config.height = Int(match.frame.height * scale * 2)
            config.showsCursor = false
            guard let cg = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: match), configuration: config),
                  showing, items.indices.contains(i), items[i].id == w.id else { continue }
            let image = NSImage(cgImage: cg, size: NSSize(width: cg.width / 2, height: cg.height / 2))
            items[i].preview = image
            previews[w.id] = image
        }
    }
}

struct SwitcherView: View {
    @ObservedObject var switcher: Switcher

    var body: some View {
        VStack(spacing: 0) {
            strip
            if !switcher.previewsAllowed {
                Button { switcher.allowPreviews() } label: {
                    Label("Showing app icons — click to allow live window previews (Screen Recording)", systemImage: "rectangle.dashed.badge.record")
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 6)
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.12)))
    }

    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Array(switcher.items.enumerated()), id: \.element.id) { i, item in
                        card(item, selected: i == switcher.index)
                            .id(i)
                            .onTapGesture { switcher.choose(i) }
                    }
                }
                .padding(20)
            }
            .onChange(of: switcher.index) { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(switcher.index, anchor: .center) } }
            .onAppear { proxy.scrollTo(switcher.index, anchor: .center) }
        }
    }

    private func card(_ item: Switcher.Item, selected: Bool) -> some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.25))
                if let preview = item.preview {
                    Image(nsImage: preview).resizable().aspectRatio(contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 8)).padding(6)
                } else if let icon = item.window.icon {
                    Image(nsImage: icon).resizable().frame(width: 72, height: 72)
                }
            }
            .frame(width: 240, height: 150)
            HStack(spacing: 6) {
                if let icon = item.window.icon { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
                Text(item.window.title.isEmpty ? item.window.appName : item.window.title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular)).lineLimit(1).truncationMode(.middle)
            }
            .frame(width: 232)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 14).fill(selected ? Color.accentColor.opacity(0.35) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
        .scaleEffect(selected ? 1.0 : 0.94)
        .animation(.easeOut(duration: 0.12), value: selected)
    }
}

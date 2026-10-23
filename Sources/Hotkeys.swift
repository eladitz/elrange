// System-wide keyboard shortcuts (Carbon hotkeys: they work in every app and need no extra permission),
// and the recorder used to change them in Settings.

import AppKit
import Carbon
import SwiftUI

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt   // NSEvent.ModifierFlags

    enum Key: UInt32 {
        case a = 0, c = 8, d = 2, e = 14, f = 3, g = 5, i = 34, j = 38, k = 40, m = 46, t = 17, u = 32
        case `return` = 36, delete = 51, minus = 27, equal = 24
        case leftArrow = 123, rightArrow = 124, downArrow = 125, upArrow = 126
    }

    init(_ key: Key, _ flags: NSEvent.ModifierFlags) { self.init(keyCode: key.rawValue, flags: flags) }

    init(keyCode: UInt32, flags: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        modifiers = flags.intersection([.command, .option, .control, .shift]).rawValue
    }

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    /// "⌃⌥←", as menus show it.
    var display: String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + Self.keyName(keyCode)
    }

    static func keyName(_ code: UInt32) -> String {
        let named: [UInt32: String] = [123: "←", 124: "→", 125: "↓", 126: "↑", 36: "↩", 51: "⌫", 117: "⌦", 48: "⇥", 49: "Space", 53: "⎋",
                                       76: "⌤", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
                                       122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]
        if let name = named[code] { return name }
        // Letters and symbols as the current keyboard layout prints them.
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let data = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "?" }
        let layout = unsafeBitCast(data, to: CFData.self)
        var dead: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = CFDataGetBytePtr(layout).withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) {
            UCKeyTranslate($0, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                           &dead, 4, &length, &chars)
        }
        return status == noErr && length > 0 ? String(utf16CodeUnits: chars, count: length).uppercased() : "?"
    }
}

@MainActor
final class Hotkeys {
    static let shared = Hotkeys()
    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: Action] = [:]
    var perform: ((Action) -> Void)?
    private var installed = false

    private static let defaultsKey = "shortcuts"

    /// The shortcuts in use: Rectangle's defaults, with your changes on top. A missing entry means "none".
    var shortcuts: [Action: Shortcut] {
        get {
            if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
               let saved = try? JSONDecoder().decode([String: Shortcut?].self, from: data) {
                var result: [Action: Shortcut] = [:]
                for action in Action.allCases {
                    if let entry = saved[action.rawValue] { if let entry { result[action] = entry } }
                    else if let d = action.defaultShortcut { result[action] = d }
                }
                return result
            }
            return Dictionary(uniqueKeysWithValues: Action.allCases.compactMap { a in a.defaultShortcut.map { (a, $0) } })
        }
    }

    func set(_ shortcut: Shortcut?, for action: Action) {
        var saved: [String: Shortcut?] = [:]
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([String: Shortcut?].self, from: data) { saved = decoded }
        // A shortcut belongs to one action: take it off any other.
        if let shortcut {
            for (other, s) in shortcuts where s == shortcut && other != action { saved[other.rawValue] = .some(nil) }
        }
        saved[action.rawValue] = .some(shortcut)
        UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: Self.defaultsKey)
        register()
    }

    func resetAll() {
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        register()
    }

    func register() {
        unregister()
        if !installed {
            installed = true
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &id)
                let number = id.id
                DispatchQueue.main.async { MainActor.assumeIsolated { Hotkeys.shared.fire(number) } }
                return noErr
            }, 1, &spec, nil, nil)
        }
        for (n, (action, shortcut)) in shortcuts.enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x456C_7267), id: UInt32(n + 1))   // 'Elrg'
            if RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                refs.append(ref)
                actions[UInt32(n + 1)] = action
            }
        }
    }

    /// While a shortcut is being recorded, so pressing it records instead of firing.
    func unregister() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        actions = [:]
    }

    private func fire(_ id: UInt32) {
        if let action = actions[id] { perform?(action) }
    }
}

/// Click, then press the shortcut. Esc cancels, ⌫ clears.
struct ShortcutRecorder: NSViewRepresentable {
    let action: Action
    let shortcut: Shortcut?
    let onChange: (Shortcut?) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.onChange = onChange
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.shortcut = shortcut
        button.onChange = onChange
        button.refresh()
    }
}

final class RecorderButton: NSButton {
    var shortcut: Shortcut?
    var onChange: ((Shortcut?) -> Void)?
    private var recording = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(start)
        widthAnchor.constraint(equalToConstant: 120).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        title = recording ? "Press keys…" : shortcut?.display ?? "Record"
        contentTintColor = shortcut == nil && !recording ? .secondaryLabelColor : nil
    }

    @objc private func start() {
        recording = true
        refresh()
        MainActor.assumeIsolated { Hotkeys.shared.unregister() }
        window?.makeFirstResponder(self)
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard recording else { return super.keyDown(with: event) }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch event.keyCode {
        case 53: finish(nil, changed: false)            // Esc
        case 51 where flags.isEmpty: finish(nil, changed: true)   // ⌫ alone clears
        default:
            // A shortcut needs a modifier, except the function keys.
            let functionKey = (96...122).contains(Int(event.keyCode))
            guard !flags.isEmpty || functionKey else { NSSound.beep(); return }
            finish(Shortcut(keyCode: UInt32(event.keyCode), flags: flags), changed: true)
        }
    }

    override func resignFirstResponder() -> Bool {
        if recording { finish(nil, changed: false) }
        return super.resignFirstResponder()
    }

    private func finish(_ new: Shortcut?, changed: Bool) {
        recording = false
        if changed { shortcut = new; onChange?(new) }
        refresh()
        MainActor.assumeIsolated { Hotkeys.shared.register() }
    }
}

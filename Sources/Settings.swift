// Settings: every shortcut (click to re-record), snapping, gaps, apps to leave alone, and general options.

import SwiftUI

@MainActor
final class SettingsModel: ObservableObject {
    @Published var shortcuts = Hotkeys.shared.shortcuts
    @Published var tab = "shortcuts"

    func set(_ s: Shortcut?, _ action: Action) {
        Hotkeys.shared.set(s, for: action)
        shortcuts = Hotkeys.shared.shortcuts
        AppDelegate.shared?.rebuildMenu()
    }

    func resetAll() {
        Hotkeys.shared.resetAll()
        shortcuts = Hotkeys.shared.shortcuts
        AppDelegate.shared?.rebuildMenu()
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $model.tab) {
                Text("Shortcuts").tag("shortcuts")
                Text("Snapping").tag("snapping")
                Text("General").tag("general")
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 320).padding(12)
            Divider()
            switch model.tab {
            case "snapping": snapping
            case "general": general
            default: shortcuts
            }
        }
    }

    private var shortcuts: some View {
        VStack(spacing: 0) {
            List {
                ForEach(Action.groups, id: \.0) { group, actions in
                    Section(group) {
                        ForEach(actions) { action in
                            HStack {
                                Image(nsImage: ActionIcon.image(action)).frame(width: 22)
                                Text(action.title)
                                Spacer()
                                if Hotkeys.shared.taken.contains(action) {
                                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                        .help("macOS or another app already uses these keys, so this shortcut doesn't work")
                                }
                                ShortcutRecorder(action: action, shortcut: model.shortcuts[action]) { model.set($0, action) }
                                    .frame(width: 120)
                                Button { model.set(nil, action) } label: { Image(systemName: "xmark.circle.fill") }
                                    .buttonStyle(.borderless).foregroundStyle(.tertiary)
                                    .opacity(model.shortcuts[action] == nil ? 0 : 1)
                                    .help("Remove this shortcut")
                            }
                        }
                    }
                }
            }
            HStack {
                Text("Click a shortcut, then press the new keys. Esc cancels, ⌫ clears.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Restore Rectangle Defaults") { model.resetAll() }
            }
            .padding(10)
        }
    }

    private var snapping: some View {
        Form {
            Toggle("Snap windows by dragging them to a screen edge or corner", isOn: $prefs.snapping)
            Text("Top edge: maximize. Left or right edge: half. Corners: quarter. Bottom edge: a third, by where along it you let go.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Give a snapped window its old size back when you drag it away", isOn: $prefs.restoreOnDragAway)
            Toggle("Pressing a half again cycles ½ → ⅔ → ⅓", isOn: $prefs.cycle)
            HStack {
                Text("Gap between windows")
                Slider(value: $prefs.gap, in: 0...40, step: 2)
                Text("\(Int(prefs.gap)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            Section("Leave these apps alone") {
                if prefs.ignored.isEmpty {
                    Text("None. Use “Ignore …” in Elrange's menu while the app is in front.").foregroundStyle(.secondary)
                }
                ForEach(prefs.ignored, id: \.self) { id in
                    HStack {
                        Text(NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { FileManager.default.displayName(atPath: $0.path) } ?? id)
                        Spacer()
                        Button("Remove") { prefs.ignored.removeAll { $0 == id } }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var general: some View {
        Form {
            Section("Window switcher") {
                Toggle("Hold keys and turn the mouse wheel to flip through window previews",
                       isOn: Binding(get: { Switcher.shared.enabled }, set: { UserDefaults.standard.set($0, forKey: "switcher"); prefs.objectWillChange.send() }))
                Picker("Keys to hold", selection: Binding(get: { UserDefaults.standard.string(forKey: "switcherCombo") ?? Switcher.combos[0].name },
                                                          set: { UserDefaults.standard.set($0, forKey: "switcherCombo"); prefs.objectWillChange.send() })) {
                    ForEach(Switcher.combos, id: \.name) { Text($0.name).tag($0.name) }
                }
                Text("Let go of the keys to bring the highlighted window forward. Arrow keys and Tab move too; Esc cancels.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text(Switcher.canPreview ? "Previews: on" : "Previews: app icons until Screen Recording is allowed")
                    Spacer()
                    if !Switcher.canPreview {
                        Button("Allow…") {
                            CGRequestScreenCaptureAccess()
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                        }
                    }
                }
            }
            Toggle("Open Elrange at login", isOn: Binding(get: { prefs.launchAtLogin }, set: { prefs.launchAtLogin = $0 }))
            HStack {
                Text(AX.trusted ? "Accessibility: allowed" : "Accessibility: not allowed yet")
                Spacer()
                if !AX.trusted { Button("Allow…") { AppDelegate.shared?.showPermission() } }
            }
            Text("Elrange moves other apps' windows through macOS's Accessibility controls; it reads nothing else.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Check for Updates…") { Task { await Updater.check(manual: true) } }
                Button("Website") { NSWorkspace.shared.open(URL(string: "https://ai.itzkin.com/elrange.html")!) }
                Button("Support on Ko-fi") { NSWorkspace.shared.open(Donation.page) }
            }
        }
        .formStyle(.grouped)
    }
}

// Arrange Windows: tick the windows you want, drag them into priority order, pick a screen on the map
// and a layout, and Apply. Number 1 gets the best place (the big pane, the left column, the front).

import SwiftUI

@MainActor
final class ArrangeModel: ObservableObject {
    @Published var windows: [Win] = []
    @Published var screenID: String
    @Published var layout: Layout
    weak var window: NSWindow?
    let manager = Manager.shared

    init() {
        let last = Prefs.shared.lastScreen
        screenID = Screen.named(last) != nil ? last : Screen.id(Manager.shared.activeScreen)
        layout = Prefs.shared.lastLayout
        reload()
    }

    func reload() {
        windows = AX.all().filter { !Prefs.shared.isIgnored($0) }
        _ = manager.liveMarked()
        objectWillChange.send()
    }

    var marked: [Win] { manager.marked }
    var others: [Win] { windows.filter { !manager.isMarked($0) } }

    func toggle(_ w: Win) {
        if manager.isMarked(w) { manager.setMarked(manager.marked.filter { !$0.same(as: w) }) }
        else { manager.setMarked(manager.marked + [w]) }
        objectWillChange.send()
    }

    func markAllOnScreen() {
        guard let screen = Screen.named(screenID) else { return }
        manager.setMarked(manager.marked + others.filter { $0.screen == screen })
        objectWillChange.send()
    }

    func apply() {
        guard let screen = Screen.named(screenID) else { return }
        manager.arrange(manager.liveMarked(), layout, on: screen)
    }

    func saveArrangement() {
        let alert = NSAlert()
        alert.messageText = "Save this arrangement"
        alert.informativeText = "Saves where every window is now, on every screen. Bring it back from Elrange's menu."
        let field = NSTextField(string: "")
        field.placeholderString = "e.g. Coding, Calls, Writing"
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { manager.saveArrangement(name) }
    }
}

struct ArrangeView: View {
    @ObservedObject var model: ArrangeModel
    @ObservedObject var manager = Manager.shared

    var body: some View {
        HStack(spacing: 0) {
            // Left: windows.
            VStack(spacing: 0) {
                List {
                    Section {
                        if model.marked.isEmpty {
                            Text("Tick windows below, or press ⌃⌥M on any window.").font(.callout).foregroundStyle(.secondary)
                        }
                        ForEach(Array(model.marked.enumerated()), id: \.element.id) { i, w in
                            WindowRow(window: w, number: i + 1, marked: true) { model.toggle(w) }
                        }
                        .onMove { manager.moveMark(from: $0, to: $1); model.objectWillChange.send() }
                    } header: {
                        Text("Marked — drag to set priority")
                    }
                    Section("Other windows") {
                        ForEach(model.others) { w in
                            WindowRow(window: w, number: nil, marked: false) { model.toggle(w) }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: false))
                HStack {
                    Button("Mark All on This Screen") { model.markAllOnScreen() }
                    Button("Clear") { manager.clearMarks(); model.objectWillChange.send() }.disabled(model.marked.isEmpty)
                    Spacer()
                    Button { model.reload() } label: { Image(systemName: "arrow.clockwise") }.help("Refresh the list")
                }
                .padding(10)
            }
            .frame(minWidth: 340)

            Divider()

            // Right: where and how.
            VStack(alignment: .leading, spacing: 14) {
                Text("Screen").font(.headline)
                ScreenMap(selected: $model.screenID, layout: model.layout, count: max(model.marked.count, 1))
                    .frame(height: 170)
                Text("On " + (Screen.named(model.screenID)?.localizedName ?? "this screen") + ". Click another screen to use it.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Layout").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                    ForEach(Layout.allCases) { layout in
                        LayoutTile(layout: layout, selected: model.layout == layout, count: max(model.marked.count, 3))
                            .onTapGesture { model.layout = layout }
                            .help(layout.hint)
                    }
                }
                Text(model.layout.hint).font(.caption).foregroundStyle(.secondary)
                Spacer()
                HStack {
                    Button("Save Arrangement…") { model.saveArrangement() }
                        .help("Remember where every window is now, to bring back later")
                    Spacer()
                    Button("Arrange \(model.marked.count) Window\(model.marked.count == 1 ? "" : "s")") { model.apply() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.marked.isEmpty)
                }
            }
            .padding(16)
            .frame(minWidth: 360)
        }
    }
}

private struct WindowRow: View {
    let window: Win
    let number: Int?
    let marked: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: marked ? "checkmark.square.fill" : "square")
                .foregroundStyle(marked ? Color.accentColor : .secondary)
                .onTapGesture(perform: toggle)
            if let number {
                Text("\(number)").font(.system(size: 11, weight: .bold)).monospacedDigit()
                    .frame(width: 18, height: 18).background(Color.accentColor.opacity(0.2), in: Circle())
            }
            if let icon = window.icon { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
            VStack(alignment: .leading, spacing: 1) {
                Text(window.appName).font(.system(size: 12, weight: .medium))
                if !window.title.isEmpty {
                    Text(window.title).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            Text(window.screen.localizedName).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { window.raise() }
        .help("Double-click to bring it to the front")
    }
}

/// The screens as they're arranged in System Settings; click one to pick it. The picked one shows the layout.
private struct ScreenMap: View {
    @Binding var selected: String
    let layout: Layout
    let count: Int

    var body: some View {
        GeometryReader { geo in
            let screens = NSScreen.screens
            let all = screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
            let scale = min(geo.size.width / all.width, geo.size.height / all.height) * 0.95
            let offset = CGPoint(x: (geo.size.width - all.width * scale) / 2, y: (geo.size.height - all.height * scale) / 2)
            ZStack(alignment: .topLeading) {
                ForEach(screens, id: \.self) { screen in
                    let f = screen.frame
                    let rect = CGRect(x: offset.x + (f.minX - all.minX) * scale, y: offset.y + (all.maxY - f.maxY) * scale,
                                      width: f.width * scale, height: f.height * scale)
                    let isSelected = Screen.id(screen) == selected
                    ZStack {
                        RoundedRectangle(cornerRadius: 6).fill(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
                        RoundedRectangle(cornerRadius: 6).strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: isSelected ? 2 : 1)
                        if isSelected {
                            LayoutPreview(layout: layout, count: count).padding(6)
                        } else {
                            Text(screen.localizedName).font(.system(size: 10)).foregroundStyle(.secondary).padding(4).multilineTextAlignment(.center)
                        }
                    }
                    .frame(width: rect.width - 4, height: rect.height - 4)
                    .offset(x: rect.minX + 2, y: rect.minY + 2)
                    .onTapGesture { selected = Screen.id(screen) }
                    .help(screen.localizedName)
                }
            }
        }
    }
}

private struct LayoutTile: View {
    let layout: Layout
    let selected: Bool
    let count: Int

    var body: some View {
        VStack(spacing: 5) {
            LayoutPreview(layout: layout, count: count)
                .frame(height: 46)
                .padding(5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
            Text(layout.title).font(.system(size: 11)).lineLimit(1)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(Rectangle())
    }
}

/// Numbered boxes where the windows will go.
private struct LayoutPreview: View {
    let layout: Layout
    let count: Int

    var body: some View {
        GeometryReader { geo in
            let area = CGRect(origin: .zero, size: geo.size)
            let frames = layout.frames(count, in: area)
            ZStack(alignment: .topLeading) {
                // Back to front, so number 1 is drawn last (on top), as it will be on screen.
                ForEach(Array(frames.enumerated().reversed()), id: \.offset) { i, f in
                    let r = layout.tiles ? f.insetBy(dx: 1.5, dy: 1.5) : f
                    ZStack {
                        RoundedRectangle(cornerRadius: 3).fill(i == 0 ? Color.accentColor.opacity(0.85) : Color.accentColor.opacity(0.35))
                        RoundedRectangle(cornerRadius: 3).strokeBorder(Color.primary.opacity(0.25))
                        Text("\(i + 1)").font(.system(size: max(8, min(r.height * 0.35, 16)), weight: .bold)).foregroundStyle(.white)
                            // Overlapping windows: the number sits in the visible top-left corner.
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: layout.tiles ? .center : .topLeading)
                            .padding(layout.tiles ? 0 : 3)
                    }
                    .frame(width: max(r.width, 4), height: max(r.height, 4))
                    .offset(x: r.minX, y: r.minY)
                }
            }
        }
    }
}

// Where windows go: Rectangle's actions for one window, and Windows-style layouts for many.
// Everything is worked out inside a screen's usable area, in Accessibility coordinates (y grows downward).

import AppKit

enum Action: String, CaseIterable, Codable, Identifiable {
    case leftHalf, rightHalf, centerHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case firstThird, centerThird, lastThird, firstTwoThirds, centerTwoThirds, lastTwoThirds
    case firstFourth, secondFourth, thirdFourth, lastFourth, firstThreeFourths, lastThreeFourths
    case topLeftSixth, topCenterSixth, topRightSixth, bottomLeftSixth, bottomCenterSixth, bottomRightSixth
    case maximize, almostMaximize, maximizeHeight, smaller, larger, center, restore
    case nextDisplay, previousDisplay
    case moveLeft, moveRight, moveUp, moveDown
    case cascade, sideBySide, stacked
    case markWindow, arrangeMarked, clearMarks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftHalf: "Left Half"
        case .rightHalf: "Right Half"
        case .centerHalf: "Center Half"
        case .topHalf: "Top Half"
        case .bottomHalf: "Bottom Half"
        case .topLeft: "Top Left"
        case .topRight: "Top Right"
        case .bottomLeft: "Bottom Left"
        case .bottomRight: "Bottom Right"
        case .firstThird: "First Third"
        case .centerThird: "Center Third"
        case .lastThird: "Last Third"
        case .firstTwoThirds: "First Two Thirds"
        case .centerTwoThirds: "Center Two Thirds"
        case .lastTwoThirds: "Last Two Thirds"
        case .firstFourth: "First Fourth"
        case .secondFourth: "Second Fourth"
        case .thirdFourth: "Third Fourth"
        case .lastFourth: "Last Fourth"
        case .firstThreeFourths: "First Three Fourths"
        case .lastThreeFourths: "Last Three Fourths"
        case .topLeftSixth: "Top Left Sixth"
        case .topCenterSixth: "Top Center Sixth"
        case .topRightSixth: "Top Right Sixth"
        case .bottomLeftSixth: "Bottom Left Sixth"
        case .bottomCenterSixth: "Bottom Center Sixth"
        case .bottomRightSixth: "Bottom Right Sixth"
        case .maximize: "Maximize"
        case .almostMaximize: "Almost Maximize"
        case .maximizeHeight: "Maximize Height"
        case .smaller: "Make Smaller"
        case .larger: "Make Larger"
        case .center: "Center"
        case .restore: "Restore"
        case .nextDisplay: "Next Display"
        case .previousDisplay: "Previous Display"
        case .moveLeft: "Move Left"
        case .moveRight: "Move Right"
        case .moveUp: "Move Up"
        case .moveDown: "Move Down"
        case .cascade: "Cascade Windows"
        case .sideBySide: "Show Windows Side by Side"
        case .stacked: "Show Windows Stacked"
        case .markWindow: "Mark / Unmark Window"
        case .arrangeMarked: "Arrange Marked Windows"
        case .clearMarks: "Clear Marks"
        }
    }

    /// Rectangle's default shortcuts (⌃⌥ plus a key), and a few of Elrange's own.
    var defaultShortcut: Shortcut? {
        let ca: NSEvent.ModifierFlags = [.control, .option]
        switch self {
        case .leftHalf: return .init(.leftArrow, ca)
        case .rightHalf: return .init(.rightArrow, ca)
        case .topHalf: return .init(.upArrow, ca)
        case .bottomHalf: return .init(.downArrow, ca)
        case .topLeft: return .init(.u, ca)
        case .topRight: return .init(.i, ca)
        case .bottomLeft: return .init(.j, ca)
        case .bottomRight: return .init(.k, ca)
        case .firstThird: return .init(.d, ca)
        case .centerThird: return .init(.f, ca)
        case .lastThird: return .init(.g, ca)
        case .firstTwoThirds: return .init(.e, ca)
        case .lastTwoThirds: return .init(.t, ca)
        case .maximize: return .init(.return, ca)
        case .maximizeHeight: return .init(.upArrow, ca.union(.shift))
        case .smaller: return .init(.minus, ca)
        case .larger: return .init(.equal, ca)
        case .center: return .init(.c, ca)
        case .restore: return .init(.delete, ca)
        case .nextDisplay: return .init(.rightArrow, ca.union(.command))
        case .previousDisplay: return .init(.leftArrow, ca.union(.command))
        case .markWindow: return .init(.m, ca)
        case .arrangeMarked: return .init(.a, ca)
        default: return nil
        }
    }

    /// Menu groups, in order.
    static let groups: [(String, [Action])] = [
        ("Halves", [.leftHalf, .rightHalf, .centerHalf, .topHalf, .bottomHalf]),
        ("Corners", [.topLeft, .topRight, .bottomLeft, .bottomRight]),
        ("Thirds", [.firstThird, .centerThird, .lastThird, .firstTwoThirds, .centerTwoThirds, .lastTwoThirds]),
        ("Fourths", [.firstFourth, .secondFourth, .thirdFourth, .lastFourth, .firstThreeFourths, .lastThreeFourths]),
        ("Sixths", [.topLeftSixth, .topCenterSixth, .topRightSixth, .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth]),
        ("Size", [.maximize, .almostMaximize, .maximizeHeight, .smaller, .larger, .center, .restore]),
        ("Displays", [.nextDisplay, .previousDisplay]),
        ("Move", [.moveLeft, .moveRight, .moveUp, .moveDown]),
        ("Arrange", [.cascade, .sideBySide, .stacked]),
        ("Marks", [.markWindow, .arrangeMarked, .clearMarks]),
    ]

    /// For one window: its new frame, from the screen's usable area `s`, the window's frame `w`,
    /// and how many times in a row this was pressed (`cycle`, from 0).
    func frame(in s: CGRect, window w: CGRect, cycle: Int) -> CGRect? {
        func cols(_ from: CGFloat, _ span: CGFloat, of n: CGFloat) -> CGRect {
            CGRect(x: s.minX + s.width * from / n, y: s.minY, width: s.width * span / n, height: s.height)
        }
        func rows(_ from: CGFloat, _ span: CGFloat, of n: CGFloat) -> CGRect {
            CGRect(x: s.minX, y: s.minY + s.height * from / n, width: s.width, height: s.height * span / n)
        }
        func cell(_ col: CGFloat, _ row: CGFloat, cols c: CGFloat, rows r: CGFloat) -> CGRect {
            CGRect(x: s.minX + s.width * col / c, y: s.minY + s.height * row / r, width: s.width / c, height: s.height / r)
        }
        // Pressing a half again: ½ → ⅔ → ⅓, as Rectangle does.
        let share: CGFloat = [0.5, 2.0 / 3, 1.0 / 3][cycle % 3]
        switch self {
        case .leftHalf: return CGRect(x: s.minX, y: s.minY, width: s.width * share, height: s.height)
        case .rightHalf: return CGRect(x: s.maxX - s.width * share, y: s.minY, width: s.width * share, height: s.height)
        case .topHalf: return CGRect(x: s.minX, y: s.minY, width: s.width, height: s.height * share)
        case .bottomHalf: return CGRect(x: s.minX, y: s.maxY - s.height * share, width: s.width, height: s.height * share)
        case .centerHalf: return cols(1, 2, of: 4)
        case .topLeft: return cell(0, 0, cols: 2, rows: 2)
        case .topRight: return cell(1, 0, cols: 2, rows: 2)
        case .bottomLeft: return cell(0, 1, cols: 2, rows: 2)
        case .bottomRight: return cell(1, 1, cols: 2, rows: 2)
        case .firstThird: return cols(0, 1, of: 3)
        case .centerThird: return cols(1, 1, of: 3)
        case .lastThird: return cols(2, 1, of: 3)
        case .firstTwoThirds: return cols(0, 2, of: 3)
        case .centerTwoThirds: return cols(0.5, 2, of: 3)
        case .lastTwoThirds: return cols(1, 2, of: 3)
        case .firstFourth: return cols(0, 1, of: 4)
        case .secondFourth: return cols(1, 1, of: 4)
        case .thirdFourth: return cols(2, 1, of: 4)
        case .lastFourth: return cols(3, 1, of: 4)
        case .firstThreeFourths: return cols(0, 3, of: 4)
        case .lastThreeFourths: return cols(1, 3, of: 4)
        case .topLeftSixth: return cell(0, 0, cols: 3, rows: 2)
        case .topCenterSixth: return cell(1, 0, cols: 3, rows: 2)
        case .topRightSixth: return cell(2, 0, cols: 3, rows: 2)
        case .bottomLeftSixth: return cell(0, 1, cols: 3, rows: 2)
        case .bottomCenterSixth: return cell(1, 1, cols: 3, rows: 2)
        case .bottomRightSixth: return cell(2, 1, cols: 3, rows: 2)
        case .maximize: return s
        case .almostMaximize: return s.insetBy(dx: s.width * 0.05, dy: s.height * 0.05)
        case .maximizeHeight: return CGRect(x: w.minX, y: s.minY, width: w.width, height: s.height)
        case .smaller, .larger:
            let step: CGFloat = self == .larger ? 30 : -30
            let r = w.insetBy(dx: -step, dy: -step)
            guard r.width > 200, r.height > 120 else { return w }
            return r.intersection(s).isNull ? r : r.intersection(s)
        case .center: return CGRect(x: s.midX - w.width / 2, y: s.midY - w.height / 2, width: w.width, height: w.height).fitted(in: s)
        case .moveLeft: return CGRect(x: s.minX, y: w.minY, width: w.width, height: w.height).fitted(in: s)
        case .moveRight: return CGRect(x: s.maxX - w.width, y: w.minY, width: w.width, height: w.height).fitted(in: s)
        case .moveUp: return CGRect(x: w.minX, y: s.minY, width: w.width, height: w.height).fitted(in: s)
        case .moveDown: return CGRect(x: w.minX, y: s.maxY - w.height, width: w.width, height: w.height).fitted(in: s)
        default: return nil   // handled elsewhere (restore, displays, layouts, marks)
        }
    }

    /// Actions that fill part of the screen get gaps; the ones that keep the window's own size don't.
    var tiles: Bool { ![.smaller, .larger, .center, .moveLeft, .moveRight, .moveUp, .moveDown, .maximizeHeight].contains(self) }
}

/// Windows-style layouts for several windows; the first window (priority 1) gets the best place.
enum Layout: String, CaseIterable, Codable, Identifiable {
    case cascade, columns, rows, grid, mainSide, mainBottom, maximized
    var id: String { rawValue }

    var title: String {
        switch self {
        case .cascade: "Cascade"
        case .columns: "Side by Side"
        case .rows: "Stacked"
        case .grid: "Grid"
        case .mainSide: "Main + Side"
        case .mainBottom: "Main + Bottom"
        case .maximized: "All Maximized"
        }
    }

    var hint: String {
        switch self {
        case .cascade: "Overlapping, like Windows' Cascade; number 1 in front"
        case .columns: "Equal columns, number 1 on the left"
        case .rows: "Equal rows, number 1 at the top"
        case .grid: "As square a grid as fits"
        case .mainSide: "Number 1 takes the left 60%, the rest share the right"
        case .mainBottom: "Number 1 takes the top 65%, the rest share the bottom"
        case .maximized: "Each fills the screen; number 1 on top"
        }
    }

    /// Frames for `count` windows in the usable area `s`, in priority order.
    func frames(_ count: Int, in s: CGRect) -> [CGRect] {
        guard count > 0 else { return [] }
        let n = CGFloat(count)
        switch self {
        case .cascade:
            // About Windows' title-bar step on a real screen; proportionally less in a small preview.
            let step = min(32, s.height * 0.1)
            let w = max(s.width * 0.6, s.width - step * (n - 1)), h = max(s.height * 0.6, s.height - step * (n - 1))
            // Priority 1 is drawn last, in front, so it sits at the end of the staircase.
            return (0..<count).map { i in
                let k = CGFloat(count - 1 - i).truncatingRemainder(dividingBy: max(1, floor((s.height - h) / step) + 1))
                return CGRect(x: s.minX + k * step, y: s.minY + k * step, width: w, height: h)
            }
        case .columns:
            return (0..<count).map { CGRect(x: s.minX + s.width * CGFloat($0) / n, y: s.minY, width: s.width / n, height: s.height) }
        case .rows:
            return (0..<count).map { CGRect(x: s.minX, y: s.minY + s.height * CGFloat($0) / n, width: s.width, height: s.height / n) }
        case .grid:
            let cols = Int(ceil(sqrt(n * s.width / s.height / 1.6)).clamped(1, n))
            let rowsCount = Int(ceil(n / CGFloat(cols)))
            return (0..<count).map { i in
                let row = i / cols, col = i % cols
                // A short last row stretches across.
                let inRow = row == rowsCount - 1 ? count - row * cols : cols
                let w = s.width / CGFloat(inRow), h = s.height / CGFloat(rowsCount)
                return CGRect(x: s.minX + w * CGFloat(col), y: s.minY + h * CGFloat(row), width: w, height: h)
            }
        case .mainSide:
            guard count > 1 else { return [s] }
            let main = CGRect(x: s.minX, y: s.minY, width: s.width * 0.6, height: s.height)
            let side = CGRect(x: main.maxX, y: s.minY, width: s.width - main.width, height: s.height)
            return [main] + Layout.rows.frames(count - 1, in: side)
        case .mainBottom:
            guard count > 1 else { return [s] }
            let main = CGRect(x: s.minX, y: s.minY, width: s.width, height: s.height * 0.65)
            let bottom = CGRect(x: s.minX, y: main.maxY, width: s.width, height: s.height - main.height)
            return [main] + Layout.columns.frames(count - 1, in: bottom)
        case .maximized:
            return Array(repeating: s, count: count)
        }
    }

    /// Whether frames butt against each other (and so get gaps between them).
    var tiles: Bool { self != .cascade && self != .maximized }
}

extension CGRect {
    /// Moved (not resized) to lie inside `bounds` where it can.
    func fitted(in bounds: CGRect) -> CGRect {
        var r = self
        r.origin.x = min(max(r.minX, bounds.minX), max(bounds.minX, bounds.maxX - r.width))
        r.origin.y = min(max(r.minY, bounds.minY), max(bounds.minY, bounds.maxY - r.height))
        return r
    }

    /// A tile with gaps: half a gap round every tile plus half at the screen's edge gives even gaps everywhere.
    func gapped(_ gap: CGFloat, in screen: CGRect) -> CGRect {
        guard gap > 0 else { return self }
        var r = insetBy(dx: gap / 2, dy: gap / 2)
        if abs(minX - screen.minX) < 1 { r.origin.x += gap / 2; r.size.width -= gap / 2 }
        if abs(maxX - screen.maxX) < 1 { r.size.width -= gap / 2 }
        if abs(minY - screen.minY) < 1 { r.origin.y += gap / 2; r.size.height -= gap / 2 }
        if abs(maxY - screen.maxY) < 1 { r.size.height -= gap / 2 }
        return r
    }
}

extension Comparable {
    func clamped(_ low: Self, _ high: Self) -> Self { min(max(self, low), high) }
}

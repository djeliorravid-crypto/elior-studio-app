// TaskWidget — iOS Home Screen + Lock Screen widget showing open tasks.
//
// Data flow:
//   index.html JS → TaskWidgetBridge plugin → UserDefaults(suiteName:
//   "group.com.ravidstudio.app").set("widget_tasks": "<json>") →
//   WidgetCenter.shared.reloadAllTimelines() → this file reads and
//   renders the latest list.
//
// Tapping a row deep-links into the app (Capacitor's AppDelegate
// handles the custom URL scheme ravidstudio://).

import WidgetKit
import SwiftUI

// Keep in sync with capacitor.config.json appId and the App Group
// declared in the entitlements files.
private let APP_GROUP_ID = "group.com.ravidstudio.app"
private let TASKS_KEY    = "widget_tasks"

// ── Palette ── matches the app's dark-wood theme but with strong
//    contrast so a glance at the home screen actually reads.
private let BG_TOP     = Color(red: 0.18, green: 0.12, blue: 0.07)
private let BG_BOT     = Color(red: 0.09, green: 0.06, blue: 0.03)
private let ACCENT     = Color(red: 0.85, green: 0.62, blue: 0.40)
private let ACCENT_LO  = Color(red: 0.85, green: 0.62, blue: 0.40).opacity(0.18)
private let TEXT_HI    = Color(red: 0.97, green: 0.93, blue: 0.86)
private let TEXT_LO    = Color(red: 0.97, green: 0.93, blue: 0.86).opacity(0.55)
private let CARD       = Color.white.opacity(0.06)
private let CARD_LINE  = Color.white.opacity(0.10)
private let CHECK_LINE = Color(red: 0.85, green: 0.62, blue: 0.40).opacity(0.55)

struct TaskItem: Codable, Identifiable, Hashable {
    let id:    String
    let title: String
    let done:  Bool
}

struct TaskEntry: TimelineEntry {
    let date:  Date
    let tasks: [TaskItem]
}

struct TaskProvider: TimelineProvider {
    func placeholder(in context: Context) -> TaskEntry {
        TaskEntry(date: Date(), tasks: [
            TaskItem(id: "1", title: "טוען משימות…", done: false)
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (TaskEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskEntry>) -> Void) {
        // Refresh every 15 minutes — the app also calls
        // WidgetCenter.shared.reloadAllTimelines() on every task
        // mutation so we usually don't wait this long.
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [readEntry()], policy: .after(nextRefresh)))
    }

    private func readEntry() -> TaskEntry {
        let defaults = UserDefaults(suiteName: APP_GROUP_ID)
        guard let raw  = defaults?.string(forKey: TASKS_KEY),
              let data = raw.data(using: .utf8),
              let arr  = try? JSONDecoder().decode([TaskItem].self, from: data) else {
            return TaskEntry(date: Date(), tasks: [])
        }
        return TaskEntry(date: Date(), tasks: arr)
    }
}

// ═════════════════════════════════════════════════════════
// MARK: - Ravid Studio waveform logo (drawn with SwiftUI)
// ═════════════════════════════════════════════════════════

// 11 vertical bars decreasing-increasing-decreasing in height,
// matching icon-source.svg. Heights as % of the canvas height so
// the same view scales from 14pt (lock-screen) to 40pt (home).
struct WaveformLogo: View {
    var color: Color = TEXT_HI
    private let bars: [CGFloat] = [
        0.18, 0.36, 0.56, 0.76, 0.92,
        1.00,
        0.92, 0.76, 0.56, 0.36, 0.18
    ]

    var body: some View {
        GeometryReader { geo in
            let h    = geo.size.height
            let w    = geo.size.width
            let n    = CGFloat(bars.count)
            let gap  = w * 0.025
            let bw   = (w - gap * (n - 1)) / n
            HStack(spacing: gap) {
                ForEach(0..<bars.count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: bw / 2, style: .continuous)
                        .fill(color)
                        .frame(width: bw, height: h * bars[i])
                }
            }
            .frame(width: w, height: h, alignment: .center)
        }
    }
}

// ═════════════════════════════════════════════════════════
// MARK: - Home-screen widget views
// ═════════════════════════════════════════════════════════

struct TaskRow: View {
    let task: TaskItem
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .strokeBorder(CHECK_LINE, lineWidth: 1.6)
                .frame(width: 16, height: 16)
            Text(task.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(TEXT_HI)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(CARD)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(CARD_LINE, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct HomeScreenView: View {
    let entry: TaskEntry
    @Environment(\.widgetFamily) var family
    var openTasks: [TaskItem] { entry.tasks.filter { !$0.done } }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 8) {
                Text("\(openTasks.count)")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(ACCENT)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(ACCENT_LO))
                    .overlay(Capsule().strokeBorder(ACCENT.opacity(0.35), lineWidth: 0.6))
                Spacer()
                Text("המשימות שלי")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(TEXT_HI)
                    .tracking(-0.2)
            }

            Rectangle()
                .fill(LinearGradient(
                    colors: [ACCENT.opacity(0.45), ACCENT.opacity(0)],
                    startPoint: .trailing, endPoint: .leading
                ))
                .frame(height: 1)
                .padding(.bottom, 2)

            if openTasks.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Text("✓")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundColor(ACCENT)
                    Text("הכל בוצע")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(TEXT_LO)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(openTasks.prefix(rowLimit)) { task in
                    Link(destination: URL(string: "ravidstudio://task/\(task.id)")!) {
                        TaskRow(task: task)
                    }
                }
                if openTasks.count > rowLimit {
                    Text("עוד \(openTasks.count - rowLimit) משימות •••")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(TEXT_LO)
                        .padding(.top, 2)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .environment(\.layoutDirection, .rightToLeft)
        .widgetBackground(homeBackground)
    }

    private var rowLimit: Int {
        switch family {
        case .systemSmall:  return 2
        case .systemMedium: return 4
        case .systemLarge:  return 8
        default:            return 4
        }
    }

    private var homeBackground: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [BG_TOP, BG_BOT]),
                startPoint: .topTrailing, endPoint: .bottomLeading
            )
            LinearGradient(
                colors: [Color.white.opacity(0.05), Color.clear],
                startPoint: .top, endPoint: .center
            )
        }
    }
}

// ═════════════════════════════════════════════════════════
// MARK: - Lock-screen widget views (iOS 16+)
// ═════════════════════════════════════════════════════════

// Rectangular lock-screen widget — waveform logo on the right,
// "אליאור רביד" + "N משימות פתוחות" on the left. iOS renders the
// whole thing monochrome with the wallpaper-tinted accent, so we
// just need clean contrast (no colours of our own).
@available(iOS 16.0, *)
struct LockScreenRectangularView: View {
    let entry: TaskEntry
    var openCount: Int { entry.tasks.filter { !$0.done }.count }

    var body: some View {
        HStack(spacing: 10) {
            WaveformLogo(color: .primary)
                .frame(width: 28, height: 28)
                .widgetAccentable()
            VStack(alignment: .trailing, spacing: 2) {
                Text("אליאור רביד")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.secondary)
                Text(taskText)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .environment(\.layoutDirection, .rightToLeft)
        .widgetURL(URL(string: "ravidstudio://"))
        .widgetBackground(Color.clear)
    }

    private var taskText: String {
        switch openCount {
        case 0: return "אין משימות פתוחות"
        case 1: return "משימה 1 פתוחה"
        default: return "\(openCount) משימות פתוחות"
        }
    }
}

// ═════════════════════════════════════════════════════════
// MARK: - Family router
// ═════════════════════════════════════════════════════════

struct TaskWidgetEntryView: View {
    let entry: TaskEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if #available(iOS 16.0, *), family == .accessoryRectangular {
            LockScreenRectangularView(entry: entry)
        } else {
            HomeScreenView(entry: entry)
        }
    }
}

// iOS 17+ requires .containerBackground(...) on widget views, but
// older versions don't have it. Shim it so the same view code
// compiles for both targets.
private extension View {
    @ViewBuilder
    func widgetBackground<Bg: View>(_ bg: Bg) -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(for: .widget) { bg }
        } else {
            self.background(bg)
        }
    }
}

// ═════════════════════════════════════════════════════════
// MARK: - Widget configuration
// ═════════════════════════════════════════════════════════

@main
struct TaskWidget: Widget {
    let kind: String = "TaskWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TaskProvider()) { entry in
            TaskWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("המשימות שלי")
        .description("המשימות הפתוחות שלך מאליאור רביד.")
        .supportedFamilies(supportedFamilies)
    }

    private var supportedFamilies: [WidgetFamily] {
        if #available(iOS 16.0, *) {
            return [
                .systemSmall, .systemMedium, .systemLarge,
                .accessoryRectangular
            ]
        }
        return [.systemSmall, .systemMedium, .systemLarge]
    }
}

// TaskWidget — iOS Home Screen widget showing the user's open tasks.
//
// Data flow:
//   index.html JS → TaskWidgetBridge plugin → UserDefaults(suiteName:
//   "group.com.ravidstudio.app").set("widget_tasks": "<json>") →
//   WidgetCenter.shared.reloadAllTimelines() → this file reads and
//   renders the latest list.
//
// The widget itself is read-only — tapping a task deep-links into the
// app (custom URL scheme handled by Capacitor's AppDelegate).

import WidgetKit
import SwiftUI

// Keep in sync with capacitor.config.json appId and the App Group
// declared in the entitlements files.
private let APP_GROUP_ID = "group.com.ravidstudio.app"
private let TASKS_KEY    = "widget_tasks"

// ── Palette ── matches the app's dark-wood theme but with strong
//    contrast so a glance at the home screen actually reads.
private let BG_TOP     = Color(red: 0.18, green: 0.12, blue: 0.07)  // deep wood
private let BG_BOT     = Color(red: 0.09, green: 0.06, blue: 0.03)  // near-black
private let ACCENT     = Color(red: 0.85, green: 0.62, blue: 0.40)  // cognac
private let ACCENT_LO  = Color(red: 0.85, green: 0.62, blue: 0.40).opacity(0.18)
private let TEXT_HI    = Color(red: 0.97, green: 0.93, blue: 0.86)  // cream
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

// ───── Views ─────

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

struct TaskWidgetEntryView: View {
    let entry: TaskEntry
    @Environment(\.widgetFamily) var family

    var openTasks: [TaskItem] { entry.tasks.filter { !$0.done } }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            // ── Header ──
            HStack(spacing: 8) {
                // Cognac pill with the open-task count
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

            // Thin accent rule under the header for a printed-card feel
            Rectangle()
                .fill(LinearGradient(
                    colors: [ACCENT.opacity(0.45), ACCENT.opacity(0)],
                    startPoint: .trailing, endPoint: .leading
                ))
                .frame(height: 1)
                .padding(.bottom, 2)

            // ── Body ──
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
        .widgetBackground(backgroundView)
    }

    private var rowLimit: Int {
        switch family {
        case .systemSmall:  return 2
        case .systemMedium: return 4
        case .systemLarge:  return 8
        default:            return 4
        }
    }

    private var backgroundView: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [BG_TOP, BG_BOT]),
                startPoint: .topTrailing, endPoint: .bottomLeading
            )
            // Faint inner highlight at the top so the surface reads
            // like leather/wood rather than a flat panel.
            LinearGradient(
                colors: [Color.white.opacity(0.05), Color.clear],
                startPoint: .top, endPoint: .center
            )
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

// ───── Widget configuration ─────

@main
struct TaskWidget: Widget {
    let kind: String = "TaskWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TaskProvider()) { entry in
            TaskWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("המשימות שלי")
        .description("המשימות הפתוחות שלך מאליאור רביד.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

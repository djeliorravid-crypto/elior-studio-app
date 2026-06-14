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

struct TaskWidgetEntryView: View {
    let entry: TaskEntry
    @Environment(\.widgetFamily) var family

    var openTasks: [TaskItem] { entry.tasks.filter { !$0.done } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("המשימות שלי")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(Color(red: 0.83, green: 0.65, blue: 0.45))
                Spacer()
                Text("\(openTasks.count)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 2)

            if openTasks.isEmpty {
                Spacer()
                HStack { Spacer(); Text("אין משימות פתוחות 🎉").font(.system(size: 13, weight: .medium)).foregroundColor(.secondary); Spacer() }
                Spacer()
            } else {
                ForEach(openTasks.prefix(rowLimit)) { task in
                    Link(destination: URL(string: "ravidstudio://task/\(task.id)")!) {
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .stroke(Color(red: 0.83, green: 0.65, blue: 0.45), lineWidth: 1.5)
                                .frame(width: 14, height: 14)
                                .padding(.top, 2)
                            Text(task.title)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .foregroundColor(.primary)
                            Spacer(minLength: 0)
                        }
                    }
                }
                if openTasks.count > rowLimit {
                    Text("+ עוד \(openTasks.count - rowLimit) משימות")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
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
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 0.22, green: 0.14, blue: 0.08),
                Color(red: 0.14, green: 0.09, blue: 0.04)
            ]),
            startPoint: .top, endPoint: .bottom
        )
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

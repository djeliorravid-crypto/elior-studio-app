// TaskWidget — data-driven WidgetKit extension.
//
// The Swift code is intentionally "dumb": every visible string, every
// colour, the empty-state copy, and the item list all come from a
// single JSON blob written by the app into the App Group container
// under the key "widget_payload". That means future content / colour
// tweaks (rename the header, swap the proximity palette, add more
// items, etc.) happen entirely on the JS side without rebuilding
// the IPA.
//
// Backward-compat: if "widget_payload" is missing (older app version
// that only writes the legacy "widget_tasks" array), we fall back to
// rendering a simple "המשימות שלי" list of open tasks.

import WidgetKit
import SwiftUI

private let APP_GROUP_ID = "group.com.ravidstudio.app"
private let PAYLOAD_KEY  = "widget_payload"
private let TASKS_KEY    = "widget_tasks"

// ═════════════════════════════════════════════════════════
// MARK: - Wire types
// ═════════════════════════════════════════════════════════

struct WidgetItem: Codable, Identifiable, Hashable {
    let id:       String
    let title:    String
    let subtitle: String?      // optional — e.g. "10:30"
    let dotColor: String?      // optional — hex string "#ef4444"
    let urgency:  Int?         // 0..3 — render hint, unused by default
}

struct WidgetPayload: Codable {
    let headerTitle:    String
    let headerSubtitle: String?
    let accent:         String?  // hex, default cognac
    let emptyTitle:     String?
    let emptyText:      String?
    let emptyEmoji:     String?  // e.g. "✓"
    // Lock-screen accessory text — fully driven by JS. If nil, the
    // widget falls back to a sensible default derived from items.
    let lockTitle:      String?
    let lockSubtitle:   String?
    let items:          [WidgetItem]
}

// Legacy task array (the v239 build still calls syncTasks).
struct LegacyTask: Codable, Identifiable, Hashable {
    let id:    String
    let title: String
    let done:  Bool
}

struct TaskEntry: TimelineEntry {
    let date:    Date
    let payload: WidgetPayload
}

// ═════════════════════════════════════════════════════════
// MARK: - Defaults / palette
// ═════════════════════════════════════════════════════════

private let DEFAULT_ACCENT      = Color(red: 0.85, green: 0.62, blue: 0.40)
private let TEXT_HI             = Color(red: 0.97, green: 0.93, blue: 0.86)
private let TEXT_LO             = Color(red: 0.97, green: 0.93, blue: 0.86).opacity(0.55)
private let CARD                = Color.white.opacity(0.06)
private let CARD_LINE           = Color.white.opacity(0.10)
private let BG_TOP              = Color(red: 0.18, green: 0.12, blue: 0.07)
private let BG_BOT              = Color(red: 0.09, green: 0.06, blue: 0.03)

private func hexColor(_ hex: String?, fallback: Color) -> Color {
    guard let raw = hex?.trimmingCharacters(in: CharacterSet(charactersIn: "# ")),
          raw.count == 6 || raw.count == 8 else { return fallback }
    var value: UInt64 = 0
    Scanner(string: raw).scanHexInt64(&value)
    let r, g, b, a: Double
    if raw.count == 8 {
        r = Double((value >> 24) & 0xFF) / 255
        g = Double((value >> 16) & 0xFF) / 255
        b = Double((value >>  8) & 0xFF) / 255
        a = Double( value        & 0xFF) / 255
    } else {
        r = Double((value >> 16) & 0xFF) / 255
        g = Double((value >>  8) & 0xFF) / 255
        b = Double( value        & 0xFF) / 255
        a = 1
    }
    return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
}

// ═════════════════════════════════════════════════════════
// MARK: - Timeline provider
// ═════════════════════════════════════════════════════════

struct TaskProvider: TimelineProvider {
    func placeholder(in context: Context) -> TaskEntry {
        TaskEntry(date: Date(), payload: WidgetPayload(
            headerTitle: "המשימות שלי",
            headerSubtitle: nil,
            accent: nil,
            emptyTitle: "טוען…",
            emptyText: nil,
            emptyEmoji: "•",
            lockTitle: nil,
            lockSubtitle: nil,
            items: []
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (TaskEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskEntry>) -> Void) {
        // Refresh every 5 minutes — the schedule's "due in 30/120 min"
        // colour bands need a tighter cadence than the old tasks list.
        // The app still calls WidgetCenter.reloadAllTimelines() on any
        // mutation so we don't usually wait this long.
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date()
        completion(Timeline(entries: [readEntry()], policy: .after(nextRefresh)))
    }

    private func readEntry() -> TaskEntry {
        let defaults = UserDefaults(suiteName: APP_GROUP_ID)
        // 1. Prefer the new generic payload.
        if let raw  = defaults?.string(forKey: PAYLOAD_KEY),
           let data = raw.data(using: .utf8),
           let pl   = try? JSONDecoder().decode(WidgetPayload.self, from: data) {
            return TaskEntry(date: Date(), payload: pl)
        }
        // 2. Fall back to the legacy tasks array for users on an older
        //    app build that only writes widget_tasks.
        if let raw  = defaults?.string(forKey: TASKS_KEY),
           let data = raw.data(using: .utf8),
           let arr  = try? JSONDecoder().decode([LegacyTask].self, from: data) {
            let items = arr.filter { !$0.done }.map { t in
                WidgetItem(id: t.id, title: t.title, subtitle: nil,
                           dotColor: nil, urgency: nil)
            }
            return TaskEntry(date: Date(), payload: WidgetPayload(
                headerTitle: "המשימות שלי",
                headerSubtitle: nil,
                accent: nil,
                emptyTitle: "הכל בוצע",
                emptyText: nil,
                emptyEmoji: "✓",
                lockTitle: nil,
                lockSubtitle: nil,
                items: items
            ))
        }
        // 3. Nothing yet (fresh install).
        return TaskEntry(date: Date(), payload: WidgetPayload(
            headerTitle: "המשימות שלי",
            headerSubtitle: nil,
            accent: nil,
            emptyTitle: "אין נתונים",
            emptyText: "פתח את האפליקציה כדי לסנכרן",
            emptyEmoji: "•",
            lockTitle: nil,
            lockSubtitle: nil,
            items: []
        ))
    }
}

// ═════════════════════════════════════════════════════════
// MARK: - Ravid Studio waveform logo
// ═════════════════════════════════════════════════════════

struct WaveformLogo: View {
    var color: Color = TEXT_HI
    private let bars: [CGFloat] = [
        0.18, 0.36, 0.56, 0.76, 0.92, 1.00,
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
// MARK: - Home-screen rows
// ═════════════════════════════════════════════════════════

struct WidgetRow: View {
    let item:   WidgetItem
    let accent: Color
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(hexColor(item.dotColor, fallback: accent))
                .frame(width: 10, height: 10)
                .shadow(color: hexColor(item.dotColor, fallback: accent).opacity(0.55),
                        radius: 3, x: 0, y: 0)
            if let sub = item.subtitle, !sub.isEmpty {
                Text(sub)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(accent)
                    .frame(minWidth: 40, alignment: .trailing)
            }
            Text(item.title)
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
    private var accent: Color { hexColor(entry.payload.accent, fallback: DEFAULT_ACCENT) }
    private var items: [WidgetItem] { entry.payload.items }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 8) {
                Text("\(items.count)")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(accent.opacity(0.18)))
                    .overlay(Capsule().strokeBorder(accent.opacity(0.35), lineWidth: 0.6))
                Spacer()
                Text(entry.payload.headerTitle)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(TEXT_HI)
                    .tracking(-0.2)
            }

            Rectangle()
                .fill(LinearGradient(
                    colors: [accent.opacity(0.45), accent.opacity(0)],
                    startPoint: .trailing, endPoint: .leading
                ))
                .frame(height: 1)
                .padding(.bottom, 2)

            if items.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Text(entry.payload.emptyEmoji ?? "•")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundColor(accent)
                    Text(entry.payload.emptyTitle ?? "")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(TEXT_LO)
                    if let txt = entry.payload.emptyText, !txt.isEmpty {
                        Text(txt)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(TEXT_LO)
                    }
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(items.prefix(rowLimit)) { item in
                    Link(destination: URL(string: "ravidstudio://item/\(item.id)")!) {
                        WidgetRow(item: item, accent: accent)
                    }
                }
                if items.count > rowLimit {
                    Text("עוד \(items.count - rowLimit) פריטים •••")
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
// MARK: - Lock-screen rectangular widget (iOS 16+)
// ═════════════════════════════════════════════════════════

@available(iOS 16.0, *)
struct LockScreenRectangularView: View {
    let entry: TaskEntry

    // Top + bottom lines. JS pushes lockTitle / lockSubtitle directly,
    // so changing what shows here in the future is a pure JS edit.
    // Fallbacks below cover the case where the app hasn't sent the
    // explicit lock fields yet (e.g. very old version writing only
    // the legacy tasks key).
    var topLine: String {
        if let s = entry.payload.lockTitle, !s.isEmpty { return s }
        // Default: first item's title + time, or empty-state title.
        if let first = entry.payload.items.first {
            if let sub = first.subtitle, !sub.isEmpty { return "\(sub) · \(first.title)" }
            return first.title
        }
        return entry.payload.emptyTitle ?? "פנוי"
    }
    var bottomLine: String {
        if let s = entry.payload.lockSubtitle, !s.isEmpty { return s }
        let n = entry.payload.items.count
        switch n {
        case 0:  return "אין פעילויות מתוכננות"
        case 1:  return "הפעילות הקרובה"
        default: return "ועוד \(n - 1) פעילויות היום"
        }
    }
    var body: some View {
        HStack(spacing: 10) {
            WaveformLogo(color: .primary)
                .frame(width: 28, height: 28)
                .widgetAccentable()
            VStack(alignment: .trailing, spacing: 2) {
                Text(topLine)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(.trailing)
                Text(bottomLine)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        // Crisp light outline so the widget reads as its own object
        // against a busy wallpaper. iOS renders this in vibrant mode
        // (so it picks up the wallpaper tint rather than pure white),
        // which is the Apple-native look for accessory widgets.
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.85), lineWidth: 1.2)
        )
        .environment(\.layoutDirection, .rightToLeft)
        .widgetURL(URL(string: "ravidstudio://"))
        .widgetBackground(Color.clear)
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
        .configurationDisplayName("אליאור רביד")
        .description("הלוז של היום (או המשימות הפתוחות) — מתעדכן אוטומטית.")
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

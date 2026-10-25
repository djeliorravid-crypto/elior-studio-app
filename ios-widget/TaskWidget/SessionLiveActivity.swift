// SessionLiveActivity — the next session on the Dynamic Island and the
// lock screen. One timer that counts DOWN to the start and then UP
// (elapsed) from it — SwiftUI's .timer style does both by itself, so it
// stays right even when the app is closed. A thin bar fills start…end.

import ActivityKit
import WidgetKit
import SwiftUI

private let NAVY   = Color(red: 0.08, green: 0.10, blue: 0.24)
private let ACCENT = Color(red: 0.66, green: 0.72, blue: 1.0)
private let MINT   = Color(red: 0.66, green: 0.89, blue: 0.77)

private struct Mark: View {
    var body: some View {
        Image(systemName: "waveform")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(ACCENT)
    }
}

private struct SessionTimer: View {
    let start: Date
    let size: CGFloat
    var body: some View {
        Text(start, style: .timer)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundColor(.white)
            .multilineTextAlignment(.trailing)
    }
}

private struct Bar: View {
    let state: SessionAttributes.ContentState
    var body: some View {
        ProgressView(timerInterval: state.start...state.end, countsDown: false) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .tint(MINT)
    }
}

struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionAttributes.self) { ctx in
            // Lock screen / banner
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    Mark()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ctx.state.title).font(.system(size: 16, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                        Text(ctx.state.subtitle).font(.system(size: 13)).foregroundColor(.white.opacity(0.65)).lineLimit(1)
                    }
                    Spacer()
                    SessionTimer(start: ctx.state.start, size: 26).frame(maxWidth: 110)
                }
                Bar(state: ctx.state)
            }
            .padding(16)
            .activityBackgroundTint(NAVY)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Mark().padding(.leading, 6).padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    SessionTimer(start: ctx.state.start, size: 22).frame(maxWidth: 100).padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(ctx.state.title).font(.system(size: 15, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(ctx.state.subtitle).font(.system(size: 13)).foregroundColor(.white.opacity(0.65)).lineLimit(1)
                        Bar(state: ctx.state)
                    }
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                Mark()
            } compactTrailing: {
                Text(ctx.state.start, style: .timer)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(ACCENT)
                    .frame(maxWidth: 52)
            } minimal: {
                Mark()
            }
            .keylineTint(ACCENT)
        }
    }
}

@main
struct MaestroWidgets: WidgetBundle {
    var body: some Widget {
        TaskWidget()
        SessionLiveActivity()
    }
}

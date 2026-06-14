// TaskWidgetBridge — minimal Capacitor plugin that lets the web layer
// push task data into the App Group container the Widget reads from.
//
// Exposed methods:
//   syncTasks({ tasks: [{ id, title, done }] }) — write JSON +
//     trigger a widget timeline reload so the new list shows up
//     within seconds, not the 15-minute default refresh window.
//
// Wired in JS from index.html as:
//   Capacitor.Plugins.TaskWidgetBridge.syncTasks({ tasks: [...] })
//
// The plugin is registered manually via the Pods/Capacitor bridge
// because we ship it as a local source target rather than a npm
// package (no podspec to auto-discover). The codemagic.yaml step
// that injects this file into the Xcode project also writes a tiny
// .m bridge so Capacitor sees the @objc methods.

import Foundation
import Capacitor
import WidgetKit

private let APP_GROUP_ID = "group.com.ravidstudio.app"
private let TASKS_KEY    = "widget_tasks"

@objc(TaskWidgetBridgePlugin)
public class TaskWidgetBridgePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier  = "TaskWidgetBridgePlugin"
    public let jsName      = "TaskWidgetBridge"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "syncTasks", returnType: CAPPluginReturnPromise)
    ]

    @objc func syncTasks(_ call: CAPPluginCall) {
        guard let arr = call.getArray("tasks") else {
            call.reject("Missing 'tasks' array")
            return
        }

        // Normalise — only keep id/title/done strings so we control
        // the schema the widget decodes against.
        var clean: [[String: Any]] = []
        for item in arr {
            guard let dict = item as? [String: Any],
                  let id    = dict["id"]    as? String,
                  let title = dict["title"] as? String else { continue }
            let done = (dict["done"] as? Bool) ?? false
            clean.append([
                "id":    id,
                "title": title,
                "done":  done
            ])
        }

        guard let json = try? JSONSerialization.data(withJSONObject: clean, options: []),
              let str  = String(data: json, encoding: .utf8) else {
            call.reject("JSON encode failed")
            return
        }

        guard let defaults = UserDefaults(suiteName: APP_GROUP_ID) else {
            call.reject("App Group '\(APP_GROUP_ID)' not accessible — entitlement missing?")
            return
        }
        defaults.set(str, forKey: TASKS_KEY)

        // Nudge WidgetKit so the home-screen widget refreshes within
        // a second instead of waiting for the 15-minute timeline tick.
        if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
        }

        call.resolve([
            "count":   clean.count,
            "synced":  true
        ])
    }
}

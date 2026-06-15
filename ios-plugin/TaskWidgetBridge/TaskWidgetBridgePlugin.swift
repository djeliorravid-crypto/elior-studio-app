// TaskWidgetBridge — Capacitor bridge that pushes data the widget
// reads from the App Group UserDefaults container.
//
// Two methods, both for forward-compat:
//
//   syncTasks({ tasks: [{id,title,done}] })
//     LEGACY — writes the old "widget_tasks" key. Older widget
//     binaries in user devices still read this on iOS until they
//     get a fresh build. Keep around so the moment a user installs
//     a new IPA, the previous old widget keeps working until iOS
//     refreshes its timeline.
//
//   syncPayload({ payload: { headerTitle, items, accent, ... } })
//     NEW — writes the "widget_payload" key as a generic JSON blob.
//     The Swift widget renderer treats EVERY visible string + colour
//     as data, so future content/styling tweaks happen entirely in
//     JS without rebuilding the IPA.
//
// In both cases we kick WidgetCenter so the home/lock screen
// widgets refresh within seconds rather than waiting for the
// 15-min default timeline tick.

import Foundation
import Capacitor
import WidgetKit

private let APP_GROUP_ID = "group.com.ravidstudio.app"
private let TASKS_KEY    = "widget_tasks"
private let PAYLOAD_KEY  = "widget_payload"

@objc(TaskWidgetBridgePlugin)
public class TaskWidgetBridgePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier  = "TaskWidgetBridgePlugin"
    public let jsName      = "TaskWidgetBridge"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "syncTasks",   returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "syncPayload", returnType: CAPPluginReturnPromise)
    ]

    @objc func syncTasks(_ call: CAPPluginCall) {
        guard let arr = call.getArray("tasks") else {
            call.reject("Missing 'tasks' array")
            return
        }
        var clean: [[String: Any]] = []
        for item in arr {
            guard let dict = item as? [String: Any],
                  let id    = dict["id"]    as? String,
                  let title = dict["title"] as? String else { continue }
            let done = (dict["done"] as? Bool) ?? false
            clean.append(["id": id, "title": title, "done": done])
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
        _reloadWidgets()
        call.resolve(["count": clean.count, "synced": true])
    }

    @objc func syncPayload(_ call: CAPPluginCall) {
        guard let payload = call.getObject("payload") else {
            call.reject("Missing 'payload' object")
            return
        }
        guard JSONSerialization.isValidJSONObject(payload),
              let json = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let str  = String(data: json, encoding: .utf8) else {
            call.reject("Payload is not valid JSON")
            return
        }
        guard let defaults = UserDefaults(suiteName: APP_GROUP_ID) else {
            call.reject("App Group '\(APP_GROUP_ID)' not accessible — entitlement missing?")
            return
        }
        defaults.set(str, forKey: PAYLOAD_KEY)
        _reloadWidgets()
        call.resolve(["synced": true])
    }

    private func _reloadWidgets() {
        if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

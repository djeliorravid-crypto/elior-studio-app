// TaskWidgetBridge — Capacitor bridge that pushes data the widget
// reads from the App Group UserDefaults container.
//
// Exposed methods:
//
//   syncTasks({ tasks: [{id,title,done}] })
//     LEGACY — writes the old "widget_tasks" key. Older widget
//     binaries in user devices still read this on iOS until they
//     get a fresh build.
//
//   syncPayload({ payload: { headerTitle, items, accent, ... } })
//     Data-driven widget feed — the Swift widget is a "dumb"
//     renderer driven entirely by this JSON, so future widget
//     tweaks (text, colours, item count) don't need rebuilds.
//
//   setBadge({ count })
//     Sets the red number on the app icon. iOS 16+ uses
//     UNUserNotificationCenter.setBadgeCount; older uses the
//     UIApplication property.
//
//   consumePendingShortcut()
//     Returns and clears any quick-action shortcut type that was
//     pending from a cold launch (stashed in UserDefaults by the
//     AppDelegate). JS calls this on startup so we can dispatch
//     the right "add new …" modal.

import Foundation
import UIKit
import Capacitor
import WidgetKit
import UserNotifications

private let APP_GROUP_ID  = "group.com.ravidstudio.app"
private let TASKS_KEY     = "widget_tasks"
private let PAYLOAD_KEY   = "widget_payload"
private let SHORTCUT_KEY  = "pending_shortcut"

@objc(TaskWidgetBridgePlugin)
public class TaskWidgetBridgePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier  = "TaskWidgetBridgePlugin"
    public let jsName      = "TaskWidgetBridge"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "syncTasks",              returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "syncPayload",            returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setBadge",               returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "consumePendingShortcut", returnType: CAPPluginReturnPromise)
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

    @objc func setBadge(_ call: CAPPluginCall) {
        let count = max(0, call.getInt("count") ?? 0)
        DispatchQueue.main.async {
            if #available(iOS 16.0, *) {
                UNUserNotificationCenter.current().setBadgeCount(count) { _ in }
            } else {
                UIApplication.shared.applicationIconBadgeNumber = count
            }
            call.resolve(["badge": count])
        }
    }

    @objc func consumePendingShortcut(_ call: CAPPluginCall) {
        let defaults = UserDefaults.standard
        let type = defaults.string(forKey: SHORTCUT_KEY) ?? ""
        if !type.isEmpty {
            defaults.removeObject(forKey: SHORTCUT_KEY)
        }
        call.resolve(["type": type])
    }

    private func _reloadWidgets() {
        if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

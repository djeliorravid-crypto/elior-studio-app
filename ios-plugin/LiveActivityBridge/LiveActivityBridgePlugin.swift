// LiveActivityBridge — lets the web app put the next session on the
// Dynamic Island / lock screen (ActivityKit). Local Capacitor plugin,
// registered from BridgeViewController.capacitorDidLoad().
//
// Exposed methods:
//   available()                         → { ok: Bool }
//   start({ id, title, subtitle, start, end })   (start/end in ms)
//       — starts, or updates if an activity for that id is already running;
//         any other running session activity is ended first (one at a time)
//   end({ id })                         — ends that one now
//   endAll()                            — ends every session activity

import Foundation
import Capacitor
#if canImport(ActivityKit)
import ActivityKit
#endif

@objc(LiveActivityBridgePlugin)
public class LiveActivityBridgePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "LiveActivityBridgePlugin"
    public let jsName     = "LiveActivityBridge"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "available", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "start",     returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "end",       returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "endAll",    returnType: CAPPluginReturnPromise)
    ]

    @objc func available(_ call: CAPPluginCall) {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            call.resolve(["ok": ActivityAuthorizationInfo().areActivitiesEnabled])
            return
        }
        #endif
        call.resolve(["ok": false])
    }

    @objc func start(_ call: CAPPluginCall) {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            guard let id = call.getString("id"), !id.isEmpty,
                  let startMs = call.getDouble("start"), let endMs = call.getDouble("end") else {
                call.reject("missing id/start/end"); return
            }
            let s = Date(timeIntervalSince1970: startMs / 1000)
            var e = Date(timeIntervalSince1970: endMs / 1000)
            if e <= s { e = s.addingTimeInterval(3600) }
            let state = SessionAttributes.ContentState(
                title: call.getString("title") ?? "סשן",
                subtitle: call.getString("subtitle") ?? "",
                short: call.getString("short") ?? "סשן",
                start: s, end: e)
            let content = ActivityContent(state: state, staleDate: e.addingTimeInterval(15 * 60))
            Task {
                var kept = false
                for a in Activity<SessionAttributes>.activities {
                    if a.attributes.sessionId == id && !kept {
                        await a.update(content); kept = true
                    } else {
                        await a.end(nil, dismissalPolicy: .immediate)
                    }
                }
                if kept { call.resolve(["ok": true, "updated": true]); return }
                do {
                    _ = try Activity.request(attributes: SessionAttributes(sessionId: id), content: content, pushType: nil)
                    call.resolve(["ok": true])
                } catch {
                    call.resolve(["ok": false, "error": String(describing: error)])
                }
            }
            return
        }
        #endif
        call.resolve(["ok": false, "error": "unsupported"])
    }

    @objc func end(_ call: CAPPluginCall) {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            let id = call.getString("id") ?? ""
            Task {
                for a in Activity<SessionAttributes>.activities where id.isEmpty || a.attributes.sessionId == id {
                    await a.end(nil, dismissalPolicy: .immediate)
                }
                call.resolve(["ok": true])
            }
            return
        }
        #endif
        call.resolve(["ok": false])
    }

    @objc func endAll(_ call: CAPPluginCall) {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            Task {
                for a in Activity<SessionAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
                call.resolve(["ok": true])
            }
            return
        }
        #endif
        call.resolve(["ok": false])
    }
}

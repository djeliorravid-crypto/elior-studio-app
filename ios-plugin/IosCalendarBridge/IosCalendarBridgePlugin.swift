// IosCalendarBridge — minimal Capacitor plugin wrapping iOS EventKit.
//
// Why this exists: Google OAuth refuses to run inside a WebView,
// and every workaround we tried (Device Flow, Web flow with
// redirect URI, custom URL scheme bounce) bumped into Google's
// configuration quirks. EventKit lets us bypass Google entirely:
// write events to the user's native iOS Calendar, and any
// calendar account configured in iOS Settings → Mail (Google,
// iCloud, etc.) gets sync'd by the OS in the background.
//
// Exposed methods:
//   requestAccess()            → user-facing iOS permission prompt
//   listCalendars()            → enumerate writable calendars so JS
//                                can pick where to save (or auto-
//                                pick the Google one)
//   getDefaultCalendarId()     → the system default (usually the
//                                Google account if synced)
//   createEvent(...)           → write an event, returns its
//                                EKEvent.eventIdentifier
//   updateEvent(eventId, ...)
//   deleteEvent(eventId)
//
// Wired in JS via Capacitor.Plugins.IosCalendar.<method>.

import Foundation
import Capacitor
import EventKit

@objc(IosCalendarBridgePlugin)
public class IosCalendarBridgePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier  = "IosCalendarBridgePlugin"
    public let jsName      = "IosCalendar"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "requestAccess",         returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "listCalendars",         returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getDefaultCalendarId",  returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "createEvent",           returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "updateEvent",           returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "deleteEvent",           returnType: CAPPluginReturnPromise)
    ]

    private let store = EKEventStore()

    @objc func requestAccess(_ call: CAPPluginCall) {
        let cb: (Bool, Error?) -> Void = { granted, _ in
            DispatchQueue.main.async { call.resolve(["granted": granted]) }
        }
        if #available(iOS 17.0, *) {
            store.requestFullAccessToEvents(completion: cb)
        } else {
            store.requestAccess(to: .event, completion: cb)
        }
    }

    @objc func listCalendars(_ call: CAPPluginCall) {
        let cals = store.calendars(for: .event)
        let mapped: [[String: Any]] = cals.map { c in
            return [
                "id":           c.calendarIdentifier,
                "title":        c.title,
                "source":       c.source.title,
                "type":         _sourceTypeString(c.source.sourceType),
                "allowsModify": c.allowsContentModifications,
                "color":        _colorHex(c.cgColor)
            ]
        }
        call.resolve(["calendars": mapped])
    }

    @objc func getDefaultCalendarId(_ call: CAPPluginCall) {
        // Prefer a Google-sourced calendar (so writes flow back to
        // Google in the background); otherwise use whatever iOS
        // marked as the user's default.
        let cals = store.calendars(for: .event).filter { $0.allowsContentModifications }
        if let google = cals.first(where: { $0.source.title.lowercased().contains("google") || $0.source.title.lowercased().contains("gmail") }) {
            call.resolve(["id": google.calendarIdentifier, "source": google.source.title, "title": google.title])
            return
        }
        if let def = store.defaultCalendarForNewEvents {
            call.resolve(["id": def.calendarIdentifier, "source": def.source.title, "title": def.title])
            return
        }
        if let first = cals.first {
            call.resolve(["id": first.calendarIdentifier, "source": first.source.title, "title": first.title])
            return
        }
        call.reject("No writable calendar found")
    }

    @objc func createEvent(_ call: CAPPluginCall) {
        guard let title      = call.getString("title"),
              let dateStr    = call.getString("date"),    // YYYY-MM-DD
              let timeStr    = call.getString("time") else {
            call.reject("Missing title / date / time")
            return
        }
        let calendarId = call.getString("calendarId") ?? ""
        let durationMin = call.getInt("durationMinutes") ?? 60

        let chosen: EKCalendar?
        if !calendarId.isEmpty, let c = store.calendar(withIdentifier: calendarId) {
            chosen = c
        } else {
            chosen = store.calendars(for: .event)
                .filter { $0.allowsContentModifications }
                .first(where: { $0.source.title.lowercased().contains("google") || $0.source.title.lowercased().contains("gmail") })
                ?? store.defaultCalendarForNewEvents
        }
        guard let calendar = chosen else {
            call.reject("No writable calendar")
            return
        }

        guard let start = _parseDate(dateStr, timeStr) else {
            call.reject("Invalid date/time")
            return
        }

        let event = EKEvent(eventStore: store)
        event.title     = title
        event.startDate = start
        event.endDate   = start.addingTimeInterval(TimeInterval(durationMin * 60))
        event.calendar  = calendar
        if let notes = call.getString("notes"), !notes.isEmpty {
            event.notes = notes
        }
        do {
            try store.save(event, span: .thisEvent, commit: true)
            call.resolve([
                "id":     event.eventIdentifier ?? "",
                "source": calendar.source.title
            ])
        } catch {
            call.reject("Save failed: \(error.localizedDescription)")
        }
    }

    @objc func updateEvent(_ call: CAPPluginCall) {
        guard let eventId = call.getString("eventId"),
              let event   = store.event(withIdentifier: eventId) else {
            call.reject("Event not found")
            return
        }
        if let title = call.getString("title") { event.title = title }
        let dateStr = call.getString("date")
        let timeStr = call.getString("time")
        if let dateStr = dateStr, let timeStr = timeStr,
           let start = _parseDate(dateStr, timeStr) {
            event.startDate = start
            let dur = TimeInterval((call.getInt("durationMinutes") ?? 60) * 60)
            event.endDate = start.addingTimeInterval(dur)
        }
        if let notes = call.getString("notes") { event.notes = notes }
        do {
            try store.save(event, span: .thisEvent, commit: true)
            call.resolve(["id": event.eventIdentifier ?? ""])
        } catch {
            call.reject("Update failed: \(error.localizedDescription)")
        }
    }

    @objc func deleteEvent(_ call: CAPPluginCall) {
        guard let eventId = call.getString("eventId"),
              let event   = store.event(withIdentifier: eventId) else {
            // Not finding an event isn't an error from the caller's
            // perspective — they already deleted it locally; the
            // remote side might just be stale.
            call.resolve(["deleted": false])
            return
        }
        do {
            try store.remove(event, span: .thisEvent, commit: true)
            call.resolve(["deleted": true])
        } catch {
            call.reject("Delete failed: \(error.localizedDescription)")
        }
    }

    // ─── helpers ───
    private func _parseDate(_ date: String, _ time: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        f.timeZone   = TimeZone(identifier: "Asia/Jerusalem")
        return f.date(from: date + "T" + time)
    }

    private func _sourceTypeString(_ t: EKSourceType) -> String {
        switch t {
        case .local:        return "local"
        case .exchange:     return "exchange"
        case .calDAV:       return "caldav"
        case .mobileMe:     return "mobileme"
        case .subscribed:   return "subscribed"
        case .birthdays:    return "birthdays"
        @unknown default:   return "other"
        }
    }

    private func _colorHex(_ cg: CGColor?) -> String {
        guard let c = cg, let comps = c.components, comps.count >= 3 else { return "" }
        let r = Int((comps[0]) * 255), g = Int((comps[1]) * 255), b = Int((comps[2]) * 255)
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}

// HealthKitBridge — minimal Capacitor plugin reading daily step
// totals from Apple Health (HealthKit). Self-contained (no npm
// dependency) so it works on Capacitor 8's SPM-based plugin pipeline,
// same pattern as BiometricBridge / IosCalendarBridge.
//
// Exposed methods:
//   available()            → { available: Bool }
//   requestAuth()          → { granted: Bool }   (iOS shows the Health
//                            permission sheet on first call only)
//   getDailySteps({ days }) → { days: [{ date: "YYYY-MM-DD", steps: Int }] }
//
// Read-only — we never write to Health. Requires:
//   • NSHealthShareUsageDescription in Info.plist (codemagic.yaml)
//   • com.apple.developer.healthkit entitlement (App.entitlements)
//   • HealthKit capability enabled on the App ID in the developer portal
//
// Registered with the bridge from BridgeViewController.swift's
// capacitorDidLoad() override — Capacitor 8 doesn't auto-discover
// local plugins, only those in node_modules.

import Foundation
import Capacitor
import HealthKit

@objc(HealthKitBridgePlugin)
public class HealthKitBridgePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier  = "HealthKitBridgePlugin"
    public let jsName      = "HealthKitBridge"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "available",     returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "requestAuth",   returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getDailySteps", returnType: CAPPluginReturnPromise)
    ]

    private let store = HKHealthStore()

    @objc func available(_ call: CAPPluginCall) {
        call.resolve(["available": HKHealthStore.isHealthDataAvailable()])
    }

    @objc func requestAuth(_ call: CAPPluginCall) {
        guard HKHealthStore.isHealthDataAvailable(),
              let steps = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            call.resolve(["granted": false])
            return
        }
        store.requestAuthorization(toShare: nil, read: [steps]) { ok, err in
            // Note: for read-only types Apple never reveals whether the
            // user actually granted access — `ok` just means the sheet
            // flow completed. Queries on denied data return zeros.
            DispatchQueue.main.async {
                call.resolve(["granted": ok && err == nil])
            }
        }
    }

    @objc func getDailySteps(_ call: CAPPluginCall) {
        guard HKHealthStore.isHealthDataAvailable(),
              let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            call.reject("HealthKit unavailable on this device")
            return
        }
        let days = max(1, min(90, call.getInt("days") ?? 14))
        let cal = Calendar.current
        let now = Date()
        guard let startRaw = cal.date(byAdding: .day, value: -(days - 1), to: now) else {
            call.reject("Date math failed")
            return
        }
        let startDay = cal.startOfDay(for: startRaw)
        let predicate = HKQuery.predicateForSamples(withStart: startDay, end: now, options: .strictStartDate)
        var interval = DateComponents()
        interval.day = 1

        let query = HKStatisticsCollectionQuery(
            quantityType: stepsType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum,
            anchorDate: startDay,
            intervalComponents: interval
        )
        query.initialResultsHandler = { _, results, error in
            if let error = error {
                DispatchQueue.main.async { call.reject(error.localizedDescription) }
                return
            }
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            fmt.timeZone = TimeZone.current
            var out: [[String: Any]] = []
            results?.enumerateStatistics(from: startDay, to: now) { stat, _ in
                let steps = stat.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
                out.append(["date": fmt.string(from: stat.startDate), "steps": Int(steps.rounded())])
            }
            DispatchQueue.main.async { call.resolve(["days": out]) }
        }
        store.execute(query)
    }
}

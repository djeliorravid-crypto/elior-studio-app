// BiometricBridge — minimal Capacitor plugin wrapping iOS LAContext
// for Face ID / Touch ID auth. Self-contained (no npm dependency) so
// it works on Capacitor 8's SPM-based plugin pipeline.
//
// Exposed methods:
//   authenticate({ reason }) → resolve on success, reject on failure
//
// Wired in JS as:
//   Capacitor.Plugins.BiometricBridge.authenticate({ reason: "פתח את האפליקציה" })
//
// Registered with the bridge from BridgeViewController.swift's
// capacitorDidLoad() override — Capacitor 8 doesn't auto-discover
// local plugins, only those in node_modules.

import Foundation
import Capacitor
import LocalAuthentication

@objc(BiometricBridgePlugin)
public class BiometricBridgePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier  = "BiometricBridgePlugin"
    public let jsName      = "BiometricBridge"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "authenticate", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "isAvailable",  returnType: CAPPluginReturnPromise)
    ]

    @objc func isAvailable(_ call: CAPPluginCall) {
        let context = LAContext()
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        )
        call.resolve([
            "available": canEvaluate,
            "biometryType": _biometryTypeName(context.biometryType)
        ])
    }

    @objc func authenticate(_ call: CAPPluginCall) {
        let reason = call.getString("reason") ?? "אמת את עצמך כדי להמשיך"

        let context = LAContext()
        context.localizedCancelTitle = call.getString("cancelTitle") ?? "בטל"

        // .deviceOwnerAuthentication falls back to device passcode if
        // Face ID isn't enrolled or fails too many times — safest
        // option so the user can't lock themselves out.
        let policy: LAPolicy = .deviceOwnerAuthentication

        // canEvaluatePolicy first so we surface a clean error if
        // there's no biometry/passcode at all instead of a generic
        // "auth failed".
        var canEvalError: NSError?
        guard context.canEvaluatePolicy(policy, error: &canEvalError) else {
            call.reject(
                canEvalError?.localizedDescription ?? "Biometric auth unavailable",
                String(canEvalError?.code ?? -1)
            )
            return
        }

        context.evaluatePolicy(policy, localizedReason: reason) { success, evalError in
            DispatchQueue.main.async {
                if success {
                    call.resolve(["authenticated": true])
                } else {
                    let code = (evalError as NSError?)?.code ?? -1
                    call.reject(
                        evalError?.localizedDescription ?? "Authentication failed",
                        String(code)
                    )
                }
            }
        }
    }

    private func _biometryTypeName(_ type: LABiometryType) -> String {
        switch type {
        case .faceID:  return "faceId"
        case .touchID: return "touchId"
        default:       return "none"
        }
    }
}

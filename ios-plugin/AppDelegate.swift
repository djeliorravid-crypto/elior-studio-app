// Custom AppDelegate — replaces the boilerplate one Capacitor
// generates with `cap add ios`. Adds two iOS lifecycle handlers
// for quick actions (the long-press-on-icon shortcuts declared
// in Info.plist):
//
//   • application(didFinishLaunchingWithOptions:)
//     COLD launch via shortcut: stash the type in standard
//     UserDefaults so the JS layer can pick it up on startup via
//     Capacitor.Plugins.TaskWidgetBridge.consumePendingShortcut().
//
//   • application(performActionFor:completionHandler:)
//     WARM launch via shortcut (app still in memory): post a
//     NotificationCenter notification that BridgeViewController
//     listens for and forwards to JS as a CustomEvent.
//
// All the original Capacitor delegate methods (URL open,
// userActivity) are preserved unchanged.

import UIKit
import Capacitor

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        if let shortcut = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
            UserDefaults.standard.set(shortcut.type, forKey: "pending_shortcut")
        }
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {}
    func applicationDidEnterBackground(_ application: UIApplication) {}
    func applicationWillEnterForeground(_ application: UIApplication) {}
    func applicationDidBecomeActive(_ application: UIApplication) {}
    func applicationWillTerminate(_ application: UIApplication) {}

    // ── Remote push (APNs) — the Capacitor PushNotifications plugin
    //    listens for these NotificationCenter posts to hand the device
    //    token (or the failure) back to the JS layer. Required
    //    boilerplate per the plugin docs. ──
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationCenter.default.post(name: .capacitorDidRegisterForRemoteNotifications,
                                        object: deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationCenter.default.post(name: .capacitorDidFailToRegisterForRemoteNotifications,
                                        object: error)
    }

    func application(_ application: UIApplication,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        NotificationCenter.default.post(
            name: NSNotification.Name("RavidShortcut"),
            object: nil,
            userInfo: ["type": shortcutItem.type]
        )
        completionHandler(true)
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        // Forward the URL to the JS layer so the OAuth-callback handler
        // can pluck the ?code= off it. We still chain into Capacitor's
        // default proxy so other plugins (e.g. Share) can react too.
        NotificationCenter.default.post(
            name: NSNotification.Name("RavidUrlOpen"),
            object: nil,
            userInfo: ["url": url.absoluteString]
        )
        return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
    }

    // Capacitor 8 dropped the (continue userActivity:) overload — we
    // don't use universal links anyway, so stub it.
    func application(_ application: UIApplication,
                     continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        return false
    }
}

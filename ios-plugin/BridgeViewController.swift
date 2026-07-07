// BridgeViewController — subclass of CAPBridgeViewController whose
// only job is to register local Swift plugins with the Capacitor
// bridge. Capacitor 8 auto-discovers plugins that live in
// node_modules (via the SPM-generated registry), but local plugins
// in App/Plugins/ have to be wired up manually here.
//
// Codemagic flips Main.storyboard's initial-view-controller
// customClass from "CAPBridgeViewController" to this class so the
// app actually instantiates this subclass.
//
// Also forwards warm-launch quick-action taps from AppDelegate to
// the JS layer via a CustomEvent.

import UIKit
import Capacitor

@objc(BridgeViewController)
class BridgeViewController: CAPBridgeViewController {
    override open func capacitorDidLoad() {
        bridge?.registerPluginInstance(TaskWidgetBridgePlugin())
        bridge?.registerPluginInstance(BiometricBridgePlugin())
        bridge?.registerPluginInstance(IosCalendarBridgePlugin())
        bridge?.registerPluginInstance(HealthKitBridgePlugin())
        bridge?.registerPluginInstance(ContactsBridgePlugin())

        // Warm-launch quick action: AppDelegate posts to this
        // NotificationCenter name; we forward to JS so the right
        // modal opens immediately.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShortcutNotification(_:)),
            name: NSNotification.Name("RavidShortcut"),
            object: nil
        )
        // OAuth callback: the GitHub Pages /oauth-callback.html page
        // redirects to ravidstudio://oauth?code=… → AppDelegate posts
        // here → we hand the URL off to JS to exchange for tokens.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUrlOpenNotification(_:)),
            name: NSNotification.Name("RavidUrlOpen"),
            object: nil
        )
    }

    @objc func handleShortcutNotification(_ note: Notification) {
        guard let type = note.userInfo?["type"] as? String, !type.isEmpty else { return }
        let safe = type.replacingOccurrences(of: "'", with: "\\'")
        let js = "window.dispatchEvent(new CustomEvent('app-shortcut', { detail: { type: '\(safe)' } }))"
        bridge?.webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    @objc func handleUrlOpenNotification(_ note: Notification) {
        guard let url = note.userInfo?["url"] as? String, !url.isEmpty else { return }
        let safe = url.replacingOccurrences(of: "'", with: "\\'")
        let js = "window.dispatchEvent(new CustomEvent('app-url-open', { detail: { url: '\(safe)' } }))"
        bridge?.webView?.evaluateJavaScript(js, completionHandler: nil)
    }
}

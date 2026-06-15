// BridgeViewController — subclass of CAPBridgeViewController whose
// only job is to register local Swift plugins with the Capacitor
// bridge. Capacitor 8 auto-discovers plugins that live in
// node_modules (via the SPM-generated registry), but local plugins
// in App/Plugins/ have to be wired up manually here.
//
// Codemagic flips Main.storyboard's initial-view-controller
// customClass from "CAPBridgeViewController" to this class so the
// app actually instantiates this subclass.

import UIKit
import Capacitor

@objc(BridgeViewController)
class BridgeViewController: CAPBridgeViewController {
    override open func capacitorDidLoad() {
        bridge?.registerPluginInstance(TaskWidgetBridgePlugin())
        bridge?.registerPluginInstance(BiometricBridgePlugin())
    }
}

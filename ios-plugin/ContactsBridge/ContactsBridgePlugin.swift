// ContactsBridge — minimal Capacitor plugin reading the device
// address book (names + phone numbers only, read-only) so the
// WhatsApp inbox can show Elior's own contact names. Self-contained
// local plugin, same pattern as HealthKitBridge / BiometricBridge —
// no npm dependency, guaranteed compatible with the app's Capacitor
// version.
//
// Exposed method:
//   getAll() → { granted: Bool, contacts: [{ name: String, phones: [String] }] }
//
// Requires NSContactsUsageDescription in Info.plist (codemagic.yaml).
// Registered from BridgeViewController.capacitorDidLoad().

import Foundation
import Capacitor
import Contacts

@objc(ContactsBridgePlugin)
public class ContactsBridgePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier  = "ContactsBridgePlugin"
    public let jsName      = "ContactsBridge"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "getAll", returnType: CAPPluginReturnPromise)
    ]

    @objc func getAll(_ call: CAPPluginCall) {
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { granted, _ in
            guard granted else {
                DispatchQueue.main.async { call.resolve(["granted": false, "contacts": []]) }
                return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let keys = [CNContactGivenNameKey,
                            CNContactFamilyNameKey,
                            CNContactOrganizationNameKey,
                            CNContactPhoneNumbersKey] as [CNKeyDescriptor]
                let req = CNContactFetchRequest(keysToFetch: keys)
                var out: [[String: Any]] = []
                try? store.enumerateContacts(with: req) { c, _ in
                    let name = [c.givenName, c.familyName]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    let display = name.isEmpty ? c.organizationName : name
                    if display.isEmpty { return }
                    let phones = c.phoneNumbers.map { $0.value.stringValue }
                    if phones.isEmpty { return }
                    out.append(["name": display, "phones": phones])
                }
                DispatchQueue.main.async {
                    call.resolve(["granted": true, "contacts": out])
                }
            }
        }
    }
}

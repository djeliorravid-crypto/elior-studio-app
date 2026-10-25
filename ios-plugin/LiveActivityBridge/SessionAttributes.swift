// SessionAttributes — the Live Activity model shared by the app (which
// starts/updates/ends it) and the TaskWidget extension (which draws it on
// the Dynamic Island and the lock screen). Compiled into BOTH targets.

import Foundation
#if canImport(ActivityKit)
import ActivityKit

@available(iOS 16.1, *)
public struct SessionAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var title: String      // e.g. "סשן עם נועה"
        public var subtitle: String   // e.g. "14:00–16:00 · אולפן"
        public var start: Date        // the timer counts down to this, then up from it
        public var end: Date          // progress bar runs start…end
    }
    public var sessionId: String
}
#endif

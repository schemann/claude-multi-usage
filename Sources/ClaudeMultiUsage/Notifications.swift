import Foundation
import UserNotifications

/// Schedules a local notification at each window's reset time. Reschedules on
/// every poll; identifiers are keyed by account+window+resetTime so re-adding
/// the same reset is idempotent (no duplicate alerts).
enum ResetNotifier {
    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    /// Deliver a notification immediately (used for threshold warnings).
    static func fire(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: nil)
        )
    }

    static func schedule(for states: [AccountState]) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let stale = pending.map(\.identifier).filter { $0.hasPrefix("reset:") }
            center.removePendingNotificationRequests(withIdentifiers: stale)

            for state in states {
                guard let usage = state.usage else { continue }
                add(center, name: state.name, window: "5h", reset: usage.fiveHour?.resetsAtDate, accId: state.id)
                add(center, name: state.name, window: "7d", reset: usage.sevenDay?.resetsAtDate, accId: state.id)
                for limit in usage.modelLimits {
                    add(center, name: state.name, window: limit.modelName ?? "Modell", reset: limit.resetsAtDate, accId: state.id)
                }
            }
        }
    }

    private static func add(
        _ center: UNUserNotificationCenter,
        name: String,
        window: String,
        reset: Date?,
        accId: String
    ) {
        guard let reset, reset > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = L("notif.reset.title")
        content.body = L("notif.reset.body", name, window)
        content.sound = .default

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: reset
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let id = "reset:\(accId):\(window):\(Int(reset.timeIntervalSince1970))"
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}

import Foundation
import UserNotifications

/// Local notifications for release reminders: scheduled on the phone, no server needed.
enum Notifications {
    /// Ask once; later calls return the answer already given.
    @discardableResult
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default: return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    /// A reminder at 9am on release day.
    static func scheduleRelease(_ set: ExploreSet) async {
        guard let day = set.release, await requestPermission() else { return }
        var parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
        parts.hour = 9
        guard let fire = Calendar.current.date(from: parts), fire > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(set.name) is out today"
        content.body = "\(set.gameName) · see what's in it and what it's going for."
        content.sound = .default
        content.userInfo = ["set": set.slug]
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "release-\(set.slug)", content: content, trigger: trigger))
    }

    static func cancelRelease(_ slug: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["release-\(slug)"])
    }
}

import Foundation
import Observation
import SwiftUI
import UserNotifications

/// Local notifications for release reminders: scheduled on the phone, no server needed.
enum Notifications {
    /// Ask once; later calls return the answer already given. Never asked at launch: only when
    /// a price watch, a release reminder or a test notification first needs it, and then one
    /// line on why comes first (once), before Apple's own prompt.
    @discardableResult
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default:
            if !Onboarding.notificationsExplained {
                let go = await NotificationExplainer.shared.ask()
                Onboarding.notificationsExplained = true
                guard go else { return false }
            }
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
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

    /// Every Sunday at 6pm: your week's recap is ready. Set on the phone (no server), once
    /// notifications are allowed; replacing it each launch keeps a single one.
    static func scheduleWeeklyRecap() async {
        guard NotificationPrefs.recapOn else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["weekly-recap"])
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Your week in Lucent"
        content.body = "What moved, what you added and your best card this week."
        content.sound = .default
        content.userInfo = ["recap": true]
        var when = DateComponents()
        when.weekday = 1
        when.hour = 18
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "weekly-recap", content: content, trigger: trigger))
    }

    static func cancelRelease(_ slug: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["release-\(slug)"])
    }
}


/// Which notifications you want (user_state "notification-prefs", read by the website's daily
/// price check; anything missing counts as on). The weekly recap is set on the phone, so its
/// switch is also kept here.
struct NotificationPrefs: Codable, Equatable {
    var priceTargets = true
    var bigMoves = true
    var milestones = true
    var nearlyDone = true
    var weeklyRecap = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        priceTargets = try c.decodeIfPresent(Bool.self, forKey: .priceTargets) ?? true
        bigMoves = try c.decodeIfPresent(Bool.self, forKey: .bigMoves) ?? true
        milestones = try c.decodeIfPresent(Bool.self, forKey: .milestones) ?? true
        nearlyDone = try c.decodeIfPresent(Bool.self, forKey: .nearlyDone) ?? true
        weeklyRecap = try c.decodeIfPresent(Bool.self, forKey: .weeklyRecap) ?? true
    }

    static let key = "notification-prefs"
    private static let recapKey = "notifications-weekly-recap"

    /// The weekly recap's switch, on this phone.
    static var recapOn: Bool {
        get { UserDefaults.standard.object(forKey: recapKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: recapKey) }
    }
}

/// The one-line note shown before the notifications prompt. `ask()` waits for the answer; the
/// root shows `NotificationNoteSheet` while `pending` is true.
@Observable
final class NotificationExplainer {
    static let shared = NotificationExplainer()
    private(set) var pending = false
    @ObservationIgnored private var continuation: CheckedContinuation<Bool, Never>?

    /// True when the note's "Turn on" was tapped (then Apple's prompt follows).
    func ask() async -> Bool {
        await MainActor.run {
            // A second ask while one is up answers the first "not now".
            continuation?.resume(returning: false)
            continuation = nil
            pending = true
        }
        return await withCheckedContinuation { c in continuation = c }
    }

    /// Called from the note (on the main thread).
    func answer(_ go: Bool) {
        pending = false
        continuation?.resume(returning: go)
        continuation = nil
    }
}

/// "Lucent sends a notification when a watched price is hit or a set comes out." Turn on, or not now.
struct NotificationNoteSheet: View {
    var onAnswer: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Notifications").font(.display(24)).tracking(-0.6)
                    Text("Only when something you asked for happens").font(.geist(13)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button("Not now") { onAnswer(false) }.font(.geist(15, .medium)).foregroundStyle(Theme.muted)
            }
            Text("Lucent sends one when a watched card reaches your price, or a set you set a reminder for comes out. Nothing else.")
                .font(.geist(15)).foregroundStyle(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
            Button("Turn on") { onAnswer(true) }.buttonStyle(Button3D(kind: .lime))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(250)])
        .interactiveDismissDisabled()
        .glassSheet()
    }
}

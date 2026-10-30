import Supabase
import SwiftUI
import UIKit
import UserNotifications

/// Push notifications: registers the phone with Apple, saves its token to your account
/// (so the server can send price alerts), and opens the right card when you tap one.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await PushRegistration.save(token: token) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Push registration failed: \(error.localizedDescription)")
    }

    /// Show alerts even while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Tapping a price alert opens that card.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let id = response.notification.request.content.userInfo["productId"] as? String {
            await MainActor.run { Router.shared.product = id }
        }
    }
}

/// Where a tapped notification wants to go.
@Observable
final class Router {
    static let shared = Router()
    var product: String?
}

enum PushRegistration {
    /// Ask for permission (once) and register with Apple; the token arrives in the AppDelegate.
    @MainActor
    static func enable() async {
        guard await Notifications.requestPermission() else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Re-register on launch when permission was already given, so a changed token is saved.
    @MainActor
    static func refreshIfAllowed() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .authorized { UIApplication.shared.registerForRemoteNotifications() }
    }

    struct Row: Codable {
        var token: String
        var user_id: String
        var environment: String
        var updated_at: String
    }

    static func save(token: String) async {
        let client = Backend.shared.supabase
        guard let user = try? await client.auth.session.user else { return }
        // Builds run from Xcode talk to Apple's sandbox; TestFlight and the App Store use production.
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        let row = Row(token: token, user_id: user.id.uuidString.lowercased(), environment: environment, updated_at: ISO8601DateFormatter().string(from: Date()))
        do {
            try await client.from("device_tokens").upsert(row).execute()
        } catch {
            print("Couldn't save push token: \(error.localizedDescription)")
        }
    }
}

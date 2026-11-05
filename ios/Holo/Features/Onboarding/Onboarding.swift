import Foundation
import Observation
import SwiftUI

/// The first-run flags kept on this phone: whether the welcome pages were seen, whether the
/// demo is being tried without an account, and the one-line notes before the camera and
/// notification prompts. Nothing here is a secret or synced.
@Observable
final class Onboarding {
    static let shared = Onboarding()

    /// The welcome pages show once; after that a signed-out app opens on the sign-in form.
    var welcomeSeen: Bool {
        didSet { UserDefaults.standard.set(welcomeSeen, forKey: "onboarding-welcome-seen") }
    }

    /// "Try the demo" on the welcome pages: the made-up collection, no account. Survives a
    /// relaunch; Account → My collection (or Sign in) switches back to the sign-in form.
    var tryingDemo: Bool {
        didSet { UserDefaults.standard.set(tryingDemo, forKey: "onboarding-trying-demo") }
    }

    private init() {
        welcomeSeen = UserDefaults.standard.bool(forKey: "onboarding-welcome-seen")
        tryingDemo = UserDefaults.standard.bool(forKey: "onboarding-trying-demo")
    }

    /// The one-line note in the scanner before the camera prompt, shown once.
    static var cameraNoteSeen: Bool {
        get { UserDefaults.standard.bool(forKey: "onboarding-camera-note-seen") }
        set { UserDefaults.standard.set(newValue, forKey: "onboarding-camera-note-seen") }
    }

    /// The one-line note before the notifications prompt, shown once.
    static var notificationsExplained: Bool {
        get { UserDefaults.standard.bool(forKey: "onboarding-notifications-explained") }
        set { UserDefaults.standard.set(newValue, forKey: "onboarding-notifications-explained") }
    }
}

/// An empty page, in the house style: a short title, one muted line and one lime action
/// (with an optional quiet link under it). No pictures, no coach marks.
struct EmptyPage: View {
    var title: String
    var line: String
    var action: String?
    var icon: String = "viewfinder"
    var onAction: () -> Void = {}
    var link: String?
    var onLink: () -> Void = {}

    var body: some View {
        VStack(spacing: 12) {
            Text(title).font(.display(28)).tracking(-0.7).multilineTextAlignment(.center)
            Text(line).font(.geist(15)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action: onAction) { Label(action, systemImage: icon) }
                    .buttonStyle(Button3D(kind: .lime, fullWidth: false))
                    .padding(.top, 8)
            }
            if let link {
                Button(link, action: onLink).font(.geist(15, .medium)).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.vertical, 48)
    }
}

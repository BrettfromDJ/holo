import Foundation
import Observation
import SwiftUI

/// The first-run flags kept on this phone: whether the
/// demo is being tried without an account, and the one-line notes before the camera and
/// notification prompts. Nothing here is a secret or synced.
@Observable
final class Onboarding {
    static let shared = Onboarding()

    /// The made-up collection without an account (from the old welcome pages). Survives a
    /// relaunch; Account → My collection (or Sign in) switches back to the sign-in form.
    var tryingDemo: Bool {
        didSet { UserDefaults.standard.set(tryingDemo, forKey: "onboarding-trying-demo") }
    }

    private init() {
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
    /// The button's icon, and the big icon on top unless `symbol` is given.
    var icon: String = "camera"
    var onAction: () -> Void = {}
    var link: String?
    var onLink: () -> Void = {}
    /// The icon in the glass circle at the top.
    var symbol: String? = nil

    /// One look for every empty page (the same as an empty Watchlist or list): an icon in a glass
    /// circle, a display heading, one muted line, one flat lime 44pt button, an optional quiet link.
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol ?? icon)
                .font(.system(size: 26, weight: .medium)).foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .liquidGlass(in: Circle())
                .padding(.bottom, 6)
            Text(title.noWidow).font(.display(24)).tracking(-0.6).foregroundStyle(.white).multilineTextAlignment(.center)
            // Even lines, centred (no long line over a short one).
            BalancedText(text: line, font: .geist(15), color: Theme.muted, alignment: .center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300)
            if let action {
                Button { Haptics.tap(); onAction() } label: {
                    Label(action, systemImage: icon).font(.geist(15, .semibold)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 22).frame(height: 44)
                        .background(Capsule().fill(Theme.lime))
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
            }
            if let link {
                Button(link, action: onLink).font(.geist(14, .medium)).foregroundStyle(Theme.muted)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.vertical, 48)
    }
}

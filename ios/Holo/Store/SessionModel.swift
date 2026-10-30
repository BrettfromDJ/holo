import Foundation
import Observation
import Supabase

/// Who's signed in. Follows Supabase's auth events, so a restored or expired session updates the UI.
@Observable
final class SessionModel {
    enum State: Equatable { case loading, signedOut, signedIn(userId: String, email: String?) }

    var state: State = .loading

    private var listener: Task<Void, Never>?

    func start() {
        guard listener == nil else { return }
        let auth = Backend.shared.supabase.auth
        listener = Task { [weak self] in
            for await (_, session) in auth.authStateChanges {
                await MainActor.run {
                    if let session, !session.isExpired {
                        self?.state = .signedIn(userId: session.user.id.uuidString.lowercased(), email: session.user.email)
                    } else {
                        self?.state = .signedOut
                    }
                }
            }
        }
    }

    /// Emails a 6-digit sign-in code (creates the account on first use).
    func sendCode(to email: String) async throws {
        try await Backend.shared.supabase.auth.signInWithOTP(email: email)
    }

    func verify(email: String, code: String) async throws {
        try await Backend.shared.supabase.auth.verifyOTP(email: email, token: code, type: .email)
    }

    func signOut() async {
        try? await Backend.shared.supabase.auth.signOut()
    }
}

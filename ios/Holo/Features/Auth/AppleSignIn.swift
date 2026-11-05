import AuthenticationServices
import CryptoKit
import Foundation
import Security
import SwiftUI

/// Apple's own Sign in with Apple button, wired to the same Supabase account as the website:
/// Apple hands back an identity token for a nonce we made; Supabase checks both and signs in.
struct AppleSignInButton: View {
    @Environment(SessionModel.self) private var session
    /// Signed in (the session changes on its own; this is for marking the welcome seen etc.).
    var onSuccess: () -> Void = {}
    var onError: (String) -> Void
    @State private var nonce = ""

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            nonce = AppleNonce.random()
            request.requestedScopes = [.email]
            // Apple gets the hash; Supabase gets the raw nonce and checks they match.
            request.nonce = AppleNonce.sha256(nonce)
        } onCompletion: { result in
            switch result {
            case let .success(auth):
                guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                      let data = credential.identityToken, let token = String(data: data, encoding: .utf8) else {
                    onError("Apple didn't return a sign-in token. Try again, or use email.")
                    return
                }
                let nonce = self.nonce
                Task {
                    do {
                        try await session.signInWithApple(idToken: token, nonce: nonce)
                        onSuccess()
                    } catch {
                        onError(AppleNonce.message(for: error))
                    }
                }
            case let .failure(error):
                // Closing Apple's sheet isn't an error worth showing.
                if let e = error as? ASAuthorizationError, e.code == .canceled { return }
                onError(error.localizedDescription)
            }
        }
        .signInWithAppleButtonStyle(.white)
        .frame(height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel("Sign in with Apple")
    }
}

enum AppleNonce {
    /// A random string Apple signs into the token, so the token can't be replayed.
    static func random(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var out = ""
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        if status != errSecSuccess {
            // Vanishingly rare; the nonce is still unpredictable enough for one sign-in.
            bytes = (0 ..< length).map { _ in UInt8.random(in: 0 ... 255) }
        }
        for b in bytes { out.append(chars[Int(b) % chars.count]) }
        return out
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Supabase's "Unsupported provider" means Apple isn't switched on for this project yet.
    static func message(for error: Error) -> String {
        let text = error.localizedDescription.lowercased()
        if text.contains("provider") || text.contains("not enabled") || text.contains("unsupported") {
            return "Sign in with Apple isn't set up yet. Use email."
        }
        return error.localizedDescription
    }
}

import AuthenticationServices
import CryptoKit
import Foundation
import Security
import SwiftUI

/// Sign in with Apple, wired to the same Supabase account as the website: Apple hands back an
/// identity token for a nonce we made; Supabase checks both and signs in. Our own button (Apple's
/// logo and words, in the app's font and size, like the lime one above it) instead of Apple's,
/// whose text came out much bigger than the rest of the form.
struct AppleSignInButton: View {
    @Environment(SessionModel.self) private var session
    /// Signed in (the session changes on its own; this is for marking things seen etc.).
    var onSuccess: () -> Void = {}
    var onError: (String) -> Void
    @State private var flow = AppleSignInFlow()

    var body: some View {
        Button {
            flow.start { result in handle(result) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "apple.logo").font(.system(size: 17, weight: .semibold)).offset(y: -1)
                Text("Sign in with Apple")
            }
        }
        .buttonStyle(Button3D(kind: .light))
        .accessibilityLabel("Sign in with Apple")
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .success(auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.identityToken, let token = String(data: data, encoding: .utf8) else {
                onError("Apple didn't return a sign-in token. Try again, or use email.")
                return
            }
            let nonce = flow.nonce
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
}

/// Runs Apple's sign-in sheet for our button and hands back what it returns.
@MainActor
final class AppleSignInFlow: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    /// The raw nonce of the current request (Apple gets its hash; Supabase gets this).
    private(set) var nonce = ""
    private var completion: ((Result<ASAuthorization, Error>) -> Void)?
    private var controller: ASAuthorizationController?

    func start(_ completion: @escaping (Result<ASAuthorization, Error>) -> Void) {
        nonce = AppleNonce.random()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email]
        request.nonce = AppleNonce.sha256(nonce)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.completion = completion
        self.controller = controller
        controller.performRequests()
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        MainActor.assumeIsolated { finish(.success(authorization)) }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated { finish(.failure(error)) }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }

    private func finish(_ result: Result<ASAuthorization, Error>) {
        completion?(result)
        completion = nil
        controller = nil
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

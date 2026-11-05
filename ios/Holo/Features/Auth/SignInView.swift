import SwiftUI

/// Email sign-in with a code (6 to 8 digits, whatever the account sends), the same account as the website.
struct SignInView: View {
    @Environment(SessionModel.self) private var session
    @State private var email = ""
    @State private var code = ""
    @State private var sent = false
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Text("Lucent").font(.geist(40, .semibold)).tracking(-1)
            Text(sent ? "Enter the code we sent to \(email)." : "Track what your cards are worth. Sign in with the same email you use on the website.")
                .foregroundStyle(Theme.muted)

            if !sent {
                TextField("you@email.com", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .field()
                    .focused($focused)
                Button(busy ? "Sending…" : "Email me a code") { Task { await send() } }
                    .buttonStyle(LimeButtonStyle())
                    .disabled(busy || !email.contains("@"))
                HStack(spacing: 12) {
                    Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
                    Text("or").font(.geist(13)).foregroundStyle(Theme.subtle)
                    Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
                }
                AppleSignInButton { message in error = message }
            } else {
                TextField("Code", text: $code)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .field()
                    .focused($focused)
                    // Digits only; the sixth one signs in by itself.
                    .onChange(of: code) { _, value in
                        // Codes are 6 to 8 digits depending on the account's settings: the field
                        // takes up to 8 and signs in by itself once 8 are in (or tap Sign in at 6).
                        let digits = String(value.filter(\.isNumber).prefix(8))
                        if digits != value { code = digits; return }
                        if digits.count == 8, !busy { Task { await verify() } }
                    }
                Button(busy ? "Checking…" : "Sign in") { Task { await verify() } }
                    .buttonStyle(LimeButtonStyle())
                    .disabled(busy || code.count < 6)
                Button("Use a different email") {
                    sent = false
                    code = ""
                }
                .font(.callout)
                .foregroundStyle(Theme.muted)
            }

            if let error {
                Text(error).font(.callout).foregroundStyle(Theme.down)
            }
            Spacer()
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.background)
        .onAppear { focused = true }
    }

    private func send() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await session.sendCode(to: email.trimmingCharacters(in: .whitespaces))
            sent = true
            focused = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func verify() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await session.verify(email: email.trimmingCharacters(in: .whitespaces), code: code.trimmingCharacters(in: .whitespaces))
        } catch {
            self.error = "That code didn't work. Check it, or send a new one."
        }
    }
}

extension View {
    /// A filled input like the web app's.
    func field() -> some View {
        padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

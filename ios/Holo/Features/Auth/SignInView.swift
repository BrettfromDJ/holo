import SwiftUI

/// Email sign-in with a 6-digit code, the same account as the website.
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
            Text("HOLO").font(.system(size: 44, weight: .black)).kerning(1)
            Text(sent ? "Enter the 6-digit code we sent to \(email)." : "Track what your cards are worth. Sign in with the same email you use on the website.")
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
            } else {
                TextField("123456", text: $code)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .field()
                    .focused($focused)
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

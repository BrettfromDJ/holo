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
        ZStack(alignment: .top) {
            // The welcome screens' lit grid and drifting, tilted columns of cards, filling the
            // top and fading into the page behind the form.
            WelcomeBackdrop().ignoresSafeArea()
            GeometryReader { geo in
                WelcomeGrid(showsWorth: false)
                    .frame(height: geo.size.height * 0.62)
                    .frame(maxWidth: .infinity)
            }
            .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Spacer(minLength: 0)
                // The name, then a big balanced line.
                HStack(spacing: 8) {
                    Circle().fill(Theme.lime).frame(width: 8, height: 8).shadow(color: Theme.lime.opacity(0.8), radius: 6)
                    Text("DEXORA").font(.mono(12)).tracking(2.4).foregroundStyle(.white.opacity(0.85))
                }
                DisplayText(text: sent ? "Check your email" : "Know what every card is worth", size: 34, lineGap: -0.07)
                Text(sent ? "Enter the code we sent to \(email)." : "Prices, grades and your whole collection, in one place. Use the same email as the website.")
                    .font(.geist(15)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 6)

                if !sent {
                    TextField("you@email.com", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .glassField()
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
                        .glassField()
                        .focused($focused)
                        // Digits only; codes are 6 to 8 digits depending on the account's settings:
                        // the field takes up to 8 and signs in by itself once 8 are in (or tap Sign in at 6).
                        .onChange(of: code) { _, value in
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
                    .font(.geist(14, .medium))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
                }

                if let error {
                    Text(error).font(.geist(14)).foregroundStyle(Theme.down)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .background(Theme.background)
        // The keyboard comes up when you tap the field, not over the cards on arrival.
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
    /// An input on glass, so the cards and glows behind show through softly.
    func glassField() -> some View {
        padding(.horizontal, 16)
            .frame(minHeight: 54)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// A filled input like the web app's.
    func field() -> some View {
        padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

import SwiftUI

/// Email sign-in with a 6-digit code (six boxes), the same account as the website.
struct SignInView: View {
    @Environment(SessionModel.self) private var session
    @State private var email = ""
    @State private var code = ""
    @State private var sent = false
    @State private var busy = false
    @State private var error: String?
    /// When the last code was sent, and the seconds until another can be.
    @State private var sentAt = Date.distantPast
    @State private var resendIn = 0
    /// Briefly true after a resend, to say it went.
    @State private var resent = false
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            // The welcome screens' lit grid and drifting card wall, as its own piece: tapping the
            // field only changes `typing`, so nothing else on the page is worked out again.
            SignInBackdrop(typing: focused).equatable()
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                form
                    .padding(.horizontal, 24)
                    .padding(.top, 70)
                    .padding(.bottom, 16)
                    // The form's own dark backing: clear at the top, solid page color from the
                    // heading down, so text always reads, wherever the keyboard pushes it.
                    .background {
                        LinearGradient(stops: [
                            .init(color: Theme.background.opacity(0), location: 0),
                            .init(color: Theme.background.opacity(0.92), location: 0.22),
                            .init(color: Theme.background, location: 0.4),
                        ], startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea(edges: .bottom)
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .background(Theme.background)
        // iPhone loads its keyboard the first time an app asks for one, which made the first tap
        // on the field pause. Load it out of sight while the screen is being read.
        .background(KeyboardWarmer().frame(width: 0, height: 0))
        // The keyboard comes up when you tap the field, not over the cards on arrival.
    }

    private var form: some View {
            VStack(alignment: .leading, spacing: 16) {
                // The name, then a big balanced line.
                HStack(spacing: 8) {
                    Circle().fill(Theme.lime).frame(width: 8, height: 8).shadow(color: Theme.lime.opacity(0.8), radius: 6)
                    Text("DEXORA").font(.mono(12)).tracking(2.4).foregroundStyle(.white.opacity(0.85))
                }
                // The heading and its line sit close together, as one block.
                VStack(alignment: .leading, spacing: 6) {
                    DisplayText(text: sent ? "Check your email" : "Sign in", size: 34, lineGap: -0.07)
                    // Lines of even length (no long line over a short one).
                    BalancedText(text: sent ? "Enter the code we sent to \(email)." : "Sign in with your email or Apple. It's the same account as the website.",
                                 font: .geist(15), color: Theme.muted, alignment: .leading)
                }
                .padding(.bottom, 6)

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
                    // Six boxes, one per digit; the sixth signs in by itself. One hidden field takes
                    // the typing (and iPhone's "from Mail" code suggestion fills all six at once).
                    CodeBoxes(code: $code, focused: $focused) {
                        if !busy { Task { await verify() } }
                    }
                    Button(busy ? "Checking…" : "Sign in") { Task { await verify() } }
                        .buttonStyle(LimeButtonStyle())
                        .disabled(busy || code.count < CodeBoxes.length)
                    HStack {
                        Button("Use a different email") {
                            sent = false
                            code = ""
                        }
                        Spacer()
                        // Resend, once a 30-second wait is up (emails are rate limited).
                        if resendIn > 0 {
                            Text("Resend in \(resendIn)s").monospacedDigit().foregroundStyle(Theme.subtle)
                        } else {
                            Button("Resend code") { Task { await send(again: true) } }
                                .foregroundStyle(Theme.lime)
                                .disabled(busy)
                        }
                    }
                    .font(.geist(14, .medium))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 2)
                    .task(id: sentAt) {
                        // Count down the wait to resend.
                        while !Task.isCancelled {
                            let left = 30 - Int(Date().timeIntervalSince(sentAt))
                            resendIn = max(0, left)
                            if left <= 0 { break }
                            try? await Task.sleep(for: .seconds(1))
                        }
                    }
                }

                if resent {
                    Text("New code sent.").font(.geist(14)).foregroundStyle(Theme.muted)
                }
                if let error {
                    Text(error).font(.geist(14)).foregroundStyle(Theme.down)
                }
            }
    }

    private func send(again: Bool = false) async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await session.sendCode(to: email.trimmingCharacters(in: .whitespaces))
            sent = true
            sentAt = Date()
            if again {
                code = ""
                resent = true
                Task { try? await Task.sleep(for: .seconds(3)); resent = false }
            }
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

/// The sign-in code as six boxes, one digit each: the next empty box lit in lime, a filled one
/// white. One hidden field underneath does the typing, so paste, autofill from Mail and delete
/// all work as usual. `onComplete` runs when the sixth digit goes in.
struct CodeBoxes: View {
    static let length = 6
    @Binding var code: String
    var focused: FocusState<Bool>.Binding
    var onComplete: () -> Void

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .focused(focused)
                .foregroundStyle(.clear)
                .tint(.clear)
                .opacity(0.02)
                .onChange(of: code) { _, value in
                    let digits = String(value.filter(\.isNumber).prefix(Self.length))
                    if digits != value { code = digits; return }
                    if digits.count == Self.length { onComplete() }
                }
            HStack(spacing: 8) {
                ForEach(0 ..< Self.length, id: \.self) { i in
                    let chars = Array(code)
                    let digit = i < chars.count ? String(chars[i]) : ""
                    let current = focused.wrappedValue && i == min(chars.count, Self.length - 1) && chars.count < Self.length
                    Text(digit)
                        .font(.display(28)).monospacedDigit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 62)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface2))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(current ? Theme.lime : Color.white.opacity(digit.isEmpty ? 0.08 : 0.22), lineWidth: current ? 2 : 1)
                        )
                        .shadow(color: current ? Theme.lime.opacity(0.35) : .clear, radius: 10)
                }
            }
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { focused.wrappedValue = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sign-in code, \(code.count) of \(Self.length) digits")
    }
}

/// The sign-in page's background: the lit grid and the drifting, tilted wall of cards over the
/// top of the screen. While you type, the drift stops (no redraws while the keyboard slides up)
/// and a dark layer dims it: a plain layer on top, not a fade of the wall itself (fading the wall
/// made the phone redraw all of it off-screen through the fade). Equatable on `typing` alone.
private struct SignInBackdrop: View, Equatable {
    var typing: Bool

    var body: some View {
        ZStack(alignment: .top) {
            WelcomeBackdrop().ignoresSafeArea()
            GeometryReader { geo in
                WelcomeGrid()
                    .frame(height: geo.size.height * 0.62)
                    .frame(maxWidth: .infinity)
            }
            .ignoresSafeArea()
            // The drift stops while you type.
            .environment(\.welcomeActive, !typing)
            Theme.background
                .opacity(typing ? 0.82 : 0)
                .ignoresSafeArea()
                .animation(.easeOut(duration: 0.2), value: typing)
        }
        .allowsHitTesting(false)
    }
}

/// An invisible text field that, once per launch, asks for the keyboard and lets it go straight
/// away (before it can show), so iPhone has it loaded by the time the real field is tapped.
private struct KeyboardWarmer: UIViewRepresentable {
    func makeUIView(context: Context) -> WarmField {
        let field = WarmField()
        field.keyboardType = .emailAddress
        field.textContentType = .emailAddress
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.alpha = 0
        field.isAccessibilityElement = false
        return field
    }

    func updateUIView(_ uiView: WarmField, context: Context) {}

    final class WarmField: UITextField {
        private static var warmed = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, !Self.warmed else { return }
            Self.warmed = true
            // A moment after the screen appears, so its first frame isn't held up.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, self.window != nil else { return }
                UIView.performWithoutAnimation {
                    self.becomeFirstResponder()
                    self.resignFirstResponder()
                }
            }
        }
    }
}

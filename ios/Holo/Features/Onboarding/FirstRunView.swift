import SwiftUI
import UIKit

/// The two first-run steps after signing in with nothing in the collection: what you collect
/// (so Search and Explore put those brands first), then the ways to add a first card. Shown
/// once per account; Later skips it for good. Never in a demo.
struct FirstRunView: View {
    /// The account (nil in a screenshot demo: nothing is saved).
    var userId: String?
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var games: [Collects.Game] = Collects.fallback
    @State private var picked: Set<String> = Set(Collects.cached)
    @State private var saving = false
    @State private var importNote = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            GridPattern().ignoresSafeArea().mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .center))
            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 6) {
                        ForEach(0 ..< 2, id: \.self) { i in
                            Capsule().fill(i == step ? Theme.lime : Color.white.opacity(0.18)).frame(width: i == step ? 18 : 6, height: 6)
                        }
                    }
                    .accessibilityHidden(true)
                    Spacer()
                    Button("Later") { finish() }
                        .font(.geist(15, .medium)).foregroundStyle(Theme.muted)
                        .accessibilityIdentifier("first-run-later")
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                if step == 0 {
                    collect.transition(.opacity)
                } else {
                    add.transition(.opacity)
                }
            }
        }
        .foregroundStyle(.white)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: step)
        .task { games = await Collects.games() }
        .sheet(isPresented: $importNote) { ImportNoteSheet() }
    }

    // MARK: Step 1: what do you collect?

    private var collect: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    DisplayText(text: "What do you collect?", size: 38)
                    Text("Pick as many as you like. Search and Explore put them first.").font(.geist(15)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(games) { g in
                            let on = picked.contains(g.slug)
                            Button {
                                if on { picked.remove(g.slug) } else { picked.insert(g.slug) }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(on ? Theme.ink : Theme.subtle)
                                    // Two lines when a name needs them ("Magic: The Gathering").
                                    Text(g.name).font(.geist(15, .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                                .foregroundStyle(on ? Theme.ink : .white)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 50)
                                .background {
                                    if on {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.limeEdge).offset(y: 2)
                                            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.lime)
                                        }
                                    } else {
                                        Color.clear.liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    }
                                }
                                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    .padding(.top, 18)
                }
                .padding(.horizontal, 24)
                .padding(.top, 36)
                .padding(.bottom, 24)
            }
            Button(saving ? "Saving…" : (picked.isEmpty ? "Skip for now" : "Continue")) { Task { await savePicks() } }
                .buttonStyle(Button3D(kind: .lime))
                .disabled(saving)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                .accessibilityIdentifier("first-run-continue")
        }
    }

    private func savePicks() async {
        saving = true
        defer { saving = false }
        let chosen = games.filter { picked.contains($0.slug) }
        await Collects.save(chosen, userId: userId)
        step = 1
    }

    // MARK: Step 2: add your first card

    private var add: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    DisplayText(text: "Add your first card", size: 38)
                    Text("Scan it, look it up, or bring a whole collection over from the website.").font(.geist(15)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 10) {
                        tile("Scan", "Point the camera at a card; its price appears on it.", icon: "viewfinder") {
                            finish { Router.shared.scanRequest += 1 }
                        }
                        .accessibilityIdentifier("first-run-scan")
                        tile("Search", "Find any card or sealed product by name.", icon: "magnifyingglass") {
                            finish { Router.shared.searchRequest += 1 }
                        }
                        .accessibilityIdentifier("first-run-search")
                        tile("Import", "Already have a spreadsheet? The website imports CSV files.", icon: "square.and.arrow.down") {
                            importNote = true
                        }
                        .accessibilityIdentifier("first-run-import")
                    }
                    .padding(.top, 18)
                }
                .padding(.horizontal, 24)
                .padding(.top, 36)
                .padding(.bottom, 24)
            }
            // (Later lives at the top right, like the first step.)
        }
    }

    /// A big glass tile: icon, title, one line, chevron.
    private func tile(_ title: String, _ line: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.lime)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Theme.lime.opacity(0.12)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.geist(18, .semibold))
                    Text(line).font(.geist(13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.subtle)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Done (or Later): remembered for this account, then the cover goes down and whatever
    /// was picked opens once it has.
    private func finish(then action: (() -> Void)? = nil) {
        if let userId { Onboarding.markDone(userId: userId) }
        dismiss()
        guard let action else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { action() }
    }
}

/// Import: the app has no CSV import; the website does. Copies the link to the clipboard.
private struct ImportNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var link: String { AppConfig.apiBaseURL.appendingPathComponent("settings").absoluteString }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Import on the website").font(.display(24)).tracking(-0.6)
                    Text("Same account, same collection").font(.geist(13)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button("Done") { dismiss() }.font(.geist(15, .medium)).foregroundStyle(Theme.muted)
            }
            Text("Open Lucent on a computer, go to Settings → Import a collection (CSV), and bring purchases over from another tracker or a spreadsheet. You check every match before anything is added, and it all shows up here.")
                .font(.geist(15)).foregroundStyle(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
            Text(link).font(.mono(13)).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .sheetPanel(radius: 14)
            Button(copied ? "Link copied" : "Copy the link") {
                UIPasteboard.general.string = link
                copied = true
            }
            .buttonStyle(Button3D(kind: .lime))
            .sensoryFeedback(.success, trigger: copied)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(340)])
        .glassSheet()
    }
}

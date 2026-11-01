import Foundation
import Observation

/// Cards at the grader and your grading costs, kept in user_state under the website's keys
/// ("grading-submissions", "grading-costs"). While a card is at the grader it stays in the
/// collection raw; when it comes back it's moved into a slab (CollectionStore.moveToSlab).
@Observable
final class GradingStore {
    struct Submission: Codable, Identifiable, Hashable {
        var id: String
        var productId: String
        var printing: String?
        var condition: String
        var company: String
        /// Service level ("Value", "Regular", "Express").
        var service: String
        var quantity: Double
        /// Grading fee per card.
        var fee: Double
        /// Shipping and insurance per card.
        var shipping: Double
        var sentOn: String
        /// "sent" or "returned".
        var status: String
        var grade: String?
        var returnedOn: String?

        var rawIdentity: HoldingIdentity { HoldingIdentity(productId: productId, printing: printing, condition: condition, gradeCompany: nil, grade: nil) }
    }

    var submissions: [Submission] = []
    var costs = Grading.Costs()
    /// Certification numbers by slab holding key (shared with the website as "slab-certs").
    var certs: [String: String] = [:]
    /// The bumper guard chosen for each slab, by holding key ("slab-bumpers").
    var bumpers: [String: String] = [:]
    private(set) var loaded = false
    private var userId: String?
    /// The keys whose account copy loaded. A key that failed to load is never saved, so an
    /// empty list from a bad connection can't overwrite what's in the account.
    private var synced: Set<String> = []

    func reset() {
        submissions = []
        costs = Grading.Costs()
        certs = [:]
        bumpers = [:]
        loaded = false
        userId = nil
        synced = []
    }

    /// Load once per account; a demo (no account) keeps everything on the phone.
    @MainActor
    func load(userId: String?) async {
        guard !loaded || self.userId != userId else { return }
        self.userId = userId
        loaded = true
        guard userId != nil, !Demo.isOn else { return }
        synced = []
        // `try?` would flatten "no saved value yet" and "the load failed" into one nil, so each
        // key is loaded with do/catch: only a real failure leaves it unsynced.
        do { submissions = try await UserState.load("grading-submissions", as: [Submission].self) ?? []; synced.insert("grading-submissions") } catch {}
        do { costs = try await UserState.load("grading-costs", as: Grading.Costs.self) ?? Grading.Costs(); synced.insert("grading-costs") } catch {}
        do { certs = try await UserState.load("slab-certs", as: [String: String].self) ?? [:]; synced.insert("slab-certs") } catch {}
        do { bumpers = try await UserState.load("slab-bumpers", as: [String: String].self) ?? [:]; synced.insert("slab-bumpers") } catch {}
        // Something didn't load: try again the next time the app loads your data.
        if synced.count < 4 { loaded = false }
    }

    @MainActor
    func setCert(_ holdingKey: String, _ cert: String) {
        let value = cert.trimmingCharacters(in: .whitespaces)
        certs[holdingKey] = value.isEmpty ? nil : value
        guard let userId, !Demo.isOn, synced.contains("slab-certs") else { return }
        let snapshot = certs
        Task { try? await UserState.save("slab-certs", snapshot, userId: userId) }
    }

    @MainActor
    func setBumper(_ holdingKey: String, _ id: String?) {
        bumpers[holdingKey] = id
        guard let userId, !Demo.isOn, synced.contains("slab-bumpers") else { return }
        let snapshot = bumpers
        Task { try? await UserState.save("slab-bumpers", snapshot, userId: userId) }
    }

    /// When Edit details changes what a slab is, its cert number and bumper follow it to the
    /// new details (unless that slab already has its own). A copy that is no longer graded
    /// leaves them where they were.
    @MainActor
    func moveSlab(from old: HoldingIdentity, to new: HoldingIdentity) {
        guard old.key != new.key, new.isGraded else { return }
        if let cert = certs[old.key], certs[new.key] == nil {
            setCert(old.key, "")
            setCert(new.key, cert)
        }
        if let bumper = bumpers[old.key], bumpers[new.key] == nil {
            setBumper(old.key, nil)
            setBumper(new.key, bumper)
        }
    }

    var sent: [Submission] { submissions.filter { $0.status == "sent" }.sorted { $0.sentOn < $1.sentOn } }
    var returned: [Submission] { Array(submissions.filter { $0.status == "returned" }.sorted { ($0.returnedOn ?? "") > ($1.returnedOn ?? "") }.prefix(5)) }

    /// Units of each raw holding currently at the grader.
    var atGrader: [String: Double] {
        sent.reduce(into: [:]) { $0[$1.rawIdentity.key, default: 0] += $1.quantity }
    }

    @MainActor
    func send(_ holding: HoldingView, company: String, service: String, quantity: Double, fee: Double, shipping: Double, date: String) {
        submissions.append(Submission(
            id: UUID().uuidString.lowercased(), productId: holding.identity.productId, printing: holding.identity.printing,
            condition: holding.identity.condition, company: company, service: service, quantity: quantity,
            fee: fee, shipping: shipping, sentOn: date, status: "sent"
        ))
        save()
    }

    @MainActor
    func cancel(_ id: String) {
        submissions.removeAll { $0.id == id }
        save()
    }

    @MainActor
    func complete(_ sub: Submission, grade: String, date: String, store: CollectionStore) async throws {
        try await store.moveToSlab(raw: sub.rawIdentity, company: sub.company, grade: grade, quantity: sub.quantity, fee: sub.fee, shipping: sub.shipping, date: date)
        if let i = submissions.firstIndex(where: { $0.id == sub.id }) {
            submissions[i].status = "returned"
            submissions[i].grade = grade
            submissions[i].returnedOn = date
        }
        save()
    }

    @MainActor
    func setCosts(_ c: Grading.Costs) {
        costs = c
        guard let userId, !Demo.isOn, synced.contains("grading-costs") else { return }
        Task { try? await UserState.save("grading-costs", c, userId: userId) }
    }

    private func save() {
        guard let userId, !Demo.isOn, synced.contains("grading-submissions") else { return }
        let snapshot = submissions
        Task { try? await UserState.save("grading-submissions", snapshot, userId: userId) }
    }
}

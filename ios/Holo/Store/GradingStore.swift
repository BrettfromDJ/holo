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
    private(set) var loaded = false
    private var userId: String?

    func reset() {
        submissions = []
        costs = Grading.Costs()
        loaded = false
        userId = nil
    }

    /// Load once per account; a demo (no account) keeps everything on the phone.
    @MainActor
    func load(userId: String?) async {
        guard !loaded || self.userId != userId else { return }
        self.userId = userId
        loaded = true
        guard userId != nil, !Demo.isOn else { return }
        submissions = (try? await UserState.load("grading-submissions", as: [Submission].self)) ?? []
        costs = (try? await UserState.load("grading-costs", as: Grading.Costs.self)) ?? Grading.Costs()
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
        guard let userId, !Demo.isOn else { return }
        Task { try? await UserState.save("grading-costs", c, userId: userId) }
    }

    private func save() {
        guard let userId, !Demo.isOn else { return }
        let snapshot = submissions
        Task { try? await UserState.save("grading-submissions", snapshot, userId: userId) }
    }
}

import Foundation
import Observation
import UIKit

/// Rapid scanning: every photo is queued and read in the background, a couple at a time,
/// so you can keep shooting. Clear matches are accepted straight away; others wait for you.
@Observable
final class ScanModel {
    struct Entry: Identifiable {
        enum State { case queued, reading, done, failed }

        let id = UUID()
        let photo: Data
        var thumbnail: UIImage?
        var state: State = .queued
        var result: ScanResult?
        var error: String?
        /// The match you're adding (picked automatically on a clear match).
        var picked: ScanCandidate?
        /// What you paid each, as typed; blank uses the default below.
        var paid = ""
        var condition = CardCondition.nearMint.rawValue

        var value: Double? { picked?.value(for: result?.read) }
    }

    var entries: [Entry] = []
    var scansLeft: Int?
    /// Stops new scans: the balance is empty or the account can't scan.
    var blocked: String?

    private let parallel = 2

    var picks: [Entry] { entries.filter { $0.picked != nil } }
    var busy: Int { entries.filter { $0.state == .queued || $0.state == .reading }.count }
    var total: Double { picks.reduce(0) { $0 + ($1.value ?? 0) } }

    func refreshBalance() async {
        let left = await Backend.shared.api.scansRemaining()
        await MainActor.run { scansLeft = left }
    }

    @MainActor
    func add(photo: Data) {
        var e = Entry(photo: photo)
        e.thumbnail = UIImage(data: photo)?.preparingThumbnail(of: CGSize(width: 96, height: 128))
        entries.insert(e, at: 0)
        pump()
    }

    @MainActor
    func retry(_ id: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].state = .queued
        entries[i].error = nil
        pump()
    }

    @MainActor
    func pick(_ candidate: ScanCandidate, for id: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].picked = candidate
    }

    @MainActor
    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }

    /// Start reading queued photos, oldest first, up to `parallel` at once.
    @MainActor
    private func pump() {
        guard blocked == nil else { return }
        let reading = entries.filter { $0.state == .reading }.count
        let waiting = entries.filter { $0.state == .queued }.reversed()
        for entry in waiting.prefix(max(0, parallel - reading)) {
            guard let i = entries.firstIndex(where: { $0.id == entry.id }) else { continue }
            entries[i].state = .reading
            let id = entry.id
            let photo = entry.photo
            Task {
                do {
                    let result = try await Backend.shared.api.scan(jpeg: photo)
                    await MainActor.run { self.finish(id, result: result) }
                } catch {
                    await MainActor.run { self.fail(id, error: error) }
                }
            }
        }
    }

    @MainActor
    private func finish(_ id: UUID, result: ScanResult) {
        if let left = result.scansRemaining { scansLeft = left }
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return pump() }
        entries[i].state = .done
        entries[i].result = result
        if result.status == "matched", let top = result.candidates.first { entries[i].picked = top }
        pump()
    }

    @MainActor
    private func fail(_ id: UUID, error: Error) {
        let code = (error as? HoloError)?.code
        if ["scan_balance_empty", "unauthorized", "not_configured"].contains(code ?? "") {
            blocked = error.localizedDescription
        }
        if let i = entries.firstIndex(where: { $0.id == id }) {
            entries[i].state = .failed
            entries[i].error = error.localizedDescription
        }
        pump()
    }

    /// Everything picked, as purchases. A blank price uses market, or $0 for cards you pulled.
    func purchases(pulled: Bool, date: String) -> [CollectionStore.Purchase] {
        picks.compactMap { e -> CollectionStore.Purchase? in
            guard let c = e.picked else { return nil }
            let typed = Double(e.paid.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: ""))
            let slab = e.result?.read?.kind == "slab" ? e.result?.read?.grade : nil
            return CollectionStore.Purchase(
                product: c.product,
                printing: c.printing,
                condition: c.product.isSealed ? "Sealed" : (slab != nil ? CardCondition.nearMint.rawValue : e.condition),
                gradeCompany: slab?.company,
                grade: slab?.grade,
                quantity: 1,
                unitPrice: typed ?? (pulled ? 0 : (e.value ?? 0)),
                date: date,
                source: "ios-scan"
            )
        }
    }
}

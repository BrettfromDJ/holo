import Foundation
import Vision

/// Picture matching for the scanner, with Apple's built-in image fingerprints (Vision's feature
/// prints): no model of our own, nothing paid, all on the phone. When the text reader gets part
/// way (a name, or a number several cards share), the candidates' catalog pictures are
/// fingerprinted and the scan goes to the one it looks most like, but only when that one is
/// clearly closer than the rest. Each catalog card's fingerprint is kept on the phone.
enum CardFingerprint {
    /// The closest must be this much nearer than the runner-up (0.8 = 20% nearer) to count.
    static let margin: Float = 0.8
    /// At most this many candidates are compared (each needs its picture once).
    static let maxCandidates = 24

    /// The candidate the scan looks most like, with how sure (its distance and the runner-up's),
    /// or nil when none is clearly closest.
    static func best(scan: Data, among hits: [SearchHit]) async -> (hit: SearchHit, distance: Float, next: Float?)? {
        let hits = Array(hits.prefix(maxCandidates))
        guard !hits.isEmpty, let mine = await fingerprint(of: scan) else { return nil }
        var scored: [(SearchHit, Float)] = []
        await withTaskGroup(of: (SearchHit, Float)?.self) { group in
            for hit in hits {
                group.addTask {
                    guard let theirs = await catalogPrint(hit.pictured) else { return nil }
                    var d: Float = 0
                    guard (try? mine.computeDistance(&d, to: theirs)) != nil else { return nil }
                    return (hit, d)
                }
            }
            for await r in group { if let r { scored.append(r) } }
        }
        scored.sort { $0.1 < $1.1 }
        guard let first = scored.first else { return nil }
        let next = scored.dropFirst().first?.1
        // Clearly closest: well ahead of the runner-up (alone, it must still look alike).
        if let next {
            guard first.1 < next * margin else { return nil }
        } else {
            guard first.1 < 0.6 else { return nil }
        }
        return (first.0, first.1, next)
    }

    // MARK: Fingerprints

    static func fingerprint(of image: Data) async -> VNFeaturePrintObservation? {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNGenerateImageFeaturePrintRequest()
                let handler = VNImageRequestHandler(data: image, options: [:])
                do {
                    try handler.perform([request])
                    cont.resume(returning: request.results?.first as? VNFeaturePrintObservation)
                } catch {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    /// A catalog card's fingerprint: from memory, then the phone's cache, else made from its
    /// picture (downloaded once) and kept.
    static func catalogPrint(_ product: Product) async -> VNFeaturePrintObservation? {
        let key = product.id + "|" + (product.imageUrl ?? "")
        if let hit = store.get(key) { return hit }
        let file = folder.appendingPathComponent(safe(key) + ".print")
        if let data = try? Data(contentsOf: file),
           let print = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data) {
            store.set(key, print)
            return print
        }
        guard let url = product.imageURL, let picture = await ImageCache.download(url),
              let print = await fingerprint(of: picture) else { return nil }
        store.set(key, print)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: print, requiringSecureCoding: true) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? data.write(to: file)
        }
        return print
    }

    private static var folder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("card-prints", isDirectory: true)
    }

    private static func safe(_ key: String) -> String {
        String(key.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" }).suffix(120).description
    }

    /// Fingerprints made this session.
    private static let store = PrintStore()
}

private final class PrintStore: @unchecked Sendable {
    private var prints: [String: VNFeaturePrintObservation] = [:]
    private let lock = NSLock()
    func get(_ key: String) -> VNFeaturePrintObservation? { lock.lock(); defer { lock.unlock() }; return prints[key] }
    func set(_ key: String, _ value: VNFeaturePrintObservation) { lock.lock(); prints[key] = value; lock.unlock() }
}

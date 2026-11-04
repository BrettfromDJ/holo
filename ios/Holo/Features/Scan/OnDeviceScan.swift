import Foundation
import Vision

/// The fast, free first pass of a scan: Apple's on-device text recognition reads the card's name
/// and collector number ("215/203") from the photo, then the stored catalog (a free search, no
/// paid scan) is asked for that card. Only a clear, single match is accepted; anything unsure
/// (slabs, sealed, glare, two printings that read the same) returns nil and the caller falls back
/// to the paid server scan.
///
/// The live scanner (`CardTracker`) uses the same two steps on a flattened crop of the card in
/// view: `read(jpeg:)` then `lookUp`, cached by `cacheKey`, and `result(for:)` turns its match
/// into a scan entry when you tap.
enum OnDeviceScan {
    /// What the text recognition found on the card.
    struct Reading: Equatable {
        var name: String?
        /// The collector number as printed, e.g. "215/203" or "TG05/TG30".
        var number: String
    }

    /// Identify a raw card in a photo, or nil when not sure.
    static func identify(jpeg: Data) async -> ScanResult? {
        guard let reading = await read(jpeg: jpeg) else { return nil }
        guard let hit = await lookUp(reading) else { return nil }
        return result(for: hit)
    }

    /// A catalog match as a matched raw-card scan result.
    static func result(for hit: SearchHit) -> ScanResult {
        let candidate = ScanCandidate(product: hit.product, printing: hit.printing, printings: hit.product.printings ?? [],
                                      market: hit.market, slabMarket: nil, score: 1)
        return ScanResult(status: "matched", message: nil, read: ScanRead(kind: "raw", grade: nil), candidates: [candidate], scansRemaining: nil)
    }

    /// A rough key for a reading, so the same card isn't looked up twice: the number in
    /// canonical form ("TG05/TG30" → "TG5/TG30"), plus the name when one was read.
    static func cacheKey(_ reading: Reading) -> String {
        let number = reading.number.uppercased().split(separator: "/").map { part -> String in
            let letters = part.prefix { $0.isLetter }
            let digits = part.drop { $0.isLetter }.drop { $0 == "0" }
            return String(letters) + (digits.isEmpty ? "0" : String(digits))
        }.joined(separator: "/")
        return number + "|" + (reading.name?.lowercased() ?? "")
    }

    // MARK: Reading the photo

    /// Words that sit at the top of a card but are never its name.
    private static let notNames: Set<String> = ["basic", "stage 1", "stage 2", "stage1", "stage2", "hp", "trainer", "item",
                                                "supporter", "stadium", "energy", "pokémon tool", "evolves from", "vmax", "vstar", "mega"]
    /// Slab labels: leave those to the server, which also reads the grade.
    private static let slabWords = ["psa", "bgs", "beckett", "cgc", "sgc", "gem mt", "gem mint", "pristine", "certified"]

    static func read(jpeg: Data) async -> Reading? {
        await withCheckedContinuation { (cont: CheckedContinuation<Reading?, Never>) in
            // Resume exactly once, whether the request finishes or `perform` throws.
            let once = Once()
            let request = VNRecognizeTextRequest { request, _ in
                let lines = (request.results as? [VNRecognizedTextObservation] ?? []).compactMap { obs -> (String, CGRect)? in
                    guard let text = obs.topCandidates(1).first?.string else { return nil }
                    return (text, obs.boundingBox)
                }
                if once.claim() { cont.resume(returning: parse(lines)) }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US"]
            DispatchQueue.global(qos: .userInitiated).async {
                // Reads the photo's own orientation from its EXIF data.
                let handler = VNImageRequestHandler(data: jpeg, options: [:])
                do { try handler.perform([request]) } catch { if once.claim() { cont.resume(returning: nil) } }
            }
        }
    }

    /// Picks the collector number and the name out of the recognised lines. `boundingBox` is in
    /// Vision's space: 0...1, origin bottom-left, so a larger `maxY` is nearer the top of the card.
    static func parse(_ lines: [(String, CGRect)]) -> Reading? {
        let all = lines.map(\.0).joined(separator: " ").lowercased()
        if slabWords.contains(where: { all.contains($0) }) { return nil }
        // "215/203", "TG05/TG30", "GG12/GG70", allowing a space around the slash.
        let pattern = #"\b([A-Z]{0,3}\d{1,3})\s*/\s*([A-Z]{0,3}\d{2,3})\b"#
        var number: String?
        for (text, _) in lines {
            if let r = text.range(of: pattern, options: .regularExpression) {
                number = text[r].replacingOccurrences(of: " ", with: "")
                break
            }
        }
        guard let number else { return nil }
        // The name: the topmost line with letters that isn't a stage/type word or an HP figure.
        let name = lines
            .sorted { $0.1.maxY > $1.1.maxY }
            .prefix(6)
            .map { cleanName($0.0) }
            .first { n in
                guard let n, n.count >= 3 else { return false }
                return !notNames.contains(n.lowercased())
            } ?? nil
        return Reading(name: name, number: number)
    }

    /// "Umbreon VMAX HP310" → "Umbreon VMAX"; drops HP figures and stray symbols.
    private static func cleanName(_ s: String) -> String? {
        var t = s.replacingOccurrences(of: #"\bHP\s*\d+\b|\b\d+\s*HP\b"#, with: "", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #"[^A-Za-zÀ-ÿ'\-\. ]"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return t.rangeOfCharacter(from: .letters) == nil ? nil : t
    }

    // MARK: Finding it in the catalog

    /// "215/203" and "#215/203" and "215" compare by their parts, ignoring leading zeros.
    static func sameNumber(_ catalog: String?, _ read: String) -> Bool {
        guard let catalog else { return false }
        func parts(_ s: String) -> [String] {
            s.uppercased().replacingOccurrences(of: "#", with: "").split(separator: "/").map { part in
                let letters = part.prefix { $0.isLetter }
                let digits = part.drop { $0.isLetter }.drop { $0 == "0" }
                return String(letters) + (digits.isEmpty ? "0" : String(digits))
            }
        }
        let a = parts(catalog), b = parts(read)
        guard let a0 = a.first, let b0 = b.first, a0 == b0 else { return false }
        // Both have a set total: it must match too (the same number appears in many sets).
        if a.count > 1, b.count > 1 { return a[1] == b[1] }
        return true
    }

    /// One clear catalog match for the reading, or nil.
    static func lookUp(_ reading: Reading) async -> SearchHit? {
        var queries: [String] = []
        if let name = reading.name { queries.append(name) }
        queries.append(reading.number)
        for q in queries {
            guard let hits = try? await Backend.shared.api.search(q) else { continue }
            let matches = hits.filter { !$0.product.isSealed && sameNumber($0.product.number, reading.number) }
            // One product (its printings come along with it): accept. More than one: let the
            // server decide.
            let ids = Set(matches.map(\.product.id))
            if ids.count == 1, let hit = matches.first { return hit }
        }
        return nil
    }
}

/// A flag that can be claimed once, from any thread.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

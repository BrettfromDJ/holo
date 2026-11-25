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
        /// The collector number as printed, e.g. "215/203" or "TG05/TG30"; empty when only the
        /// name could be read (then pictures decide).
        var number: String
        /// Japanese text on the card: it's looked up among Japanese cards (the English list on
        /// the phone had an English card with the same number, and named it).
        var japanese = false
    }

    /// Identify a raw card in a photo, or nil when not sure.
    static func identify(jpeg: Data) async -> ScanResult? {
        await identifyWithReading(jpeg: jpeg).result
    }

    /// The same, also returning what was read and how it was decided (for test-photo mode's log).
    /// Text first; when the text narrows it to several cards (or only a name was read), picture
    /// matching (`CardFingerprint`) picks the one the photo looks most like, if one clearly is.
    static func identifyWithReading(jpeg: Data) async -> (result: ScanResult?, reading: Reading?, note: String?) {
        let began = Date()
        var steps: [String] = []
        func lap(_ what: String, _ from: Date) { steps.append(String(format: "%@ %.1fs", what, Date().timeIntervalSince(from))) }
        func noted(_ how: String) -> String { ([how] + steps).joined(separator: " · ") }
        // The photo's fingerprint starts alongside the text reading (it's needed whenever the
        // text alone doesn't settle it) and is made once for both picture checks below.
        // (A plain task, so a scan settled by its text never waits for it.)
        let printing = Task { await CardFingerprint.fingerprint(of: jpeg) }
        let reading = await read(jpeg: jpeg)
        lap("read", began)
        var why = reading == nil ? "no text" : "text unsure"
        if let reading {
            // Every catalog search at once (they took a second or more each, one after another).
            let searched = Date()
            let hits = await searches(reading)
            lap("search", searched)
            let numbered = hits.filter { strictNumber($0.product.number, reading.number) }
            // The cards the name read could be, in a set of the same size (the number may be misread:
            // "083/128" read for Mewtwo's 063/128 named a Lucario).
            let total = reading.number.split(separator: "/").dropFirst().first.map(String.init)
            let sameName = reading.name == nil ? [] : hits.filter {
                nameAgrees(reading.name, $0.product.name) && total != nil
                    && ($0.product.number ?? "").split(separator: "/").dropFirst().first.map { ScanCatalog.key(String($0)) } == ScanCatalog.key(total!)
            }
            // One card with that number (its pattern versions count as one), and the name read
            // agrees, or isn't any card's name (an attack read as the name): that's it.
            if !reading.number.isEmpty, let hit = oneCard(numbered),
               nameAgrees(reading.name, hit.product.name) || (numberIsEnough(reading.number) && sameName.isEmpty) {
                return (result(for: hit), reading, noted("text"))
            }
            // Several cards print that number (other games and sets): the name read picks one.
            if let hit = oneCard(numbered.filter { reading.name != nil && nameAgrees(reading.name, $0.product.name) }) {
                return (result(for: hit), reading, noted("text + name among \(Set(numbered.map(\.product.id)).count)"))
            }
            // The number names another card: the card with the name read, in a set that size.
            if let hit = oneCard(sameName) {
                return (result(for: hit), reading, noted("name + set size (number misread?)"))
            }
            // A misread set total ("021/130" for 021/131): cards with the same number and a total one off.
            var close = numbered.isEmpty ? hits.filter { closeNumber($0.product.number, reading.number) } : []
            if Set(close.map(\.product.id)).count > 1, reading.name != nil {
                let named = close.filter { nameAgrees(reading.name, $0.product.name) }
                if !named.isEmpty { close = named }
            }
            if Set(close.map(\.product.id)).count == 1, let hit = close.first, nameAgrees(reading.name, hit.product.name) {
                return (result(for: hit), reading, noted("text, total one off"))
            }
            let pool = candidates(reading, hits: numbered.isEmpty ? close : numbered, all: hits)
            if !pool.isEmpty, let mine = await printing.value {
                let compared = Date()
                let best = await CardFingerprint.best(print: mine, among: pool)
                lap("picture", compared)
                if let best {
                    let note = String(format: "picture %.2f vs %@ among %d", best.distance, best.next.map { String(format: "%.2f", $0) } ?? "none", pool.count)
                    return (result(for: best.hit), reading, noted(note))
                }
                why = "picture unsure among \(pool.count)" + (CardFingerprint.lastNear.map { " (\($0))" } ?? "")
            }
        }
        // Last on the phone's side: the scan's picture against every card in the catalog.
        if let mine = await printing.value {
            let compared = Date()
            let best = await CardFingerprint.catalogMatch(print: mine)
            lap("catalog", compared)
            if let best {
                let note = String(format: "catalog picture %.2f vs %@", best.distance, best.next.map { String(format: "%.2f", $0) } ?? "none")
                return (result(for: best.hit), reading, noted(note))
            }
        }
        return (nil, reading, noted(why + ", catalog picture unsure" + (CardFingerprint.lastNear.map { " (\($0))" } ?? "")))
    }

    /// The scanner's own quick lookup (one request); the general search (name, number and both,
    /// at once) only if that fails. One list, each product once.
    static func searches(_ reading: Reading) async -> [SearchHit] {
        // A Japanese card: the server's lookup, kept to Japanese cards (the phone's list is English).
        if reading.japanese {
            let hits = (try? await Backend.shared.api.scanLookup(name: nil, number: reading.number)) ?? []
            return hits.filter { ($0.gameName ?? "").localizedCaseInsensitiveContains("japan") && !$0.product.isSealed }
        }
        // The card list kept on the phone first (milliseconds). The server too only when the
        // phone's list has nothing for this number (a set newer than the list) or isn't ready.
        if let local = ScanCatalog.shared.hits(for: reading) {
            let covered = reading.number.isEmpty
                ? !local.isEmpty
                : local.contains { strictNumber($0.product.number, reading.number) || closeNumber($0.product.number, reading.number) }
            if covered { return local }
        }
        if let hits = try? await Backend.shared.api.scanLookup(name: reading.name, number: reading.number) {
            var seen = Set<String>()
            return hits.filter { !$0.product.isSealed && seen.insert($0.product.id + "|" + ($0.printing ?? "")).inserted }
        }
        var queries: [String] = []
        if let name = reading.name { queries.append(name) }
        if !reading.number.isEmpty { queries.append(reading.number) }
        if let name = reading.name, !reading.number.isEmpty { queries.append(name + " " + reading.number) }
        let lists = await withTaskGroup(of: [SearchHit].self) { group in
            for q in queries { group.addTask { (try? await Backend.shared.api.search(q)) ?? [] } }
            var all: [[SearchHit]] = []
            for await list in group { all.append(list) }
            return all
        }
        var seen = Set<String>()
        return lists.flatMap { $0 }.filter { !$0.product.isSealed && !$0.product.isHiddenFromBrowsing && seen.insert($0.product.id + "|" + ($0.printing ?? "")).inserted }
    }

    /// Whether the name read fits the card (no name read: nothing to disagree with). Loose, as the
    /// reader often runs words together ("TerapagoseX"): the card's first word, letters only, must
    /// appear in what was read. Stops a stray small number ("09/30") naming the wrong card.
    static func nameAgrees(_ read: String?, _ name: String) -> Bool {
        guard let read else { return true }
        func letters(_ s: String) -> String { s.lowercased().filter(\.isLetter) }
        let seen = letters(read)
        guard let first = name.split(separator: " ").first.map({ letters(String($0)) }), first.count >= 3 else { return true }
        // A partly read name ("eevee" read as "evee") counts only from 5 letters: "asic" sits
        // inside "basic" and named a Grass Energy.
        return seen.contains(first) || (seen.count >= 5 && first.contains(seen))
    }

    /// The one card these are, counting a card's pattern versions (Prismatic Evolutions' Poké Ball
    /// and Master Ball patterns are their own products with the same number) as one: the plainest
    /// name wins (the others are a tap away under Wrong card?). Nil when they're different cards.
    static func oneCard(_ hits: [SearchHit]) -> SearchHit? {
        guard let first = hits.first else { return nil }
        if Set(hits.map(\.product.id)).count == 1 { return first }
        func base(_ n: String) -> String {
            n.replacingOccurrences(of: #"\s*[\(\[].*$"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s+-\s+\S+$"#, with: "", options: .regularExpression).lowercased()
        }
        let sameCard = hits.allSatisfy {
            $0.product.setId == first.product.setId && sameNumber($0.product.number, first.product.number ?? "")
                && base($0.product.name) == base(first.product.name)
        }
        guard sameCard else { return nil }
        return hits.min { $0.product.name.count < $1.product.name.count }
    }

    /// A full collector number ("092/131") names one card by itself, even when the line read as
    /// the name was an attack ("Unified Beatdown"). A small one ("09/30", a subset's own count)
    /// can be a stray, so the name read must fit too.
    static func numberIsEnough(_ number: String) -> Bool {
        let parts = number.split(separator: "/")
        guard parts.count == 2, let total = Int(parts[1].filter(\.isNumber)) else { return false }
        return total > 30
    }

    /// `sameNumber`, but when a set total was read the card must print one too (a stored "074"
    /// with no total matched every "074/131" read, filling the list with other sets' cards).
    static func strictNumber(_ catalog: String?, _ read: String) -> Bool {
        guard sameNumber(catalog, read) else { return false }
        return !read.contains("/") || (catalog ?? "").contains("/")
    }

    /// The same card number with a set total one off ("021/130" read for 021/131).
    static func closeNumber(_ catalog: String?, _ read: String) -> Bool {
        guard let catalog else { return false }
        let a = catalog.split(separator: "/"), b = read.split(separator: "/")
        guard a.count == 2, b.count == 2, sameNumber(String(a[0]), String(b[0])),
              let x = Int(a[1].filter(\.isNumber)), let y = Int(b[1].filter(\.isNumber)) else { return false }
        return abs(x - y) == 1
    }

    /// The cards the reading could be, from the searches already made: ones with its number,
    /// else every single starting with its name; one entry per product.
    static func candidates(_ reading: Reading, hits numbered: [SearchHit], all: [SearchHit]) -> [SearchHit] {
        var seen = Set<String>()
        var out = numbered.filter { seen.insert($0.product.id).inserted }
        if out.isEmpty, let name = reading.name {
            let base = name.lowercased()
            out = all.filter { $0.product.name.lowercased().hasPrefix(base) && seen.insert($0.product.id).inserted }
        }
        return out
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
            // Japanese too, so a Japanese card is known for one (its name can't be matched, but
            // its number can, among Japanese cards).
            request.recognitionLanguages = ["en-US", "ja-JP"]
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
        var numbers: [String] = []
        for (text, _) in lines {
            var from = text.startIndex
            while let r = text.range(of: pattern, options: .regularExpression, range: from..<text.endIndex) {
                let n = text[r].replacingOccurrences(of: " ", with: "")
                if !numbers.contains(n) { numbers.append(n) }
                from = r.upperBound
            }
        }
        // A card can carry a second, small subset number beside its own (30th Celebration's
        // "031/128 09/30"): when one is out of 30 or fewer and another isn't, drop the small one.
        func total(_ n: String) -> Int { Int(n.split(separator: "/").last?.filter(\.isNumber) ?? "") ?? 0 }
        if numbers.count > 1, numbers.contains(where: { total($0) > 30 }) {
            numbers.removeAll { total($0) <= 30 }
        }
        // Several cards in one photo: leave it to the server, which reads them all.
        guard numbers.count <= 1 else { return nil }
        var number = numbers.first ?? ""
        // Promos print just a number ("SVP EN 168", "098"), no "/total": a short number alone in
        // the card's bottom-left corner, where nothing else is (HP and damage sit higher up).
        if number.isEmpty {
            let promo = lines.compactMap { text, box -> String? in
                guard box.maxY < 0.12, box.minX < 0.5 else { return nil }
                let tokens = text.split(whereSeparator: { $0 == " " }).map(String.init)
                return tokens.last { $0.range(of: #"^[A-Z]{0,4}0*\d{1,3}$"#, options: .regularExpression) != nil && $0.contains(where: \.isNumber) }
            }
            if promo.count == 1 { number = promo[0].filter(\.isNumber) }
        }
        // The name: the topmost line with letters that isn't a stage/type word or an HP figure.
        let name = lines
            .sorted { $0.1.maxY > $1.1.maxY }
            .prefix(6)
            .map { cleanName($0.0) }
            .first { n in
                guard let n, n.count >= 3 else { return false }
                return !notNames.contains(n.lowercased()) && !looksLikeStage(n)
            } ?? nil
        // Neither a number nor a name: nothing to go on.
        if number.isEmpty && name == nil { return nil }
        let japanese = lines.contains { $0.0.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) } }
        // A Japanese card's name can't be matched to the catalog's English names.
        if japanese { return number.isEmpty ? nil : Reading(name: nil, number: number, japanese: true) }
        return Reading(name: name, number: number)
    }

    /// A misread "BASIC" / "STAGE 1" label ("BASR", "STAOEJ"): within two letters of one.
    static func looksLikeStage(_ s: String) -> Bool {
        let t = s.lowercased().filter(\.isLetter)
        guard t.count <= 7 else { return false }
        return ["basic", "stage", "stagei"].contains { edits(t, $0) <= 2 }
    }

    private static func edits(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var row = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var prev = row[0]
            row[0] = i
            for j in 1...max(b.count, 1) where !b.isEmpty {
                let cur = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, prev + (a[i - 1] == b[j - 1] ? 0 : 1))
                prev = cur
            }
        }
        return a.isEmpty ? b.count : row[b.count]
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

    /// One clear catalog match for the reading, or nil (the live scanner's check).
    static func lookUp(_ reading: Reading) async -> SearchHit? {
        guard !reading.number.isEmpty else { return nil }
        let numbered = await searches(reading).filter { strictNumber($0.product.number, reading.number) }
        // One product (its printings come along with it) that fits the name read: accept. Several
        // with that number: the one whose name fits, if only one does. Else let the server decide.
        if let hit = oneCard(numbered), nameAgrees(reading.name, hit.product.name) { return hit }
        guard reading.name != nil else { return nil }
        return oneCard(numbered.filter { nameAgrees(reading.name, $0.product.name) })
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

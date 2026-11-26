import Foundation

/// Test-photo mode (Settings → Scanner): every scan's photo is saved on the phone with what each
/// scanner said, so our own on-device scanner can be measured against CardSight before it takes
/// over. While it's on, both run on every scan (CardSight too, even when the phone was sure).
/// Files: Files app → On My iPhone → Corodex → Scan tests (one JPEG and one JSON per scan, plus
/// summary.json).
enum ScanTestLog {
    static let key = "scan-test-photos"
    /// Bumped with each scanner change worth testing.
    static let build = "2026-11-26 japanese on phone"

    static var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// What one scanner said about a photo.
    struct Answer: Codable {
        var name: String?
        var number: String?
        var set: String?
        var productId: String?
        var seconds: Double?
    }

    /// One saved scan.
    struct Record: Codable {
        /// Which scanner version made it (so a test zip says whether the phone had the latest).
        var build: String? = ScanTestLog.build
        var id: String
        var date: String
        /// The phone's own read (nil: it wasn't sure, so it would have fallen back to CardSight).
        var phone: Answer?
        /// What the phone's text reader saw (name and number), even when it found no match.
        var phoneRead: String?
        var cardSight: Answer?
        /// Both gave the same card.
        var agree: Bool?
    }

    /// Running totals, shown in Settings.
    struct Summary: Codable {
        var scans = 0
        /// The phone was sure.
        var phoneSure = 0
        /// The phone was sure and CardSight gave the same card.
        var agreed = 0
        /// The phone was sure and CardSight gave a different card.
        var disagreed = 0
        var phoneSeconds = 0.0
        var cardSightSeconds = 0.0
        var cardSightCount = 0
    }

    static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Scan tests", isDirectory: true)
    }

    private static let queue = DispatchQueue(label: "corodex.scan-tests")

    static func answer(_ result: ScanResult?, seconds: Double?) -> Answer? {
        guard let c = result?.candidates.first else { return nil }
        return Answer(name: c.product.name, number: c.product.number, set: c.product.setName, productId: c.product.id, seconds: seconds)
    }

    /// Saves one scan's photo and what each scanner said, and adds it to the totals.
    static func save(photo: Data, phone: Answer?, phoneRead: String?, cardSight: Answer?) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let id = stamp.replacingOccurrences(of: ":", with: "-") + "-" + UUID().uuidString.prefix(4)
        let agree: Bool? = (phone?.productId != nil && cardSight?.productId != nil) ? phone?.productId == cardSight?.productId : nil
        let record = Record(id: id, date: stamp, phone: phone, phoneRead: phoneRead, cardSight: cardSight, agree: agree)
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try? photo.write(to: folder.appendingPathComponent("\(id).jpg"))
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try? enc.encode(record).write(to: folder.appendingPathComponent("\(id).json"))
            var s = loadSummary()
            s.scans += 1
            if let phone {
                s.phoneSure += 1
                s.phoneSeconds += phone.seconds ?? 0
                if agree == true { s.agreed += 1 } else if agree == false { s.disagreed += 1 }
            }
            if let cardSight {
                s.cardSightCount += 1
                s.cardSightSeconds += cardSight.seconds ?? 0
            }
            try? enc.encode(s).write(to: folder.appendingPathComponent("summary.json"))
        }
    }

    static func loadSummary() -> Summary {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("summary.json")),
              let s = try? JSONDecoder().decode(Summary.self, from: data) else { return Summary() }
        return s
    }

    /// Deletes every saved test scan.
    static func clear() {
        queue.async { try? FileManager.default.removeItem(at: folder) }
    }
}

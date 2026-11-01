import Foundation

/// Your collection as it was after the last load, kept on the phone so the app opens on it at
/// once (then the fresh data replaces it). One file per account, in Caches (never backed up).
/// A demo never reads or writes one; signing out deletes them all.
struct CollectionSnapshot: Codable, @unchecked Sendable {
    /// Bumped when the shape changes; an older file is ignored and deleted.
    static let currentVersion = 1

    var version: Int = CollectionSnapshot.currentVersion
    var userId: String
    var savedAt: Date
    var holdingRows: [HoldingRow]
    var transactions: [Txn]
    var manualValues: [String: ManualValue]
    var products: [String: Product]
    var prices: [String: Price]
    var history: [String: [PricePoint]]
    var ebayGraded: [String: Double]
    var conditionShares: [String: Double]
    var watchlist: [WatchRow]
    var wishlist: [WishItem]
    var reminders: [String]
    var monthlyBudget: Double?
}

enum SnapshotFile {
    /// Reads, writes and deletes run one after another here, so a save still running can't
    /// land after a sign-out deleted the file.
    private static let queue = DispatchQueue(label: "holo.collection-snapshot", qos: .userInitiated)

    private static var folder: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CollectionSnapshots", isDirectory: true)
    }

    private static func fileURL(for userId: String) -> URL? {
        let safe = String(userId.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" })
        guard !safe.isEmpty else { return nil }
        return folder?.appendingPathComponent("collection-\(safe).json")
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return d
    }

    /// The saved collection for this account, read off the main thread. A file that won't
    /// decode, is from an older version or belongs to someone else is deleted.
    static func read(userId: String) async -> CollectionSnapshot? {
        guard let url = fileURL(for: userId) else { return nil }
        return await withCheckedContinuation { (continuation: CheckedContinuation<CollectionSnapshot?, Never>) in
            Self.queue.async {
                continuation.resume(returning: Self.decode(at: url, userId: userId))
            }
        }
    }

    private static func decode(at url: URL, userId: String) -> CollectionSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let snapshot = try? Self.decoder().decode(CollectionSnapshot.self, from: data),
              snapshot.version == CollectionSnapshot.currentVersion,
              snapshot.userId == userId else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return snapshot
    }

    /// Saves in the background (encoding included). Any other account's file goes.
    static func write(_ snapshot: CollectionSnapshot) {
        guard let url = fileURL(for: snapshot.userId), let folder = Self.folder else { return }
        Self.queue.async {
            guard let data = try? Self.encoder().encode(snapshot) else { return }
            let fm = FileManager.default
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            if let others = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
                for other in others where other.lastPathComponent != url.lastPathComponent { try? fm.removeItem(at: other) }
            }
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    /// Deletes every saved collection (sign-out).
    static func deleteAll() {
        guard let folder = Self.folder else { return }
        Self.queue.async { try? FileManager.default.removeItem(at: folder) }
    }
}

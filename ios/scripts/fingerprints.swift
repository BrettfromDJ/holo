// Card fingerprints, run nightly on a Mac by the "Card fingerprints" GitHub workflow.
// Asks the website for cards without a fingerprint (GET /api/fingerprints), downloads each
// picture, makes its Apple Vision feature print (revision 2, the same the app makes on the
// phone), and sends them back in batches (POST /api/fingerprints). Stops when none are left or
// after MAX_MINUTES. Needs SITE_URL and CRON_SECRET in the environment.
import Foundation
import Vision

let env = ProcessInfo.processInfo.environment
guard let site = env["SITE_URL"].flatMap(URL.init(string:)), let secret = env["CRON_SECRET"], !secret.isEmpty else {
    print("SITE_URL and CRON_SECRET are needed.")
    exit(1)
}
let maxMinutes = Double(env["MAX_MINUTES"] ?? "") ?? 300
let started = Date()

struct Card: Codable { var productId: String; var imageUrl: String }
struct Todo: Codable { var cards: [Card] }
struct Print: Codable { var productId: String; var imageUrl: String; var print: [Float] }

func request(_ path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
    var r = URLRequest(url: site.appendingPathComponent(path), timeoutInterval: 60)
    r.httpMethod = method
    r.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
    if let body { r.httpBody = body; r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
    return r
}

func fingerprint(_ data: Data) -> [Float]? {
    let req = VNGenerateImageFeaturePrintRequest()
    req.revision = VNGenerateImageFeaturePrintRequestRevision2
    let handler = VNImageRequestHandler(data: data, options: [:])
    guard (try? handler.perform([req])) != nil, let obs = req.results?.first else { return nil }
    guard obs.elementType == .float else { return nil }
    return obs.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
}

var total = 0, failed = 0, seenDims = Set<Int>()
var skipped = Set<String>()
while Date().timeIntervalSince(started) < maxMinutes * 60 {
    var todoURL = request("api/fingerprints")
    todoURL.url = URL(string: site.appendingPathComponent("api/fingerprints").absoluteString + "?limit=400")
    guard let (data, resp) = try? await URLSession.shared.data(for: todoURL),
          (resp as? HTTPURLResponse)?.statusCode == 200,
          let todo = try? JSONDecoder().decode(Todo.self, from: data) else {
        print("Couldn't get the list of cards."); exit(1)
    }
    let cards = todo.cards.filter { !skipped.contains($0.productId) }
    if cards.isEmpty { break }
    // Download and fingerprint, 16 at a time.
    var prints: [Print] = []
    await withTaskGroup(of: Print?.self) { group in
        var it = cards.makeIterator()
        func next() -> Card? { it.next() }
        for _ in 0..<16 { if let c = next() { group.addTask { await make(c) } } }
        while let r = await group.next() {
            if let r { prints.append(r) }
            if let c = next() { group.addTask { await make(c) } }
        }
    }
    let made = Set(prints.map(\.productId))
    for c in cards where !made.contains(c.productId) { skipped.insert(c.productId); failed += 1 }
    for p in prints { seenDims.insert(p.print.count) }
    for chunk in stride(from: 0, to: prints.count, by: 100).map({ Array(prints[$0..<min($0 + 100, prints.count)]) }) {
        let body = try! JSONEncoder().encode(["prints": chunk])
        let (_, r) = (try? await URLSession.shared.data(for: request("api/fingerprints", method: "POST", body: body))) ?? (Data(), nil)
        guard (r as? HTTPURLResponse)?.statusCode == 200 else { print("Saving failed."); exit(1) }
        total += chunk.count
    }
    print("Fingerprinted \(total) so far (\(failed) pictures couldn't be read).")
}
print("Done: \(total) cards fingerprinted, \(failed) skipped. Fingerprint size: \(seenDims.sorted()).")

func make(_ card: Card) async -> Print? {
    guard let url = URL(string: card.imageUrl),
          let (data, resp) = try? await URLSession.shared.data(from: url),
          (resp as? HTTPURLResponse)?.statusCode == 200,
          let print = fingerprint(data) else { return nil }
    return Print(productId: card.productId, imageUrl: card.imageUrl, print: print)
}

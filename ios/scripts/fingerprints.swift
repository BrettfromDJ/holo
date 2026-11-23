// Card fingerprints, run nightly on a Mac by the "Card fingerprints" GitHub workflow.
// Asks the website for cards without a fingerprint (GET /api/fingerprints), downloads each
// picture, makes its Apple Vision feature print (revision 2, the same the app makes on the
// phone), and sends them back in batches (POST /api/fingerprints). Stops when none are left or
// after MAX_MINUTES. Needs SITE_URL and CRON_SECRET in the environment.
import Foundation
import Vision

// Each line shows in the GitHub log as it happens (a pipe would otherwise hold it all back until
// the end, and a run that's stopped would show nothing at all).
setvbuf(stdout, nil, _IOLBF, 0)
func log(_ line: String) { print(line); fflush(stdout) }

let env = ProcessInfo.processInfo.environment
guard let site = env["SITE_URL"].flatMap(URL.init(string:)), let secret = env["CRON_SECRET"], !secret.isEmpty else {
    print("SITE_URL and CRON_SECRET are needed.")
    exit(1)
}
let maxMinutes = Double(env["MAX_MINUTES"] ?? "") ?? 300
let started = Date()
func timeUp() -> Bool { Date().timeIntervalSince(started) >= maxMinutes * 60 }

// No request may hang: 30 s to start answering, 90 s for the whole thing.
let session: URLSession = {
    let c = URLSessionConfiguration.ephemeral
    c.timeoutIntervalForRequest = 30
    c.timeoutIntervalForResource = 90
    c.httpMaximumConnectionsPerHost = 16
    return URLSession(configuration: c)
}()
log("Fingerprinting cards for \(Int(maxMinutes)) minutes at most, from \(site.host ?? "the site").")

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
var batch = 0
while !timeUp() {
    batch += 1
    var todoURL = request("api/fingerprints")
    todoURL.url = URL(string: site.appendingPathComponent("api/fingerprints").absoluteString + "?limit=400")
    let listStart = Date()
    let fetched = try? await session.data(for: todoURL)
    let status = (fetched?.1 as? HTTPURLResponse)?.statusCode
    guard let data = fetched?.0, status == 200, let todo = try? JSONDecoder().decode(Todo.self, from: data) else {
        log("Couldn't get the list of cards (HTTP \(status.map(String.init) ?? "no answer")): \(String(data: fetched?.0 ?? Data(), encoding: .utf8)?.prefix(300) ?? "")")
        exit(1)
    }
    let cards = todo.cards.filter { !skipped.contains($0.productId) }
    log("Batch \(batch): \(cards.count) cards to do (list took \(Int(Date().timeIntervalSince(listStart))) s).")
    if cards.isEmpty { break }
    // Download and fingerprint, 16 at a time.
    var prints: [Print] = []
    await withTaskGroup(of: Print?.self) { group in
        var it = cards.makeIterator()
        func next() -> Card? { it.next() }
        for _ in 0..<16 { if let c = next() { group.addTask { await make(c) } } }
        while let r = await group.next() {
            if let r { prints.append(r) }
            // Out of time: finish what's running, start nothing new.
            if !timeUp(), let c = next() { group.addTask { await make(c) } }
        }
    }
    let made = Set(prints.map(\.productId))
    // Cards not tried because time ran out aren't failures.
    if !timeUp() { for c in cards where !made.contains(c.productId) { skipped.insert(c.productId); failed += 1 } }
    for p in prints { seenDims.insert(p.print.count) }
    for chunk in stride(from: 0, to: prints.count, by: 100).map({ Array(prints[$0..<min($0 + 100, prints.count)]) }) {
        let body = try! JSONEncoder().encode(["prints": chunk])
        let saved = try? await session.data(for: request("api/fingerprints", method: "POST", body: body))
        let code = (saved?.1 as? HTTPURLResponse)?.statusCode
        guard code == 200 else {
            log("Saving failed (HTTP \(code.map(String.init) ?? "no answer")): \(String(data: saved?.0 ?? Data(), encoding: .utf8)?.prefix(300) ?? "")")
            exit(1)
        }
        total += chunk.count
    }
    log("Fingerprinted \(total) so far (\(failed) pictures couldn't be read), \(Int(Date().timeIntervalSince(started) / 60)) min in.")
}
log("Done: \(total) cards fingerprinted, \(failed) skipped. Fingerprint size: \(seenDims.sorted()).")

func make(_ card: Card) async -> Print? {
    guard let url = URL(string: card.imageUrl),
          let (data, resp) = try? await session.data(from: url),
          (resp as? HTTPURLResponse)?.statusCode == 200,
          let print = fingerprint(data) else { return nil }
    return Print(productId: card.productId, imageUrl: card.imageUrl, print: print)
}

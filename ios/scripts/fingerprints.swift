// Card fingerprints, run nightly on a Mac by the "Card fingerprints" GitHub workflow.
// Asks the website for cards without a fingerprint (GET /api/fingerprints), downloads each
// picture, makes its Apple Vision feature print (revision 2, the same the app makes on the
// phone), and sends them back in batches (POST /api/fingerprints). Stops when none are left or
// after MAX_MINUTES. Needs SITE_URL and CRON_SECRET in the environment.
import Foundation
import Vision
import AppKit

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
struct Todo: Codable { var cards: [Card]; var next: String? }
struct Print: Codable { var productId: String; var imageUrl: String; var print: [Float] }

func request(_ path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
    var r = URLRequest(url: site.appendingPathComponent(path), timeoutInterval: 60)
    r.httpMethod = method
    r.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
    if let body { r.httpBody = body; r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
    return r
}

/// One at a time, on its own thread: Vision on GitHub's virtual Macs stalled when many pictures
/// were fingerprinted at once, and holding a lock inside Swift's shared task threads (the last
/// try) froze the whole run (16 downloads blocked those few threads waiting for the lock, so
/// nothing could finish). Vision now runs on one plain queue the tasks wait on without blocking.
let visionQueue = DispatchQueue(label: "vision")

func fingerprintAsync(_ data: Data) async -> [Float]? {
    await withCheckedContinuation { done in visionQueue.async { done.resume(returning: fingerprint(data)) } }
}

func fingerprint(_ data: Data) -> [Float]? {
    let req = VNGenerateImageFeaturePrintRequest()
    req.revision = VNGenerateImageFeaturePrintRequestRevision2
    // The processor only: the virtual Mac has no graphics chip or neural engine to hand it to.
    req.usesCPUOnly = true
    let handler = VNImageRequestHandler(data: data, options: [:])
    guard (try? handler.perform([req])) != nil, let obs = req.results?.first else { return nil }
    guard obs.elementType == .float else { return nil }
    return obs.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
}

// A quick check that Vision works here at all, before any downloads.
do {
    let t0 = Date()
    let size = 64
    var px = [UInt8](repeating: 0, count: size * size * 4)
    for i in stride(from: 0, to: px.count, by: 4) { px[i] = UInt8(i % 255); px[i + 1] = 128; px[i + 2] = UInt8((i / 7) % 255); px[i + 3] = 255 }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32)!
    px.withUnsafeBytes { memcpy(rep.bitmapData!, $0.baseAddress!, px.count) }
    let png = rep.representation(using: .png, properties: [:])!
    let test = fingerprint(png)
    log("Vision check: \(test == nil ? "FAILED" : "ok, \(test!.count) numbers") in \(String(format: "%.1f", Date().timeIntervalSince(t0))) s.")
    if test == nil { exit(1) }
}

/// Why pictures couldn't be read, tallied for the end of the run (and the first few named).
/// Declared before the loop: a script's top-level lines run in order, and using these before
/// this line ran crashed the run (segmentation fault).
let reasonLock = NSLock()
var reasons: [String: Int] = [:]
var examples: [String] = []

// Safety stops, so a stuck run ends in minutes instead of using up GitHub's 5½ hours:
// nothing finished for 10 minutes ends it (what's saved stays saved), and so does running
// 15 minutes past MAX_MINUTES.
let progressLock = NSLock()
var lastProgress = Date()
func noteProgress() { progressLock.lock(); lastProgress = Date(); progressLock.unlock() }
let watchdog = DispatchSource.makeTimerSource(queue: .global())
watchdog.schedule(deadline: .now() + 60, repeating: 60)
watchdog.setEventHandler {
    progressLock.lock(); let idle = Date().timeIntervalSince(lastProgress); progressLock.unlock()
    if idle > 600 { log("Stuck: nothing finished for \(Int(idle / 60)) minutes. Stopping (what's saved stays saved)."); exit(1) }
    if Date().timeIntervalSince(started) > (maxMinutes + 15) * 60 { log("Over time. Stopping."); exit(0) }
}
watchdog.resume()

var total = 0, failed = 0, seenDims = Set<Int>()
var skipped = Set<String>()
var batch = 0
// The website walks the catalog from a bookmark: each list carries on where the last one ended
// (the one big "what's left" query timed out once most cards were done).
var after: String? = ""
while !timeUp(), let cursor = after {
    batch += 1
    var parts = URLComponents(url: site.appendingPathComponent("api/fingerprints"), resolvingAgainstBaseURL: false)!
    parts.queryItems = [URLQueryItem(name: "limit", value: "200"), URLQueryItem(name: "after", value: cursor)]
    var todoURL = request("api/fingerprints")
    todoURL.url = parts.url
    let listStart = Date()
    // A hiccup (a slow database moment) is tried again, three times, before giving up.
    var todo: Todo?
    for attempt in 1...4 {
        let fetched = try? await session.data(for: todoURL)
        let status = (fetched?.1 as? HTTPURLResponse)?.statusCode
        if let data = fetched?.0, status == 200, let t = try? JSONDecoder().decode(Todo.self, from: data) { todo = t; break }
        log("Couldn't get the list of cards (HTTP \(status.map(String.init) ?? "no answer")): \(String(data: fetched?.0 ?? Data(), encoding: .utf8)?.prefix(300) ?? "")\(attempt < 4 ? ", trying again" : "")")
        if attempt < 4 { try? await Task.sleep(nanoseconds: UInt64(attempt) * 20_000_000_000) }
    }
    guard let todo else { exit(1) }
    after = todo.next
    // Pictures that couldn't be read stay on the website's list (they have no fingerprint), so
    // ask for that many more and step past them; otherwise they'd fill the list and end the run
    // early with cards still to do.
    let cards = todo.cards.filter { !skipped.contains($0.productId) }
    noteProgress()
    log("Batch \(batch): \(cards.count) cards to do (list took \(Int(Date().timeIntervalSince(listStart))) s).")
    if cards.isEmpty { continue }
    // Download and fingerprint, 16 at a time.
    var prints: [Print] = []
    await withTaskGroup(of: Print?.self) { group in
        var it = cards.makeIterator()
        func next() -> Card? { it.next() }
        for _ in 0..<16 { if let c = next() { group.addTask { await make(c) } } }
        var done = 0
        let batchStart = Date()
        while let r = await group.next() {
            if let r { prints.append(r) }
            done += 1
            noteProgress()
            // Progress inside a batch, so a slow step shows in the log.
            if done % 25 == 0 { log("  \(done)/\(cards.count) pictures done (\(prints.count) fingerprinted), \(Int(Date().timeIntervalSince(batchStart))) s into the batch.") }
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
        // A blip (no answer, a slow moment) is tried again, three times, before giving up; a run
        // stopped on one dropped save after 25,000 cards.
        var savedOK = false
        for attempt in 1...4 {
            let saved = try? await session.data(for: request("api/fingerprints", method: "POST", body: body))
            let code = (saved?.1 as? HTTPURLResponse)?.statusCode
            if code == 200 { savedOK = true; break }
            log("Saving failed (HTTP \(code.map(String.init) ?? "no answer")): \(String(data: saved?.0 ?? Data(), encoding: .utf8)?.prefix(300) ?? "")\(attempt < 4 ? ", trying again" : "")")
            if attempt < 4 { try? await Task.sleep(nanoseconds: UInt64(attempt) * 20_000_000_000) }
        }
        guard savedOK else { exit(1) }
        total += chunk.count
        noteProgress()
    }
    log("Fingerprinted \(total) so far (\(failed) pictures couldn't be read), \(Int(Date().timeIntervalSince(started) / 60)) min in.")
}
log("Done: \(total) cards fingerprinted, \(failed) skipped. Fingerprint size: \(seenDims.sorted()).")
if !reasons.isEmpty {
    log("Why pictures couldn't be read: " + reasons.sorted { $0.value > $1.value }.map { "\($0.value) \($0.key)" }.joined(separator: " · "))
    log("First few:")
    for e in examples { log("  " + e) }
}

func fail(_ card: Card, _ why: String) -> Print? {
    reasonLock.lock()
    reasons[why, default: 0] += 1
    if examples.count < 25 { examples.append("\(why): \(card.productId) \(card.imageUrl)") }
    reasonLock.unlock()
    return nil
}

func make(_ card: Card) async -> Print? {
    guard let url = URL(string: card.imageUrl) else { return fail(card, "bad picture link") }
    let fetched: (Data, URLResponse)
    do { fetched = try await session.data(from: url) } catch {
        let code = (error as? URLError)?.code
        return fail(card, code == .timedOut ? "timed out" : "download failed (\(code.map { "\($0.rawValue)" } ?? "error"))")
    }
    let status = (fetched.1 as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else {
        let why = status == 404 || status == 410 ? "not found (\(status))"
            : status == 403 ? "refused (403)"
            : status == 429 ? "too many requests (429)"
            : "server said \(status)"
        return fail(card, why)
    }
    if fetched.0.count < 200 { return fail(card, "empty picture") }
    guard let print = await fingerprintAsync(fetched.0) else { return fail(card, "picture Vision couldn't read (\(fetched.1.mimeType ?? "unknown type"))") }
    return Print(productId: card.productId, imageUrl: card.imageUrl, print: print)
}

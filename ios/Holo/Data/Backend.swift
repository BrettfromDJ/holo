import Foundation
import Supabase

/// The shared Supabase client (sign-in and your collection, protected per user)
/// and the web app's API (scanning, search, catalog), used with the same login.
final class Backend {
    static let shared = Backend()

    let supabase: SupabaseClient
    let api: HoloAPI

    private init() {
        supabase = SupabaseClient(supabaseURL: AppConfig.supabaseURL, supabaseKey: AppConfig.supabaseAnonKey)
        api = HoloAPI(base: AppConfig.apiBaseURL, supabase: supabase)
    }
}

enum HoloError: LocalizedError {
    case server(code: String?, message: String)
    case signedOut

    var errorDescription: String? {
        switch self {
        case let .server(_, message): return message
        case .signedOut: return "Sign in again to continue."
        }
    }

    var code: String? {
        if case let .server(code, _) = self { return code }
        return nil
    }
}

/// The web app's API routes, called with the signed-in user's token.
final class HoloAPI {
    private let base: URL
    private let supabase: SupabaseClient
    private let session = URLSession(configuration: .default)
    private let decoder = JSONDecoder()

    init(base: URL, supabase: SupabaseClient) {
        self.base = base
        self.supabase = supabase
    }

    private func request(_ path: String, query: [URLQueryItem] = []) async throws -> URLRequest {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var req = URLRequest(url: components.url!)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = try? await supabase.auth.session.accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private func send<T: Decodable>(_ req: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = try? decoder.decode(APIErrorBody.self, from: data)
            throw HoloError.server(code: body?.error?.code, message: body?.error?.message ?? "Something went wrong (\(status)).")
        }
        return try decoder.decode(T.self, from: data)
    }

    /// One page of the stored catalog's matches, with how many there are in all.
    /// `count` is how many the server sent (before code cards are left out), for the next offset.
    func searchPage(_ query: String, offset: Int, limit: Int) async throws -> (hits: [SearchHit], total: Int, count: Int) {
        struct Page: Decodable { var products: [SearchHit]; var total: Int? }
        let items = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "offset", value: "\(offset)"), URLQueryItem(name: "limit", value: "\(limit)")]
        let page = try await send(try await request("api/explore/search", query: items), as: Page.self)
        let hits = page.products.filter { !$0.product.isCodeCard }
        return (hits, page.total ?? (offset + page.products.count), page.products.count)
    }

    /// Search the stored catalog (free: no TCG API calls).
    func search(_ query: String) async throws -> [SearchHit] {
        try await searchPage(query, offset: 0, limit: 80).hits
    }

    /// Search TCG API live, for things the stored catalog doesn't have yet. Each call is a paid
    /// TCG API request, so only call it when someone asks for it (never while typing).
    func liveSearch(_ query: String) async throws -> [SearchHit] {
        struct Live: Decodable { var hits: [SearchHit] }
        let q = URLQueryItem(name: "q", value: query)
        let live = try await send(
            try await request("api/tcg/search", query: [q, URLQueryItem(name: "type", value: "all"), URLQueryItem(name: "game", value: "all")]),
            as: Live.self
        )
        return live.hits.filter { !$0.product.isCodeCard }
    }

    /// Save a product to the shared catalog (needed before it can be added) and get its prices.
    func importProduct(_ product: Product, printing: String?) async throws -> CatalogImport {
        var req = try await request("api/catalog")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["productId": product.id, "kind": product.kind]
        body["printing"] = printing ?? NSNull()
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(req, as: CatalogImport.self)
    }

    /// Identify the card, slab or sealed product in a photo. Uses one scan.
    func scan(jpeg: Data) async throws -> ScanResult {
        var req = try await request("api/scan")
        req.httpMethod = "POST"
        req.timeoutInterval = 75
        let boundary = "holo-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"image\"; filename=\"scan.jpg\"\r\n".utf8))
        body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        body.append(jpeg)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        req.httpBody = body
        return try await send(req, as: ScanResult.self)
    }

    // MARK: Explore and market data (stored catalog; eBay and conditions are cached 12h at the CDN)

    func exploreIndex() async throws -> ExploreIndex {
        try await send(try await request("api/explore"), as: ExploreIndex.self)
    }

    func exploreSet(_ slug: String) async throws -> ExploreSetDetail {
        var detail = try await send(try await request("api/explore/sets/\(slug)"), as: ExploreSetDetail.self)
        detail.products.removeAll { $0.product.isCodeCard }
        return detail
    }

    /// A product's full price history. Free when Holo already has it; otherwise the server asks
    /// TCG API once (signed in only) and saves it for everyone, so it's never paid for twice.
    func priceHistory(_ id: String, printing: String?) async throws -> (points: [PricePoint], available: Bool, reason: String?) {
        struct Body: Encodable { var printing: String? }
        struct Reply: Decodable { var points: [PricePoint]?; var available: Bool?; var reason: String? }
        var req = try await request("api/explore/products/\(id)/history")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(Body(printing: printing))
        let reply = try await send(req, as: Reply.self)
        return (reply.points ?? [], reply.available ?? true, reply.reason)
    }

    /// PriceCharting's graded values for products (stored nightly on the server: no API cost).
    func gradedValues(_ productIds: [String]) async throws -> [String: GradedValues] {
        struct Body: Decodable { var graded: [String: GradedValues] }
        let q = URLQueryItem(name: "ids", value: productIds.joined(separator: ","))
        return try await send(try await request("api/graded", query: [q]), as: Body.self).graded
    }

    func catalogProduct(_ id: String) async throws -> CatalogProduct {
        // appendingPathComponent escapes what needs escaping; ":" is fine in a path.
        return try await send(try await request("api/explore/products/\(id)"), as: CatalogProduct.self)
    }

    func ebaySales(_ productId: String, printing: String?) async throws -> EbaySales? {
        struct Body: Decodable { var ebay: EbaySales? }
        let q = printing.map { [URLQueryItem(name: "printing", value: $0)] } ?? []
        return try await send(try await request("api/tcg/products/\(productId)/ebay", query: q), as: Body.self).ebay
    }

    func conditionPrices(_ productId: String, printing: String?) async throws -> [ConditionPrice] {
        struct Body: Decodable { var conditions: [ConditionPrice] }
        let q = printing.map { [URLQueryItem(name: "printing", value: $0)] } ?? []
        return try await send(try await request("api/tcg/products/\(productId)/conditions", query: q), as: Body.self).conditions
    }

    /// eBay summaries for many cards in one request (by product id).
    func ebaySummaries(_ productIds: [String]) async throws -> [String: [EbaySummary]] {
        struct Body: Decodable { var ebay: [String: [EbaySummary]] }
        guard !productIds.isEmpty else { return [:] }
        let q = [URLQueryItem(name: "ids", value: productIds.sorted().joined(separator: ","))]
        return try await send(try await request("api/tcg/ebay", query: q), as: Body.self).ebay
    }

    struct PushTestResult: Decodable {
        var sent: Int
        var failed: Int
        var reasons: [String]
    }

    /// Ask the server to send a test notification to your phones.
    func testPush() async throws -> PushTestResult {
        var req = try await request("api/push/test")
        req.httpMethod = "POST"
        return try await send(req, as: PushTestResult.self)
    }

    /// Scans left on the account (free to ask).
    func scansRemaining() async -> Int? {
        struct Balance: Decodable { var scansRemaining: Int? }
        guard let req = try? await request("api/scan") else { return nil }
        return (try? await send(req, as: Balance.self))?.scansRemaining
    }
}

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

    /// Search the stored catalog first (free); fall back to a live search when it has nothing.
    func search(_ query: String) async throws -> [SearchHit] {
        struct Stored: Decodable { var products: [SearchHit] }
        struct Live: Decodable { var hits: [SearchHit] }
        let q = URLQueryItem(name: "q", value: query)
        let stored = try? await send(try await request("api/explore/search", query: [q]), as: Stored.self)
        if let hits = stored?.products, !hits.isEmpty { return hits }
        let live = try await send(
            try await request("api/tcg/search", query: [q, URLQueryItem(name: "type", value: "all"), URLQueryItem(name: "game", value: "all")]),
            as: Live.self
        )
        return live.hits
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

    /// Scans left on the account (free to ask).
    func scansRemaining() async -> Int? {
        struct Balance: Decodable { var scansRemaining: Int? }
        guard let req = try? await request("api/scan") else { return nil }
        return (try? await send(req, as: Balance.self))?.scansRemaining
    }
}

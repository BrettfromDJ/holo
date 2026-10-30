import Foundation
import Supabase

/// Small per-user JSON values in the user_state table, the same ones the website keeps
/// (wishlist, the deal in progress, closed deals…), so both stay in sync.
enum UserState {
    static func load<T: Decodable>(_ key: String, as type: T.Type) async throws -> T? {
        let rows: [UserStateValue<T>] = try await Backend.shared.supabase
            .from("user_state").select("value").eq("key", value: key).limit(1).execute().value
        return rows.first?.value
    }

    static func save<T: Codable>(_ key: String, _ value: T, userId: String) async throws {
        let row = UserStateRow(user_id: userId, key: key, value: value, updated_at: ISO8601DateFormatter().string(from: Date()))
        try await Backend.shared.supabase.from("user_state").upsert(row).execute()
    }
}

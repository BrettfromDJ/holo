import Foundation

/// Settings baked in at build time from Config.xcconfig (via Info.plist).
enum AppConfig {
    private static func value(_ key: String) -> String {
        let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // An unset build setting comes through as the literal "$(NAME)".
        return trimmed.hasPrefix("$(") ? "" : trimmed
    }

    static var apiHost: String { value("HoloAPIHost") }
    static var supabaseHost: String { value("SupabaseHost") }
    static var supabaseAnonKey: String { value("SupabaseAnonKey") }

    static var isConfigured: Bool { !apiHost.isEmpty && !supabaseHost.isEmpty && !supabaseAnonKey.isEmpty }

    static var apiBaseURL: URL { URL(string: "https://\(apiHost)")! }
    static var supabaseURL: URL { URL(string: "https://\(supabaseHost)")! }
}

import Foundation

struct HakaConfiguration: Sendable {
    let supabaseURL: URL
    let anonKey: String

    static func load(bundle: Bundle = .main) throws -> HakaConfiguration {
        let environment = ProcessInfo.processInfo.environment
        let rawURL = environment["SUPABASE_URL"]
            ?? bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String
            ?? ""
        let rawKey = environment["SUPABASE_ANON_KEY"]
            ?? bundle.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
            ?? ""
        let urlText = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: urlText), url.scheme == "https", !key.isEmpty else {
            throw HakaError.configuration(
                "Add SUPABASE_URL and SUPABASE_ANON_KEY to ios/Config/Secrets.xcconfig."
            )
        }
        return HakaConfiguration(supabaseURL: url, anonKey: key)
    }
}

enum HakaError: LocalizedError, Equatable {
    case configuration(String)
    case api(code: String, message: String)
    case invalidResponse
    case missingSession
    case oauthCancelled

    var errorDescription: String? {
        switch self {
        case .configuration(let message), .api(_, let message): message
        case .invalidResponse: "Haka received an unreadable response."
        case .missingSession: "Your session expired. Please sign in again."
        case .oauthCancelled: "Sign in was cancelled."
        }
    }
}

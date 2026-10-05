import AuthenticationServices
import Foundation
import UIKit

final class HakaAPI: NSObject, @unchecked Sendable {
    private let configuration: HakaConfiguration
    private let sessionStore: SessionStore
    private let urlSession: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let lock = NSLock()
    private var session: AuthSession?
    private var oauthSession: ASWebAuthenticationSession?

    init(configuration: HakaConfiguration, sessionStore: SessionStore = SessionStore(), urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.sessionStore = sessionStore
        self.urlSession = urlSession
        self.session = sessionStore.load()
    }

    var hasSession: Bool {
        lock.lock(); defer { lock.unlock() }
        return session != nil
    }

    var userID: String? {
        lock.lock(); defer { lock.unlock() }
        return session?.user.id
    }

    func signInAnonymously() async throws {
        var request = try authRequest(path: "signup")
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        let response: AuthWireResponse = try await send(request)
        try store(response.session)
    }

    @MainActor
    func signInWithGoogle() async throws {
        var components = URLComponents(url: configuration.supabaseURL.appendingPathComponent("auth/v1/authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: "haka://auth/callback"),
        ]
        guard let url = components.url else { throw HakaError.invalidResponse }
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "haka") { url, error in
                if let url { continuation.resume(returning: url) }
                else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    continuation.resume(throwing: HakaError.oauthCancelled)
                } else {
                    continuation.resume(throwing: error ?? HakaError.invalidResponse)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.oauthSession = session
            session.start()
        }
        let values = Self.callbackValues(callback)
        guard let access = values["access_token"],
              let refresh = values["refresh_token"],
              let expiresText = values["expires_in"],
              let expires = TimeInterval(expiresText) else { throw HakaError.invalidResponse }
        let user = try await fetchUser(accessToken: access)
        try store(AuthSession(accessToken: access, refreshToken: refresh, expiresAt: .now.addingTimeInterval(expires), user: user))
    }

    @MainActor
    func linkGoogleIdentity() async throws {
        let auth = try await validSession()
        var components = URLComponents(
            url: configuration.supabaseURL.appendingPathComponent("auth/v1/user/identities/authorize"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: "haka://auth/callback"),
            URLQueryItem(name: "skip_http_redirect", value: "true"),
        ]
        guard let url = components.url else { throw HakaError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        let response: OAuthURLResponse = try await send(request)
        guard let providerURL = URL(string: response.url) else { throw HakaError.invalidResponse }
        let callback = try await openOAuth(providerURL)
        let values = Self.callbackValues(callback)
        if let access = values["access_token"],
           let refresh = values["refresh_token"],
           let expiresText = values["expires_in"],
           let expires = TimeInterval(expiresText) {
            let user = try await fetchUser(accessToken: access)
            try store(AuthSession(accessToken: access, refreshToken: refresh, expiresAt: .now.addingTimeInterval(expires), user: user))
        }
    }

    func signOut() async {
        if let token = currentSession()?.accessToken {
            var request = try? authRequest(path: "logout")
            request?.httpMethod = "POST"
            request?.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let request { _ = try? await urlSession.data(for: request) }
        }
        lock.withLock { session = nil }
        sessionStore.clear()
    }

    func createCouple(displayName: String?) async throws -> CreateCoupleResponse {
        try await function("create-couple", body: CreateCoupleRequest(timezone: TimeZone.current.identifier, displayName: displayName?.nilIfBlank))
    }

    func redeemInvite(code: String) async throws -> RedeemInviteResponse {
        try await function("redeem-invite", body: RedeemInviteRequest(code: code))
    }

    func bootstrap() async throws -> BootstrapResponse {
        try await function("get-bootstrap", body: EmptyBody())
    }

    func tap(coupleId: String, tapId: String = UUID().uuidString.lowercased()) async throws -> TapResult {
        try await function("tap-heart", body: TapHeartRequest(coupleId: coupleId, tapId: tapId))
    }

    func thinkingOfYou(coupleId: String) async throws -> ThinkingOfYouResult {
        try await function("thinking-of-you", body: ThinkingOfYouRequest(coupleId: coupleId, eventId: UUID().uuidString.lowercased()))
    }

    func sendLoveNote(coupleId: String, body: String) async throws -> LoveNoteResponse {
        try await function("send-love-note", body: LoveNoteRequest(coupleId: coupleId, body: body))
    }

    func loveNotes(coupleId: String) async throws -> [LoveNoteDTO] {
        let response: LoveNotesResponse = try await function("get-love-notes", body: LoveNoteRequest(coupleId: coupleId, body: ""))
        return response.notes
    }

    func setMood(coupleId: String, mood: String) async throws {
        let _: MoodResponse = try await function("set-mood", body: MoodRequest(coupleId: coupleId, mood: mood))
    }

    func moods(coupleId: String) async throws -> MoodResponse {
        try await function("get-mood", body: MoodRequest(coupleId: coupleId, mood: ""))
    }

    func story(_ body: StoryRequest) async throws -> StoryResponse {
        try await function("relationship-story", body: body)
    }

    func storyCommand(_ body: StoryRequest) async throws {
        try await functionDiscardingResponse("relationship-story", body: body)
    }

    private func functionDiscardingResponse<Body: Encodable>(_ name: String, body: Body) async throws {
        let auth = try await validSession()
        var request = URLRequest(url: configuration.supabaseURL.appendingPathComponent("functions/v1/\(name)"))
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw HakaError.invalidResponse
        }
    }

    private func function<Response: Decodable, Body: Encodable>(_ name: String, body: Body, retry: Bool = true) async throws -> Response {
        let auth = try await validSession()
        var request = URLRequest(url: configuration.supabaseURL.appendingPathComponent("functions/v1/\(name)"))
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        do {
            return try await send(request)
        } catch HakaError.api(let code, _) where retry && (code == "UNAUTHORIZED" || code == "AUTH_ERROR") {
            try await refreshSession()
            return try await function(name, body: body, retry: false)
        }
    }

    private func validSession() async throws -> AuthSession {
        guard let value = currentSession() else { throw HakaError.missingSession }
        if value.needsRefresh {
            try await refreshSession()
            guard let refreshed = currentSession() else { throw HakaError.missingSession }
            return refreshed
        }
        return value
    }

    private func refreshSession() async throws {
        guard let old = currentSession() else { throw HakaError.missingSession }
        var request = try authRequest(path: "token")
        var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        request.url = components.url
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(["refresh_token": old.refreshToken])
        let response: AuthWireResponse = try await send(request)
        try store(response.session)
    }

    private func fetchUser(accessToken: String) async throws -> AuthUser {
        var request = try authRequest(path: "user")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await send(request)
    }

    private func authRequest(path: String) throws -> URLRequest {
        var request = URLRequest(url: configuration.supabaseURL.appendingPathComponent("auth/v1/\(path)"))
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(configuration.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HakaError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? decoder.decode(ErrorEnvelope.self, from: data)
            throw HakaError.api(
                code: envelope?.error.code ?? "HTTP_\(http.statusCode)",
                message: envelope?.error.message ?? String(data: data, encoding: .utf8) ?? "Request failed."
            )
        }
        if Response.self == GenericResponse.self, data.isEmpty {
            return GenericResponse(ok: true) as! Response
        }
        return try decoder.decode(Response.self, from: data)
    }

    private func currentSession() -> AuthSession? {
        lock.lock(); defer { lock.unlock() }
        return session
    }

    private func store(_ newSession: AuthSession) throws {
        try sessionStore.save(newSession)
        lock.lock(); session = newSession; lock.unlock()
    }

    private static func callbackValues(_ url: URL) -> [String: String] {
        let raw = [url.query, url.fragment].compactMap { $0 }.joined(separator: "&")
        return raw.split(separator: "&").reduce(into: [:]) { result, pair in
            let pieces = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { return }
            result[pieces[0]] = pieces[1].removingPercentEncoding ?? pieces[1]
        }
    }

    @MainActor
    private func openOAuth(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "haka") { url, error in
                if let url { continuation.resume(returning: url) }
                else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    continuation.resume(throwing: HakaError.oauthCancelled)
                } else {
                    continuation.resume(throwing: error ?? HakaError.invalidResponse)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            oauthSession = session
            session.start()
        }
    }
}

extension HakaAPI: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

private struct EmptyBody: Codable {}
private struct GenericResponse: Codable { let ok: Bool? }
private struct ErrorEnvelope: Codable { let error: APIErrorBody }
private struct APIErrorBody: Codable { let code: String; let message: String }
private struct OAuthURLResponse: Codable { let url: String }

private struct AuthWireResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval
    let user: AuthUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }

    var session: AuthSession {
        AuthSession(accessToken: accessToken, refreshToken: refreshToken, expiresAt: .now.addingTimeInterval(expiresIn), user: user)
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

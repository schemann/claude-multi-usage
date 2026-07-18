import Foundation
import CryptoKit

/// Standalone OAuth PKCE + refresh, mirroring how claude-usage-bar authenticates.
/// Each account gets its own token chain here, independent of Claude Code.
enum OAuthService {
    static let clientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let redirectURI = "https://platform.claude.com/oauth/code/callback"
    static let scopes = ["user:profile", "user:inference"]

    static let authorizeEndpoint = URL(string: "https://claude.ai/oauth/authorize")!
    static let tokenEndpoint = URL(string: "https://platform.claude.com/v1/oauth/token")!
    static let profileEndpoint = URL(string: "https://api.anthropic.com/api/oauth/profile")!

    enum RefreshResult {
        case success(StoredCredentials)
        case permanentFailure   // 4xx — refresh token dead, re-login needed
        case transientFailure   // network/5xx — retry later
    }

    // MARK: PKCE

    struct PKCE {
        let verifier: String
        let challenge: String
        let state: String
    }

    static func makePKCE() -> PKCE {
        let verifier = randomToken()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
        return PKCE(verifier: verifier, challenge: challenge, state: randomToken())
    }

    static func authorizeURL(_ pkce: PKCE) -> URL {
        var components = URLComponents(url: authorizeEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: pkce.state),
        ]
        return components.url!
    }

    // MARK: Token exchange

    /// rawCode is the "code#state" string pasted from the browser.
    static func exchangeCode(_ rawCode: String, pkce: PKCE) async -> StoredCredentials? {
        let parts = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "#", maxSplits: 1)
        guard let code = parts.first.map(String.init), !code.isEmpty else { return nil }
        if parts.count > 1, String(parts[1]) != pkce.state { return nil }

        let body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "state": pkce.state,
            "client_id": clientId,
            "redirect_uri": redirectURI,
            "code_verifier": pkce.verifier,
        ]
        guard let json = await post(tokenEndpoint, body: body) else { return nil }
        return credentials(from: json, fallback: nil)
    }

    // MARK: Refresh

    static func refresh(_ current: StoredCredentials) async -> RefreshResult {
        guard let refreshToken = current.refreshToken, !refreshToken.isEmpty else {
            return .permanentFailure
        }
        var body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientId,
        ]
        if !current.scopes.isEmpty {
            body["scope"] = current.scopes.joined(separator: " ")
        }

        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .transientFailure }
            guard http.statusCode == 200 else {
                return (400..<500).contains(http.statusCode) ? .permanentFailure : .transientFailure
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let updated = credentials(from: json, fallback: current) else {
                return .transientFailure
            }
            return .success(updated)
        } catch {
            return .transientFailure
        }
    }

    // MARK: Userinfo

    static func fetchEmail(token: String) async -> String? {
        var request = URLRequest(url: profileEndpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        // Shape: { "account": { "email": "...", "full_name": "...", ... } }
        let account = json["account"] as? [String: Any]
        if let email = account?["email"] as? String, !email.isEmpty { return email }
        if let name = account?["full_name"] as? String, !name.isEmpty { return name }
        return nil
    }

    // MARK: Helpers

    private static func post(_ url: URL, body: [String: String]) async -> [String: Any]? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func credentials(from json: [String: Any], fallback: StoredCredentials?) -> StoredCredentials? {
        guard let access = json["access_token"] as? String, !access.isEmpty else { return nil }
        let scopeString = json["scope"] as? String
        let scopes = scopeString?.split(whereSeparator: \.isWhitespace).map(String.init)
            ?? fallback?.scopes ?? scopes
        return StoredCredentials(
            accessToken: access,
            refreshToken: (json["refresh_token"] as? String) ?? fallback?.refreshToken,
            expiresAt: expirationDate(from: json["expires_in"]) ?? fallback?.expiresAt,
            scopes: scopes
        )
    }

    private static func expirationDate(from value: Any?) -> Date? {
        let seconds: TimeInterval?
        switch value {
        case let n as NSNumber: seconds = n.doubleValue
        case let n as Double: seconds = n
        case let n as Int: seconds = TimeInterval(n)
        case let s as String: seconds = TimeInterval(s)
        default: seconds = nil
        }
        return seconds.map { Date().addingTimeInterval($0) }
    }

    private static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }
}

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

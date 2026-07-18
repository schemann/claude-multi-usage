import Foundation

enum UsageResult {
    case ok(UsageResponse)
    case unauthorized
    case error(String)
}

enum UsageClient {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    static func fetch(token: String) async -> UsageResult {
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .error("Ungültige Antwort") }
            if http.statusCode == 401 { return .unauthorized }
            guard http.statusCode == 200 else { return .error("HTTP \(http.statusCode)") }
            return .ok(try JSONDecoder().decode(UsageResponse.self, from: data))
        } catch {
            return .error(error.localizedDescription)
        }
    }
}

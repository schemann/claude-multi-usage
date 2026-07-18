import Foundation

struct StoredCredentials: Codable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    var scopes: [String]

    var hasRefreshToken: Bool { !(refreshToken ?? "").isEmpty }

    func needsRefresh(at now: Date = Date(), leeway: TimeInterval = 300) -> Bool {
        guard hasRefreshToken, let expiresAt else { return false }
        return expiresAt <= now.addingTimeInterval(leeway)
    }

    func isExpired(at now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }
}

/// One independent Claude account tracked by this tool. Each carries its OWN
/// OAuth session (own refresh-token chain) - fully decoupled from Claude Code.
struct StoredAccount: Codable, Identifiable, Equatable {
    let id: String                // stable UUID string
    var displayName: String?      // user-set custom name; nil = fall back to email
    var email: String?            // canonical account email (from userinfo)
    var credentials: StoredCredentials

    /// What to show as the account's name.
    var title: String {
        if let displayName, !displayName.isEmpty { return displayName }
        if let email, !email.isEmpty { return email }
        return "Account"
    }

    init(id: String, displayName: String? = nil, email: String? = nil, credentials: StoredCredentials) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.credentials = credentials
    }

    enum CodingKeys: String, CodingKey {
        case id, displayName, email, credentials
        case label // legacy: old files stored the email under "label"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        credentials = try c.decode(StoredCredentials.self, forKey: .credentials)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        // Migrate legacy "label" into email only if it is a real email; the old
        // "Account N" placeholder is dropped so the email gets backfilled.
        if email == nil,
           let legacy = try c.decodeIfPresent(String.self, forKey: .label),
           legacy.contains("@") {
            email = legacy
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(displayName, forKey: .displayName)
        try c.encodeIfPresent(email, forKey: .email)
        try c.encode(credentials, forKey: .credentials)
    }
}

/// Persists accounts to ~/.config/claude-multi-usage/accounts.json (0600).
struct AccountStore {
    let directoryURL: URL
    let fileURL: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        directoryURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/claude-multi-usage", isDirectory: true)
        fileURL = directoryURL.appendingPathComponent("accounts.json")
    }

    func load() -> [StoredAccount] {
        guard let data = try? Data(contentsOf: fileURL),
              let accounts = try? Self.decoder.decode([StoredAccount].self, from: data) else {
            return []
        }
        return accounts
    }

    func save(_ accounts: [StoredAccount]) {
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
        guard let data = try? Self.encoder.encode(accounts) else { return }
        try? data.write(to: fileURL, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

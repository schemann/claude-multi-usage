import Foundation

/// Subset of the Anthropic OAuth usage response we care about.
///
/// The API moved model-scoped limits (Opus / Sonnet / Fable / ...) out of the
/// old flat `seven_day_opus` fields - those are `null` now - and into a generic
/// `limits[]` array where each scoped entry carries `scope.model.display_name`.
/// We keep the top-level 5h/7d buckets for the primary bars and read every
/// model-scoped weekly limit out of `limits[]` so new models show up on their own.
struct UsageResponse: Codable {
    let fiveHour: UsageBucket?
    let sevenDay: UsageBucket?
    let limits: [UsageLimit]?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case limits
    }

    /// Model-scoped weekly limits (e.g. Fable), in a stable display order.
    var modelLimits: [UsageLimit] {
        (limits ?? [])
            .filter { $0.modelName != nil }
            .sorted { ($0.modelName ?? "") < ($1.modelName ?? "") }
    }
}

struct UsageBucket: Codable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    /// Utilization clamped to 0...1 for the progress bar.
    var fraction: Double { max(0, min(1, (utilization ?? 0) / 100.0)) }

    var resetsAtDate: Date? { Self.parseDate(resetsAt) }

    static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: raw) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}

/// One entry of the `limits[]` array. We only surface the model-scoped weekly
/// ones; the session / weekly_all entries duplicate the 5h/7d buckets.
struct UsageLimit: Codable {
    let kind: String?
    let percent: Double?
    let resetsAt: String?
    let scope: Scope?

    enum CodingKeys: String, CodingKey {
        case kind
        case percent
        case resetsAt = "resets_at"
        case scope
    }

    struct Scope: Codable {
        let model: Model?
        struct Model: Codable {
            let id: String?
            let displayName: String?
            enum CodingKeys: String, CodingKey {
                case id
                case displayName = "display_name"
            }
        }
    }

    /// Display name of the scoped model, or nil for non-model limits.
    var modelName: String? {
        guard let name = scope?.model?.displayName, !name.isEmpty else { return nil }
        return name
    }

    var fraction: Double { max(0, min(1, (percent ?? 0) / 100.0)) }

    var resetsAtDate: Date? { UsageBucket.parseDate(resetsAt) }
}

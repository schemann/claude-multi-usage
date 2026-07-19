import Foundation

/// Optional in-app language override. When set, string lookups and relative
/// dates use the chosen language instead of the system one - handy for taking
/// screenshots in every localization without changing the macOS system language.
enum LocalizationOverride {
    /// nil = follow the system language.
    static var languageCode: String? {
        didSet { cachedBundle = nil }
    }

    private static var cachedBundle: Bundle?

    static func bundle() -> Bundle {
        if let cachedBundle { return cachedBundle }
        guard let code = languageCode,
              let path = Bundle.module.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .module
        }
        cachedBundle = bundle
        return bundle
    }

    /// Locale for date/number formatting under the current override.
    static var locale: Locale {
        languageCode.map { Locale(identifier: $0) } ?? .autoupdatingCurrent
    }
}

/// Localized string lookup routed through the override bundle (or `Bundle.module`
/// when following the system language). SwiftUI's `Text(LocalizedStringKey)`
/// resolves against `Bundle.main`, but in a SwiftPM target the `.strings` live in
/// the package resource bundle - so we look them up explicitly here and hand
/// SwiftUI a plain (already-localized) String.
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = LocalizationOverride.bundle().localizedString(forKey: key, value: key, table: nil)
    return args.isEmpty ? format : String(format: format, locale: LocalizationOverride.locale, arguments: args)
}

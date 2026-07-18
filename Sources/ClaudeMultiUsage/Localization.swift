import Foundation

/// Localized string lookup routed through `Bundle.module`. SwiftUI's
/// `Text(LocalizedStringKey)` resolves against `Bundle.main`, but in a SwiftPM
/// target the `.strings` live in the package resource bundle - so we look them
/// up explicitly here and hand SwiftUI a plain (already-localized) String.
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = Bundle.module.localizedString(forKey: key, value: key, table: nil)
    return args.isEmpty ? format : String(format: format, locale: .current, arguments: args)
}

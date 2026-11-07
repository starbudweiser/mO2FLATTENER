// Réglages : clé « language » (« auto » ou fr/en/es/it). La version Python (QSettings « SkyrimTools/MO2Flattener », fichier
// ~/Library/Preferences/com.SkyrimTools.MO2Flattener.plist) n'enregistrait que cette clé : elle est reprise au premier lancement.

import Foundation

public enum LangChoice {
    public static let auto = "auto"
    /// Entrées du menu Langue, dans leur propre langue.
    public static let menuLangs: [(code: String, label: String)] = [("fr", "Français"), ("en", "English"), ("es", "Español"), ("it", "Italiano")]

    public static func normalize(_ choice: String?) -> String {
        let c = (choice ?? "").trimmingCharacters(in: .whitespaces)
        return I18n.langs[c] != nil ? c : auto
    }

    /// Langue à afficher pour un choix mémorisé.
    public static func resolve(_ choice: String?, preferred: [String] = Locale.preferredLanguages) -> String {
        let c = normalize(choice)
        return c == auto ? I18n.systemLang(preferred) : c
    }
}

public final class AppSettings: @unchecked Sendable {
    public static let keys = ["language"]
    /// Domaine de préférences de l'ancienne version (QSettings de Qt : organisation « SkyrimTools », appli « MO2Flattener »).
    public static let qtDomains = ["com.SkyrimTools.MO2Flattener", "com.skyrimtools.MO2Flattener", "SkyrimTools.MO2Flattener"]
    private let defaults: UserDefaults

    /// `suite` : domaine de préférences d'essai (jamais celui de l'utilisateur) ; nil = préférences de l'appli.
    public init(suite: String? = nil) {
        defaults = suite.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        if defaults.object(forKey: "qt_imported") == nil {
            if suite == nil { importQt() }
            defaults.set("1", forKey: "qt_imported")
        }
    }

    /// Reprise des valeurs de l'ancienne version (lecture seule du plist de Qt).
    private func importQt() {
        for name in AppSettings.qtDomains {
            guard let dom = UserDefaults.standard.persistentDomain(forName: name) else { continue }
            for k in AppSettings.keys where defaults.object(forKey: k) == nil {
                if let v = dom[k] { defaults.set("\(v)", forKey: k) }
            }
        }
    }

    public func string(_ key: String, _ def: String = "") -> String { defaults.string(forKey: key) ?? def }
    public func set(_ key: String, _ value: String) { defaults.set(value, forKey: key) }
}

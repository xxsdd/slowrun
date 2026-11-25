import Foundation

public enum RunLanguage {
    public static let key = "workoutLanguage"
    public static var isEnglish: Bool { UserDefaults.standard.string(forKey: key) == "en" }

    private static let englishBundle = Bundle.module.url(forResource: "en", withExtension: "lproj").flatMap(Bundle.init(url:))

    public static func english(_ key: String) -> String {
        englishBundle?.localizedString(forKey: key, value: key, table: nil) ?? key
    }

    public static func text(_ chinese: String, _ arguments: String...) -> String {
        let format = isEnglish ? english(chinese) : chinese
        return arguments.isEmpty ? format : String(format: format, arguments: arguments)
    }
}

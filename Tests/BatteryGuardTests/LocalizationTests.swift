import Foundation
import Testing

struct LocalizationTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static func entries(_ language: String) throws -> [String: String] {
        let url = root.appendingPathComponent("Resources/\(language).lproj/Localizable.strings")
        let text = try String(contentsOf: url, encoding: .utf8)
        var result: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let parts = line.split(separator: "\"", omittingEmptySubsequences: false)
            guard parts.count >= 5, parts[0].isEmpty, parts[2].hasPrefix(" = ") else { continue }
            let key = String(parts[1])
            let value = String(parts[3])
            result[key] = value
        }
        return result
    }

    private static func placeholders(_ text: String) -> [String] {
        let pattern = #"%(?:lld|ld|d|@|\.\d+f|\.\d+lf|%|s)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range)
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
            .sorted()
    }

    @Test func englishAndRussianCoverTheSameKeys() throws {
        let english = try Self.entries("en")
        let russian = try Self.entries("ru")
        #expect(english.count > 700)
        #expect(Set(english.keys) == Set(russian.keys))
    }

    @Test func translationsAreNotEmptyAndKeepPlaceholders() throws {
        for language in ["en", "ru"] {
            let entries = try Self.entries(language)
            for (key, value) in entries {
                #expect(!value.trimmingCharacters(in: .whitespaces).isEmpty, "empty translation: \(key)")
                #expect(Self.placeholders(key) == Self.placeholders(value), "placeholder mismatch: \(key)")
            }
        }
    }

    @Test func appBundleDeclaresAllSupportedLanguages() throws {
        let script = try String(
            contentsOf: Self.root.appendingPathComponent("scripts/build-app.sh"),
            encoding: .utf8
        )
        for language in ["de", "en", "ru"] {
            #expect(script.contains("<string>\(language)</string>"))
        }
    }
}

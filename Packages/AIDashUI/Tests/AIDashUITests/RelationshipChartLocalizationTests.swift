import Testing
import Foundation
@testable import AIDashUI

/// Tests for MY-1401: every user-visible string the relationship chart family
/// resolves through `String(localized:)` must have a matching entry in the
/// AIDashUI String Catalog (constitution Cross-Cutting Quality Bar §F.1).
///
/// Asserted against the catalog SOURCE rather than `Bundle.module`: `.xcstrings`
/// is compiled to `.strings` by Xcode's asset pipeline, which `swift test` does
/// not run, so a runtime lookup returns the key itself for EVERY key here and
/// would prove nothing. This is the same technique `BriefingViewTests` uses for
/// `briefing.navigation.title`.
///
/// A missing entry has no build error and no runtime crash — SwiftUI silently
/// renders the raw key ("relationship.scatter.category") as the legend title,
/// and the string is invisible to translators. That is exactly how the scatter
/// legend title shipped uncatalogued in PR #171.
@Suite("RelationshipChart Localization Tests")
struct RelationshipChartLocalizationTests {

    // MARK: - The MY-1401 key

    @Test("scatter legend-title key is present in the xcstrings catalog")
    func scatterCategoryKeyIsInCatalog() throws {
        let entry = try Self.catalogEntry(for: "relationship.scatter.category")

        #expect(Self.englishValue(of: entry) == "Category",
                "the en localization must carry the default value the renderer declares")
        #expect(!(entry["comment"] as? String ?? "").isEmpty,
                "translators need a comment explaining what the legend title labels")
    }

    // MARK: - Family guard

    @Test("every relationship.* key the sources localize exists in the catalog")
    func everyRelationshipSourceKeyIsCatalogued() throws {
        let catalogued = try Self.catalogKeys()
        let declared = try Self.localizedKeysInSources(matching: "relationship.")

        #expect(!declared.isEmpty,
                "the scan found no relationship keys at all — the source scan itself is broken")

        let missing = declared.subtracting(catalogued).sorted()
        #expect(missing.isEmpty,
                "relationship keys missing from Localizable.xcstrings: \(missing)")
    }

    @Test("catalogued relationship keys all carry a translated en value")
    func catalogueRelationshipKeysAreTranslated() throws {
        let strings = try Self.catalogStrings()
        let relationshipKeys = strings.keys.filter { $0.hasPrefix("relationship.") }

        #expect(!relationshipKeys.isEmpty, "the catalog carries no relationship keys")

        for key in relationshipKeys.sorted() {
            let entry = try #require(strings[key] as? [String: Any])
            let value = Self.englishValue(of: entry)
            #expect(!(value ?? "").isEmpty,
                    "\(key) has no non-empty en value — it would render as the raw key")
        }
    }

    // MARK: - Catalog access

    private static func catalogStrings() throws -> [String: Any] {
        let url = try sourceFile(named: "Localizable.xcstrings",
                                 under: ["Sources", "AIDashUI", "Resources"])
        let data = try Data(contentsOf: url)
        let root = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
            "Localizable.xcstrings is not a JSON object"
        )
        return try #require(root["strings"] as? [String: Any],
                            "Localizable.xcstrings has no `strings` map")
    }

    private static func catalogKeys() throws -> Set<String> {
        Set(try catalogStrings().keys)
    }

    private static func catalogEntry(for key: String) throws -> [String: Any] {
        let strings = try catalogStrings()
        return try #require(strings[key] as? [String: Any],
                            "xcstrings key \(key) is missing from the catalog")
    }

    /// The `en` `stringUnit` value of one catalog entry, or nil when the entry
    /// carries no English localization at all.
    private static func englishValue(of entry: [String: Any]) -> String? {
        guard
            let localizations = entry["localizations"] as? [String: Any],
            let english = localizations["en"] as? [String: Any],
            let unit = english["stringUnit"] as? [String: Any]
        else { return nil }
        return unit["value"] as? String
    }

    // MARK: - Source scan

    /// Every `String(localized: "<prefix>…")` key literal declared anywhere in
    /// the AIDashUI sources.
    ///
    /// Only STATIC literals are collected. A key built with interpolation
    /// (`"trending.more_items \(overflow)"`) is rewritten by the compiler's
    /// extractor into a format-specifier key (`trending.more_items %lld`), so
    /// the literal in source never matches the catalogued key and comparing
    /// them would report false misses. The relationship family is entirely
    /// static, which is what makes this guard meaningful for it.
    private static func localizedKeysInSources(matching prefix: String) throws -> Set<String> {
        let root = try sourcesRoot()
        var keys: Set<String> = []

        for url in try swiftFiles(under: root) {
            let source = try String(contentsOf: url, encoding: .utf8)
            for key in localizedKeyLiterals(in: source) where key.hasPrefix(prefix) {
                keys.insert(key)
            }
        }
        return keys
    }

    /// Pulls the key literal out of each `String(localized: "…"` occurrence.
    /// Interpolated literals contain a backslash and are skipped — see the
    /// note on `localizedKeysInSources(matching:)`.
    private static func localizedKeyLiterals(in source: String) -> [String] {
        let marker = "localized: \""
        var keys: [String] = []
        var cursor = source.startIndex

        while let start = source.range(of: marker, range: cursor..<source.endIndex) {
            guard let end = source.range(of: "\"", range: start.upperBound..<source.endIndex) else {
                break
            }
            let literal = String(source[start.upperBound..<end.lowerBound])
            if !literal.contains("\\") {
                keys.append(literal)
            }
            cursor = end.upperBound
        }
        return keys
    }

    private static func swiftFiles(under root: URL) throws -> [URL] {
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil
        ) else {
            throw SourceLookupError.testsRootNotFound
        }
        return walker
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
    }

    private static func sourcesRoot() throws -> URL {
        try packageRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("AIDashUI")
    }

    private static func sourceFile(named filename: String,
                                   under components: [String]) throws -> URL {
        var url = try packageRoot()
        for component in components {
            url = url.appendingPathComponent(component)
        }
        url = url.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SourceLookupError.testsRootNotFound
        }
        return url
    }

    private static func packageRoot(file: StaticString = #filePath) throws -> URL {
        var dir = URL(fileURLWithPath: String(describing: file)).deletingLastPathComponent()
        while dir.lastPathComponent != "Tests" && dir.path != "/" {
            dir = dir.deletingLastPathComponent()
        }
        guard dir.lastPathComponent == "Tests" else {
            throw SourceLookupError.testsRootNotFound
        }
        return dir.deletingLastPathComponent()
    }
}

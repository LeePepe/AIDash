import Foundation

/// Test helper that locates a Swift source file inside the AIDashUI
/// package by walking up from this helper's own file path. Used by
/// layout / container tests to assert source-level invariants
/// (delegation to TokenGrid, no CardType branching, no panel chrome)
/// that SwiftUI's view graph does not expose at runtime.
enum LayoutSourceLoader {

    static func read(_ filename: String,
                     under relativePath: String = "Sources/AIDashUI/Layout") throws -> String {
        let url = try locate(filename, under: relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func locate(_ filename: String,
                       under relativePath: String) throws -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = dir
                .appendingPathComponent(relativePath)
                .appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }
        throw Error.notFound(filename, relativePath)
    }

    enum Error: Swift.Error {
        case notFound(String, String)
    }
}

import Foundation

/// Resolves CLI date sugar (`today`, `yesterday`) to YYYY-MM-DD format
/// using the user's local timezone (per cli-surface.md contract).
enum DateResolver {
    static func resolve(_ input: String) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        switch input.lowercased() {
        case "today":
            return formatter.string(from: Date())
        case "yesterday":
            let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
            return formatter.string(from: yesterday)
        default:
            return input
        }
    }
}

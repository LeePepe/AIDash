import Foundation

extension JSONDecoder {
    /// A decoder configured with ISO 8601 date strategy.
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

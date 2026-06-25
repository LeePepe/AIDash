import Foundation
import AIDashCore

/// Human-readable output: pretty-printed JSON to stdout for success,
/// JSON error to stderr (per cli-surface contract: errors are always JSON).
public struct HumanOutput: OutputFormatter {
    public init() {}

    public func emit(success: any Encodable) throws {
        let json = try JSONEncoder().encode(AnyEncodable(success))
        if let obj = try? JSONSerialization.jsonObject(with: json),
           let pretty = try? JSONSerialization.data(
               withJSONObject: obj,
               options: [.prettyPrinted, .sortedKeys]
           ) {
            FileHandle.standardOutput.write(pretty)
            FileHandle.standardOutput.write(Data("\n".utf8))
        } else {
            FileHandle.standardOutput.write(json)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }

    public func emit(error: XPCError) throws {
        try JSONOutput().emit(error: error)
    }
}

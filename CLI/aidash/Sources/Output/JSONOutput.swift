import Foundation
import AIDashCore

/// Machine-readable JSON output: success to stdout, errors to stderr.
public struct JSONOutput: OutputFormatter {
    public init() {}

    public func emit(success: any Encodable) throws {
        let data = try Self.encoder.encode(AnyEncodable(success))
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    public func emit(error: XPCError) throws {
        let data = try Self.encoder.encode(error)
        FileHandle.standardError.write(data)
        FileHandle.standardError.write(Data("\n".utf8))
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

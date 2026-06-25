import Foundation
import AIDashCore

public protocol OutputFormatter: Sendable {
    func emit(success: any Encodable) throws
    func emit(error: XPCError) throws
}

public enum OutputMode: Sendable {
    case human
    case json

    public func formatter() -> any OutputFormatter {
        switch self {
        case .human: return HumanOutput()
        case .json:  return JSONOutput()
        }
    }
}

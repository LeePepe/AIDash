import Foundation
import AIDashCore

public protocol OutputFormatter: Sendable {
    func emit(success: any Encodable) throws
    func emit(error: XPCError) throws
}

public enum OutputMode: Sendable {
    case human
    case json

    public func formatter(requestId: String? = nil) -> any OutputFormatter {
        switch self {
        case .human: return HumanOutput(requestId: requestId)
        case .json:  return JSONOutput(requestId: requestId)
        }
    }
}

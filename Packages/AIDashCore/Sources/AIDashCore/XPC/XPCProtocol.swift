import Foundation

@objc public protocol AIDashXPCServiceProtocol {
    func execute(requestData: Data, reply: @escaping (Data) -> Void)
}

public enum XPCServiceConfiguration {
    public static let machServiceName = "com.tianpli.aidash.xpc.v1"
}

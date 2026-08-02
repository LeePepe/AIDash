import Foundation

@objc public protocol AIDashXPCServiceProtocol {
    func execute(requestData: Data, reply: @escaping (Data) -> Void)
}

public enum XPCServiceConfiguration {
    /// The mach service the App vends and the CLI connects to.
    ///
    /// **Fork 本项目时需要改这里。** 这是 App ↔ CLI 通信的唯一锚点,两端必须
    /// **字面一致**,否则 CLI 连不上 App。
    ///
    /// 它没有走 `Configs/Identity.xcconfig`,因为本文件属于 SPM 包
    /// (AIDashCore),而 SPM 编译不消费 Xcode 的 xcconfig 变量;CLI 又是
    /// command-line tool,`Bundle.main.bundleIdentifier` 在其中为 nil,所以也
    /// 无法在运行时从 bundle 推导。因此这里是一个**手工保持同步**的常量:
    /// 改了 xcconfig 里的 `AIDASH_BUNDLE_ID`,就要把这里一并改成
    /// `<你的 bundle id>.xpc.v1`。
    ///
    /// 约定:`<AIDASH_BUNDLE_ID>.xpc.v1`。
    public static let machServiceName = "com.tianpli.aidash.xpc.v1"
}

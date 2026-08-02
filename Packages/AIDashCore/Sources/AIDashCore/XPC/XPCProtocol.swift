import Foundation

@objc public protocol AIDashXPCServiceProtocol {
    func execute(requestData: Data, reply: @escaping (Data) -> Void)
}

public enum XPCServiceConfiguration {
    /// The mach service the App vends and the CLI connects to.
    ///
    /// **App 与 CLI 两端必须字面一致**,否则 CLI 连不上 App。
    /// 约定:`<AIDASH_BUNDLE_ID>.xpc.v1`。
    ///
    /// 为什么不是 xcconfig 变量:本文件属于 SPM 包(AIDashCore),SPM 编译不消费
    /// Xcode 的 xcconfig;CLI 又是 command-line tool,`Bundle.main.bundleIdentifier`
    /// 在其中为 nil,所以两条自动路径都走不通。因此这是一个**手工保持同步**的
    /// 常量:fork 本项目改了 `Configs/Identity.xcconfig` 的 bundle id 后,要把这里
    /// 一并改成 `<你的 bundle id>.xpc.v1`。见 README「Fork 本项目」。
    public static let machServiceName = "com.tianpli.aidash.xpc.v1"
}

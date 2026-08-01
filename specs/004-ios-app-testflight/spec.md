# Spec 004 — iOS App:手机查看 + 事件回传 + TestFlight 分发

## 1. 意图（Why）

AIDash 目前实际以 macOS 菜单栏 app 运行,但 `AIDashApp` target 早已声明
`supportedDestinations: [macOS, iOS]`、部署目标 iOS 26.0,宪法 §II 也明确 App 覆盖
**macOS / iPadOS / iPhone** 三端、均经 CloudKit 读 briefing + 写用户事件。

现状缺口:
- **iOS 构建是坏的**——违反宪法 §Testing gate 1(「workspace builds for macOS +
  iPadOS + iPhone + CLI on every PR, no exceptions」)。唯一编译阻塞是
  `CloudKitContainer.hasCloudKitEntitlement()` 用了 macOS 专属的 `SecCode` 代码签名 API。
- **无 iOS 分发渠道**——用户要在手机上查看每日 briefing,需要 TestFlight。

目标:让 iPhone 能装、能看 briefing、功能一致(star + TODO 完成态回传),经 **iCloud** 跨设备
同步,并建立 **TestFlight 自动分发**。

## 2. 同步拓扑(关键约束)

```
aidata ──(现有管道)──> aidash CLI ──XPC──> Mac App(GUI)──> CloudKit 私有库
                                                              │  iCloud
                                                              ▼
                                              iPhone App ──读 briefing / 写 star+done 事件
```

- **iPhone ↔ Mac 走 iCloud**;**Mac ↔ aidata 走现有 XPC 管道**。
- **iOS 端永不直连 aidata / 无 CLI / 无 XPC / 无 launchd**——只做 CloudKit 读 + 写事件。
  与现有代码天然一致(macOS-only 文件已包 `#if os(macOS)`,iOS 编空)。

**已知运维 caveat(by design,不改)**:headless launchd agent 用 local-only store 写
briefing(attach CloudKit mirror 会 SIGTRAP),briefing 只在 **Mac GUI app 打开时**才被推上
iCloud。因此新生成的 briefing 要等 Mac GUI 开过一次后,iPhone 才拉得到。这是
`CloudKitContainer.localOnly()` + `AIDashApp.swift` init 的既定设计。**本 spec 不改 agent。**

## 3. 行为契约(What)

### A. iOS 构建解锁
- `hasCloudKitEntitlement()` 的 SecCode 逻辑包进 `#if os(macOS)`,iOS 分支 `return true`
  (iOS 无 headless agent;entitlement 由 provisioning 保证;账号存在性仍由
  `isCloudKitAvailable()` 的 `ubiquityIdentityToken != nil` 把关,未登录 iCloud 干净回退
  local-only)。`import Security` 改条件编译。
- entitlements 按平台拆分:macOS 版保留 app-sandbox/network + iCloud 键;iOS 版仅 4 个
  iCloud 键(不含 sandbox/network,iOS 隐式沙盒)。`project.yml` 用 SDK-scoped
  `CODE_SIGN_ENTITLEMENTS[sdk=macosx*]` / `[sdk=iphoneos*]` / `[sdk=iphonesimulator*]`。
- iOS 上 `BriefingView` 用 `NavigationStack` + 导航标题包裹(纯附加,不动
  `DesignTokensChromeHierarchyTests` 断言的 token 行)。

### B. 功能一致(事件回传)
- **star**:已跨平台(走 CloudKit-mirrored SwiftData),iOS 直接复用,无需改动。
- **TODO 完成态**:见 spec 003 §8(latest-wins 迁移 + UI)。iOS 与 macOS 共用同一 UI 层,
  勾选交互天然两端可用。

### C. TestFlight 分发
- 参照 VitalStride(同付费 team `4Z8GG667QD`、同 GitHub owner、同架构)的
  fastlane + self-hosted runner + ASC API Key 方案:
  - `fastlane/Appfile` + `fastlane/Fastfile`(`ios beta` lane):ASC API Key(.p8 base64)auth、
    `xcodegen generate`、`latest_testflight_build_number`(全局单调递增)、manual 签名 +
    `get_provisioning_profile(force:true)`、`build_app(export_method:"app-store")`、
    `upload_to_testflight(distribute_external:false)` + spaceship 显式加 Internal 群组。
    **单 app bundleID,无 widget、无 HealthKit、无 GlitchTip/Aptabase**(比 VitalStride 简单)。
  - `.github/workflows/testflight.yml`:定时自动(每天凌晨 off-peak 分钟)+ `workflow_dispatch(force)`;
    gate 用 `testflight/last-released` moving tag;`runs-on: [self-hosted, aidash-mac]`;
    解锁 login keychain;`fastlane ios beta`;move tag。

### D. CI 加 iOS 构建门(防回归)
- `.github/workflows/build.yml` 的 `build` job 加一步 iOS 编译门
  (`xcodebuild -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`),
  确保 iOS 构建不再被后续改动悄悄弄坏。

## 4. Acceptance criteria
- [ ] `xcodebuild -scheme AIDashApp -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` 干净通过。
- [ ] entitlements 按 SDK 拆分;macOS/iOS 各自带正确 iCloud 键;`xcodegen generate` 后无警告。
- [ ] iOS 上 BriefingView 有导航标题;macOS 渲染不变;`DesignTokensChromeHierarchyTests` 全绿。
- [ ] TestFlight workflow 能手动 `workflow_dispatch force=true` 跑通:build 上传 + 分发到 Internal 群组。
- [ ] CI build job 含 iOS 构建 step 并通过。
- [ ] 三端构建门(macOS + iPadOS + iPhone + CLI)全绿(宪法 §Testing gate 1)。

## 5. Out of scope
- 改 headless agent 的 CloudKit 推送策略(SIGTRAP 原因,by design)。
- iOS 专属 UI 重设计(NavigationStack + 标题即可,深度手机化交互后续独立 feature)。
- App Store 正式上架(仅 TestFlight 内测)。
- 真机/iCloud 手动 smoke test 作为阻塞 issue(宪法 §User Feedback:禁止;作为用户操作)。

## 6. 按 layer 的 task 拆分(见 tasks.md)
- **A1(App)**:CloudKitContainer iOS 构建修复。
- **A2(config)**:entitlements 拆分 + project.yml SDK-scoped。
- **A3(AIDashUI)**:BriefingView NavigationStack。
- **C(config/CI)**:fastlane + testflight.yml。
- **D(config/CI)**:build.yml 加 iOS 门。
- spec 003 的 latest-wins 迁移 + UI 在 spec 003 tasks.md,与本 spec 并行。

## 7. Constitution refs
- §II:App 覆盖 macOS/iPadOS/iPhone,均经 CloudKit;iOS 端无 CLI/XPC。
- §Testing gate 1:四端构建门,no exceptions。
- §Dependencies:fastlane 是 CI 工具链(非 app 运行时依赖),不入 app 二进制,不需 app 层 ADR;
  但若评审认为需记录,补一条 CI-tooling 说明。
- §User Feedback:不建手动 smoke-test 阻塞 issue。

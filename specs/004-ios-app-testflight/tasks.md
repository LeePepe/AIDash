# Tasks — Feature 004 iOS App:手机查看 + 事件回传 + TestFlight

按 **layer 收窄**（AGENTS.md 硬规则）拆分。每个 task = 一层/一个关注点 = 一个独立可
build/test 的 commit。依赖用 `--stage` 表达。

参照：`spec.md`（本目录）、`.specify/memory/constitution.md`（§II 三端、§Testing gate 1
四端构建门）、VitalStride 的 `fastlane/` + `.github/workflows/testflight.yml`（分发模板）。

---

## Stage 1 — iOS 构建解锁（blocker，其余分发/CI 依赖它）

### T201 · [App] CloudKitContainer iOS 构建修复

**layer**: AIDashApp（依赖 AIDashCore）
**depends_on**: []
**test**: `xcodebuild -scheme AIDashApp -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`（必须干净通过）+ macOS 构建不回归

`Apps/AIDashApp/Sources/Sync/CloudKitContainer.swift` 的 `hasCloudKitEntitlement()` 用了
macOS 专属 Security API（`SecCode`/`SecCodeCopySelf`/`SecCodeCopyStaticCode`/
`SecCodeCopySigningInformation`/`SecCSFlags`/`kSecCSRequirementInformation`），iOS 上不存在
→ 唯一 iOS 编译阻塞。

- 把 `hasCloudKitEntitlement()` 的 SecCode 逻辑体包进 `#if os(macOS) ... #else return true #endif`。
  依据（见该文件行 100-116 自带注释）：gate 只为防 headless launchd agent 在无签名/无窗口
  上下文 SIGTRAP；iOS 无 headless agent、永远是 provision 过的 GUI、entitlement 由 profile
  保证 → iOS 正确行为是 return true。
- `import Security` 改条件编译（`#if os(macOS)`，文件内仅此处用）。
- 不动 `isCloudKitAvailable()`（`ubiquityIdentityToken != nil` 账号存在性检查两端都跑，
  iOS 未登录 iCloud 仍干净回退 local-only）、`makeConfiguration`、`storageMode`（均平台无关）。

**Acceptance**
- [ ] iOS 构建门命令干净通过。
- [ ] macOS 构建 + AIDashCore 测试不回归。
- [ ] iOS 分支不引入 fatalError/try!/as!；`isCloudKitAvailable()` 的账号回退在 iOS 仍生效。

---

## Stage 2 — 配置/UI（依赖构建可过）

### T202 · [config] entitlements 按 SDK 拆分 + project.yml

**layer**: 顶层配置（project.yml + Apps/AIDashApp entitlements）
**depends_on**: [T201]
**test**: `xcodegen generate` 后 `xcodebuild -scheme AIDashApp -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` + macOS 构建均过

- 现单一 `Apps/AIDashApp/AIDashApp.entitlements` 含 macOS App Sandbox 键
  （`app-sandbox`/`network.client`），iOS 不属于其 entitlement 集。拆成两份：
  - `AIDashApp.macOS.entitlements` = 现文件逐字（保留 sandbox/network + 全部 iCloud 键）。
  - `AIDashApp.iOS.entitlements` = **仅** 4 个 iCloud 键（`icloud-services:[CloudKit]`、
    `icloud-container-identifiers`、`ubiquity-container-identifiers`、
    `icloud-container-environment:Development`），去掉 sandbox/network。
- `project.yml` 的 `AIDashApp.settings.base` 把单行 `CODE_SIGN_ENTITLEMENTS` 换成 SDK-scoped
  （同现有 `INFOPLIST_KEY_LSUIElement[sdk=macosx*]` 机制）：
  ```
  CODE_SIGN_ENTITLEMENTS[sdk=macosx*]: Apps/AIDashApp/AIDashApp.macOS.entitlements
  CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]: Apps/AIDashApp/AIDashApp.iOS.entitlements
  CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]: Apps/AIDashApp/AIDashApp.iOS.entitlements
  ```
- `ENABLE_HARDENED_RUNTIME`（macOS 概念）可 scope 到 macosx* 保持整洁（可选）。

**Acceptance**
- [ ] 两个 entitlements 文件存在，键集正确（iOS 无 sandbox/network）。
- [ ] project.yml SDK-scoped；`xcodegen generate` 无警告。
- [ ] iOS + macOS 构建门均过。

### T203 · [UI] BriefingView iOS NavigationStack + 标题

**layer**: AIDashUI
**depends_on**: [T201]
**test**: `swift test --package-path Packages/AIDashUI`（含 `DesignTokensChromeHierarchyTests`）

- `Packages/AIDashUI/Sources/AIDashUI/BriefingView.swift` iOS 上是裸 `ScrollView`（无标题、
  内容钻状态栏）。**纯附加**在 iOS 分支包 `NavigationStack` + `.navigationTitle`（inline），
  macOS 完全不动。
- ⚠️ `DesignTokensChromeHierarchyTests` 对 BriefingView 源码做字符串断言（grep
  `pageHorizontalMac`/`pageHorizontalCompact`/`theme.neutrals.bg`）——改动必须纯附加，
  不删不改这些行。
- 导航标题文案走 xcstrings（§F i18n）。

**Acceptance**
- [ ] iOS 上 BriefingView 有导航标题；macOS 渲染路径不变。
- [ ] `DesignTokensChromeHierarchyTests` + AIDashUI 测试全绿。
- [ ] 标题文案本地化（无硬编码字面量）。

---

## Stage 3 — 分发 + CI（依赖 iOS 能构建）

### T204 · [CI] build.yml 加 iOS 构建门

**layer**: 顶层 CI（.github/workflows）
**depends_on**: [T201, T202]
**test**: workflow YAML 合法；本地 `xcodebuild -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` 通过

- `.github/workflows/build.yml` 的 `build` job（macos-26）在现有 macOS build step 后加：
  ```yaml
  - name: Build AIDashApp (iOS)
    run: xcodebuild -scheme AIDashApp -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
  ```
- 对齐宪法 §Testing gate 1（四端构建门）。可选：iPad destination 亦可加，但 generic/iOS
  已覆盖 iPhone/iPad 同一 target 的编译。

**Acceptance**
- [ ] build.yml 含 iOS 构建 step；YAML 合法；不破坏现有 macOS/CLI step。

### T205 · [CI] fastlane + testflight.yml（定时自动分发）

**layer**: 顶层 CI/分发（fastlane/ + .github/workflows）
**depends_on**: [T201, T202]
**test**: `fastlane` 语法（`ruby -c` / `fastlane lint` 视可用性）；workflow YAML 合法。真实上传由用户手动 `workflow_dispatch force=true` 验证（非 CI 阻塞）。

参照 VitalStride（同 team `<DEVELOPMENT_TEAM>`(见 Configs/Identity.xcconfig)、同 GitHub owner、AIDash 已有 `[self-hosted, aidash-mac]`
runner），替换 bundleID/scheme、**去掉 widget/HealthKit/GlitchTip/Aptabase**：

- `fastlane/Appfile`：`app_identifier("<AIDASH_BUNDLE_ID>")` + `team_id("<DEVELOPMENT_TEAM>")`。
  > 这两个值的**单源**是 `Configs/Identity.xcconfig`（真实 Team ID 在 git-ignored 的
  > `Configs/Identity.local.xcconfig`，见宪法 §No Identity in Version Control）。
  > `Appfile` 本身进版本库，所以**不要把真实 Team ID 写死进去** —— 从环境变量读
  > （CI 用 secret，本地从 xcconfig 解析），否则会把身份标识带回公开仓库。
- `fastlane/Fastfile`：`ios beta` lane：ASC API Key（.p8 base64，`is_key_content_base64:true`）；
  `sh("cd .. && xcodegen generate")`；`latest_testflight_build_number`（**不传 version**，全局
  单调递增，next=latest+1）；`get_provisioning_profile(force:true)` 拉单个 app bundleID 的
  App Store profile；`build_app(export_method:"app-store", export_team_id, signingStyle:"manual",
  xcargs: "CURRENT_PROJECT_VERSION=#{next_build} DEVELOPMENT_TEAM=…")`；
  `upload_to_testflight(distribute_external:false, skip_submission:true)` + spaceship 显式把
  build 加到 Internal 群组（VitalStride 注释已记录 `groups:` 对 internal 无效的坑）。
- `.github/workflows/testflight.yml`：`schedule`（每天凌晨 off-peak 分钟，如 `7 19 * * *`
  = CST 03:07）+ `workflow_dispatch(force)`；gate 用 `testflight/last-released` moving tag
  （有新 commit 才 build）；`runs-on: [self-hosted, aidash-mac]`；`permissions: contents:write`；
  step：checkout（fetch-tags）→ decide-release gate → verify Xcode → ensure fastlane →
  write/verify API key secret → unlock login keychain（`security unlock-keychain` +
  `set-keychain-settings` + `list-keychains` 合并 + `set-key-partition-list`）→ `fastlane ios beta`
  → move `testflight/last-released` tag。
- Secrets（用户在 AIDash repo 配）：`ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_P8_BASE64` /
  `KEYCHAIN_PASSWORD`。**Developer Portal / ASC 前置**（App ID + iCloud capability + container、
  ASC app 记录 + Internal 群组）是用户一次性人工操作，不在本 task 代码范围——在 handoff 注明。

**Acceptance**
- [ ] `fastlane/Appfile` + `fastlane/Fastfile`（ios beta lane）+ `.github/workflows/testflight.yml` 存在且语法/YAML 合法。
- [ ] Fastfile 用 ASC API Key + manual 签名 + 全局单调 build number + Internal 群组显式分发；无 widget/HealthKit/GlitchTip 残留。
- [ ] workflow 定时 + 手动触发；self-hosted aidash-mac；last-released tag gate。
- [ ] handoff 注明用户需配的 4 个 Secret + Developer Portal/ASC 前置。

---

## 依赖顺序
Stage 1（T201）→ Stage 2（T202, T203 并行）→ Stage 3（T204, T205 并行），用 `--stage` barrier。
spec 003 的 latest-wins（T101→T102→T103）与本 spec 并行，无交叉文件依赖。

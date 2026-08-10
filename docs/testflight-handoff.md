# TestFlight 自动分发 — 交接与前置条件(spec 004 / T205)

`.github/workflows/testflight.yml` + `fastlane/` 已经落地,但**首次真实上传前需要
用户做一次性人工配置**:5 个 GitHub Secret + Developer Portal / App Store Connect
的账号侧前置。这些都不是代码能代劳的(需要 Apple 账号交互),所以单列在这里。

配置完之前,workflow 会在「Verify API key secret」步骤**提前失败并指名缺哪个**
—— 不会跑到 archive 之后才报一个含糊的认证错误。

---

## 一、GitHub Secrets(5 个)

在 repo 里配(`gh secret set <NAME>`,或 Settings → Secrets and variables → Actions):

| Secret | 值 | 从哪来 |
|---|---|---|
| `ASC_KEY_ID` | App Store Connect API Key 的 Key ID(10 位) | ASC → Users and Access → Integrations → App Store Connect API |
| `ASC_ISSUER_ID` | 同页顶部的 Issuer ID(UUID) | 同上 |
| `ASC_KEY_P8_BASE64` | `.p8` 私钥文件的 **base64** | 见下方命令 |
| `ASC_TEAM_ID` | Apple Developer Team ID(10 位) | developer.apple.com → Membership |
| `KEYCHAIN_PASSWORD` | runner 那台 Mac 的**登录密码** | 你自己的 macOS 账户密码 |

生成 API Key:ASC → Users and Access → Integrations → App Store Connect API →
「+」新建,角色选 **App Manager**(要能上传 build + 改 TestFlight 群组)。
`.p8` **只能下载一次**,存好。然后:

```bash
# .p8 转 base64(fastlane 直接吃 base64,workflow 不会把明文密钥落到磁盘)
base64 -i AuthKey_XXXXXXXXXX.p8 | tr -d '\n' | gh secret set ASC_KEY_P8_BASE64

gh secret set ASC_KEY_ID       # 粘 Key ID
gh secret set ASC_ISSUER_ID    # 粘 Issuer ID
gh secret set ASC_TEAM_ID      # 粘 Team ID
gh secret set KEYCHAIN_PASSWORD  # runner 那台 Mac 的登录密码
```

### 为什么 Team ID 走 Secret 而不是写进 Appfile

本仓库是 **public**,宪法 §No Identity in Version Control 把 Apple Developer
Team ID 明确列为禁止进版本库的标识符。所以 `fastlane/identity.rb` 按
`ENV["AIDASH_DEVELOPMENT_TEAM"]`(CI 由 `ASC_TEAM_ID` 注入)→
`Configs/Identity.local.xcconfig`(本机 git-ignored)的顺序解析,两处都没有就**抛错**,
绝不拿占位符 `REPLACE_ME` 去签名。Bundle ID 是宪法豁免项(公开无害),所以可以
兜底到受版本控制的默认值。

### 为什么需要 KEYCHAIN_PASSWORD

self-hosted runner 跑在独立 launchd 会话(PPID=1),登录钥匙串在该会话里默认是
**锁定**的 → `codesign` 拿不到 Apple Distribution 私钥 → `errSecInternalComponent`。
这个报错完全不提「钥匙串锁着」,极难排查。workflow 在 build 前显式
`security unlock-keychain` + `set-key-partition-list` 放行。

---

## 二、Developer Portal / App Store Connect 前置

这些是**账号侧**一次性操作,代码里做不了。

### 1. App ID(Certificates, Identifiers & Profiles → Identifiers)

- Bundle ID:`com.tianpli.aidash`(与 `Configs/Identity.xcconfig` 的
  `AIDASH_BUNDLE_ID` 一致;若你改了 `AIDASH_BUNDLE_PREFIX`,这里跟着改)
- 勾上 **iCloud** capability,并关联容器 **`iCloud.com.tianpli.aidash`**
  (容器不存在就在 CloudKit Dashboard 建)

> App ID 加了 capability 之后,旧的 provisioning profile 是加能力**之前**的快照。
> lane 里用 `get_provisioning_profile(force: true)` 每次重新生成,正是为了避免
> 复用过时 profile 导致 `doesn't include the iCloud capability` 签名失败。

### 2. 证书

runner 那台 Mac 的登录钥匙串里要有 **Apple Distribution** 证书(付费 team)。
已经在本机用 Xcode 发过包的话通常已经有了;没有就在 Xcode →
Settings → Accounts → Manage Certificates 里加。

### 3. App Store Connect

- 建 app 记录:平台 iOS,Bundle ID 选 `com.tianpli.aidash`,SKU 随意
- TestFlight → 建 **Internal** 测试群组,**名字就叫 `Internal`**(大小写敏感)
  - 想用别的名字:给 workflow 的 fastlane 步骤加环境变量
    `TESTFLIGHT_GROUPS=你的组名`(逗号分隔可多组)
  - 名字对不上时 lane **不会挂**,只打印 `Beta group '...' not found` 并跳过
    —— binary 已经传上去了,手动加进群组即可

> ⚠️ ASC 对「Xcode/API 上传的 build」的 internal 群组强制**手动分发**,没有自动
> 分发开关;而 `upload_to_testflight` 的 `groups:` 参数只在 `distribute_external:
> true` 时生效,对 internal **完全无效**(VitalStride 2026-07 踩过:日志无任何
> 分发动作也不报错,测试员就是看不到)。所以 lane 在上传后用 spaceship 显式调
> ASC API 把 build 加进群组。

---

## 三、首次验证(用户手动,非 CI 阻塞)

前置配完后,手动触发一次强制发布:

```bash
gh workflow run testflight.yml -f force=true
gh run watch
```

`force=true` 会绕过「无新提交」检查。成功的标志:ASC 里出现一个新 build,
且已分发到 Internal 群组,测试员的 TestFlight app 里能看到。

真实上传**不是 CI 阻塞项** —— `build.yml` 的 iOS 构建门(T204)才是每个 PR 都跑的
硬门;TestFlight 发布是定时任务,失败了修完重跑即可。

---

## 四、日常运转

- **定时**:每天 03:07 CST(`cron: "7 19 * * *"`)。分钟取 7 是避开 GitHub cron
  整点高峰的排队延迟。
- **只在有新提交时才 build**:上次发布点记在 moving tag
  `testflight/last-released`。累积式 —— build 失败或机器关机期间不丢 commit,
  下次开机的 cron 会把攒的一起发。
- **runner 离线 = 不发布**,不报错,下次开机补上。
- **build number 全局单调递增**:`latest_testflight_build_number` 刻意**不传**
  `version:`,查的是该 app 所有版本的最大 build number,next = latest + 1。
  传了 version 会把查询限定在当前 marketing version 内,bump 版本后 build 从 1
  重来,反而比旧版本的 build number 小,被 ASC 当成更旧的构建。
- **改 marketing version**:改 `project.yml` 的 `MARKETING_VERSION` 一处即可
  (`Info.plist` 里写的是 `$(MARKETING_VERSION)`,不是字面量)。

---

## 五、排查

| 症状 | 原因 / 处理 |
|---|---|
| `找不到 Apple Developer Team ID` | `ASC_TEAM_ID` secret 没配(或本机没有 `Identity.local.xcconfig`) |
| `errSecInternalComponent` | 钥匙串没解锁 → 查 `KEYCHAIN_PASSWORD` 是否为该机真实登录密码 |
| `doesn't include the iCloud capability` | App ID 没勾 iCloud / 没关联容器(见前置 1) |
| build 传上去但测试员看不到 | Internal 群组名对不上 → 核对名字或设 `TESTFLIGHT_GROUPS` |
| `The bundle version must be higher than...` | 上一次发布中断导致 ASC 已有同号 build;重跑一次即可(会取新的 max+1) |
| workflow 一直 queued | runner 离线 → `cd ~/actions-runner-aidash && ./svc.sh start` |

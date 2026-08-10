# AIDash — 身份解析(Bundle ID / Team ID)的单一来源,供 Appfile + Fastfile 共用。
#
# 存在理由:宪法 §No Identity in Version Control —— 本仓库 public,Apple Team ID
# 不能进版本库。但 fastlane 必须拿到真实 Team ID 才能拉 provisioning profile、
# 签名、上传。于是把「去哪儿找」这件事收敛到这一个文件:
#
#   Team ID 查找顺序(先命中先用):
#     1. ENV["AIDASH_DEVELOPMENT_TEAM"]  —— CI 从 GitHub secret 注入
#     2. Configs/Identity.local.xcconfig  —— 本机 git-ignored 覆盖(开发者已有)
#     未命中 → 抛错并说明怎么配,绝不静默用占位符 REPLACE_ME 去签名
#     (那会得到一个「profile 找不到」的迷惑错误,而不是「你没配 Team ID」)。
#
#   Bundle ID 同样两级,但**允许**兜底到 Configs/Identity.xcconfig 的
#   受版本控制默认值(bundle ID 是宪法豁免项,公开无害)。
#
# 只解析 xcconfig 的简单 `KEY = VALUE` 行 —— 不做变量展开,所以取的是
# Identity.local.xcconfig 里的字面值。这与 xcodegen 的行为一致(local 覆盖优先)。

module AIDash
  module Identity
    REPO_ROOT = File.expand_path("..", __dir__).freeze

    TRACKED_XCCONFIG = File.join(REPO_ROOT, "Configs", "Identity.xcconfig").freeze
    LOCAL_XCCONFIG = File.join(REPO_ROOT, "Configs", "Identity.local.xcconfig").freeze

    # 受版本控制的占位符 —— 命中它等于「没配」,必须当作未设置。
    TEAM_PLACEHOLDER = "REPLACE_ME".freeze

    module_function

    # 从 xcconfig 里读一个 key 的字面值。文件不存在 / key 不存在 → nil。
    # 只认 `KEY = VALUE` 与 `KEY=VALUE`,忽略 // 注释行。
    def xcconfig_value(path, key)
      return nil unless File.file?(path)

      File.foreach(path) do |line|
        stripped = line.strip
        next if stripped.empty? || stripped.start_with?("//")

        match = stripped.match(/\A#{Regexp.escape(key)}\s*=\s*(.+)\z/)
        next if match.nil?

        value = match[1].split("//").first.to_s.strip
        return value unless value.empty?
      end
      nil
    end

    def presence(value)
      return nil if value.nil?

      stripped = value.strip
      stripped.empty? ? nil : stripped
    end

    # Apple Developer Team ID(10 位)。找不到就抛错——签名没有合理的默认值。
    def team_id
      from_env = presence(ENV["AIDASH_DEVELOPMENT_TEAM"])
      return from_env unless from_env.nil?

      from_local = presence(xcconfig_value(LOCAL_XCCONFIG, "AIDASH_DEVELOPMENT_TEAM"))
      return from_local unless from_local.nil? || from_local == TEAM_PLACEHOLDER

      raise <<~MSG
        [AIDash] 找不到 Apple Developer Team ID。

        本仓库是 public,Team ID 不进版本库(宪法 §No Identity in Version Control),
        所以必须由环境提供其一:

          · CI    : 设 GitHub secret ASC_TEAM_ID(workflow 会注入为 AIDASH_DEVELOPMENT_TEAM)
          · 本机  : cp Configs/Identity.local.xcconfig.example Configs/Identity.local.xcconfig
                    并填入真实的 AIDASH_DEVELOPMENT_TEAM(developer.apple.com → Membership)

        当前 Configs/Identity.xcconfig 里是占位符 #{TEAM_PLACEHOLDER},不能用于签名。
      MSG
    end

    # App 的 Bundle ID。可以安全兜底到受版本控制的默认值(宪法豁免项)。
    def app_identifier
      from_env = presence(ENV["AIDASH_BUNDLE_ID"])
      return from_env unless from_env.nil?

      from_local = presence(xcconfig_value(LOCAL_XCCONFIG, "AIDASH_BUNDLE_ID"))
      return from_local unless from_local.nil?

      # Identity.xcconfig 里 AIDASH_BUNDLE_ID 定义为 $(AIDASH_BUNDLE_PREFIX).aidash,
      # 这里不做 xcconfig 变量展开,而是用 prefix 自己拼(与那边的惯例一致)。
      prefix = presence(xcconfig_value(LOCAL_XCCONFIG, "AIDASH_BUNDLE_PREFIX")) ||
               presence(xcconfig_value(TRACKED_XCCONFIG, "AIDASH_BUNDLE_PREFIX")) ||
               "com.tianpli"
      "#{prefix}.aidash"
    end
  end
end

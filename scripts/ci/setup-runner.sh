#!/usr/bin/env bash
# 一次性:在本机注册 AIDash 的 GitHub self-hosted runner。
#
# 为什么在本机跑 review:claude-review workflow 用你**已登录订阅**的本地
# `claude` CLI(读 ~/.claude 凭证),所以 runner 必须以你当前用户身份运行,
# 不需要 ANTHROPIC_API_KEY。
#
# 用法(在你的终端里):
#     ./scripts/ci/setup-runner.sh
#
# 之后启动:
#     cd ~/actions-runner-aidash && ./run.sh          # 前台(测试用)
#   或装成随登录自启的服务:
#     cd ~/actions-runner-aidash && ./svc.sh install && ./svc.sh start
#
# 依赖:gh(已认证,对 repo 有 admin)、curl、tar。

set -euo pipefail

REPO="LeePepe/AIDash"
RUNNER_DIR="$HOME/actions-runner-aidash"
LABELS="self-hosted,aidash-mac"
NAME="aidash-mac"
VERSION="${RUNNER_VERSION:-2.335.1}"   # 可用 RUNNER_VERSION=x.y.z 覆盖

# arm64 mac → osx-arm64;Intel → osx-x64
case "$(uname -m)" in
    arm64) PLAT="osx-arm64" ;;
    x86_64) PLAT="osx-x64" ;;
    *) echo "unsupported arch: $(uname -m)"; exit 1 ;;
esac
TARBALL="actions-runner-${PLAT}-${VERSION}.tar.gz"
URL="https://github.com/actions/runner/releases/download/v${VERSION}/${TARBALL}"

echo "==> runner ${VERSION} ${PLAT} → ${RUNNER_DIR}"
mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

if [ ! -x "./config.sh" ]; then
    echo "==> 下载 ${TARBALL}"
    curl -fsSL -o "$TARBALL" "$URL"
    tar xzf "$TARBALL"
    rm -f "$TARBALL"
fi

echo "==> 申请注册 token(短时有效)"
REG_TOKEN="$(gh api -X POST "repos/${REPO}/actions/runners/registration-token" --jq .token)"

echo "==> 配置 runner"
./config.sh \
    --url "https://github.com/${REPO}" \
    --token "$REG_TOKEN" \
    --name "$NAME" \
    --labels "$LABELS" \
    --work "_work" \
    --unattended \
    --replace

echo ""
echo "✅ 注册完成。启动方式:"
echo "   前台测试: (cd $RUNNER_DIR && ./run.sh)"
echo "   装成服务: (cd $RUNNER_DIR && ./svc.sh install && ./svc.sh start)"
echo ""
echo "注意:服务以你当前用户运行,才能读到 ~/.claude 订阅凭证。"

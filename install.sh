#!/usr/bin/env bash
#
# install.sh — SUNMI 公开发布平台 · 统一一键安装入口
#   仓库：kevinwangl/sunmi-dist（public）
#
# 用法：
#   # 装某产品最新版（最常用）
#   curl -fsSL https://raw.githubusercontent.com/kevinwangl/sunmi-dist/main/install.sh | bash -s -- <product>
#   # 装指定版本
#   curl -fsSL .../install.sh | bash -s -- <product> v1.2.0
#   # 不传产品名 → 打印可装产品清单
#   curl -fsSL .../install.sh | bash
#
# 设计（见私有仓 CURL发布方案.md）：
#   - 多产品隔离：Release 复合 tag <product>/v<x.y.z>
#   - latest：方式二 · 移动 latest tag（固定 URL <product>/latest，不调 GitHub API）
#   - 产品差异（后置步骤）全部由 products/<product>.json 驱动，本脚本保持通用
#   - 下载后 sha256 校验，防传输损坏/篡改
#
set -uo pipefail

# ---- 平台常量 ----
GH_OWNER="kevinwangl"
GH_REPO="sunmi-dist"
RAW_BASE="https://raw.githubusercontent.com/${GH_OWNER}/${GH_REPO}/main"
REL_BASE="https://github.com/${GH_OWNER}/${GH_REPO}/releases/download"
INSTALL_DIR_DEFAULT="$HOME/.local/bin"

PRODUCT="${1:-}"
VERSION="${2:-}"   # 形如 v1.2.0 或 1.2.0；留空 = latest

say()  { printf '%s\n' "$*"; }
die()  { printf '✗ %s\n' "$*" >&2; exit 1; }

# ---- 0) 禁止 sudo/root（Homebrew 后置步骤会失败）----
if [ "$(id -u)" -eq 0 ]; then
  die "请不要用 sudo 运行本脚本（后置的 Homebrew 安装禁止以 root 执行）。请用本人账号直接运行。"
fi

# ---- 1) 依赖：curl 必需；jq 可选（缺则用 grep/sed 回退）----
command -v curl >/dev/null 2>&1 || die "未找到 curl，请先安装 curl。"

HAVE_JQ=0
command -v jq >/dev/null 2>&1 && HAVE_JQ=1

# fetch <url> → stdout；失败返回非零
fetch() { curl -fsSL "$1"; }

# 从 JSON 文本读取字段：json_get <json> <jq-filter> <grep-key-fallback>
# jq 存在用 jq；否则对简单标量用 grep/sed 粗解析（仅支持平铺的 "key": "value" / true/false）
json_str() {  # json_str <json> <key>
  local json="$1" key="$2"
  if [ "$HAVE_JQ" -eq 1 ]; then
    printf '%s' "$json" | jq -r --arg k "$key" '.[$k] // empty'
  else
    printf '%s' "$json" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 \
      | sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/'
  fi
}
json_bool() {  # json_bool <json> <dotted-path-or-key> ；仅用于 post_install.* 布尔
  local json="$1" key="$2"
  if [ "$HAVE_JQ" -eq 1 ]; then
    printf '%s' "$json" | jq -r "$key // false"
  else
    # 回退：直接找 "key": true（不区分嵌套层级，产品 json 为平铺结构足够）
    local leaf="${key##*.}"
    printf '%s' "$json" | grep -o "\"$leaf\"[[:space:]]*:[[:space:]]*true" >/dev/null 2>&1 \
      && echo true || echo false
  fi
}

# ---- 2) 无产品名 → 列清单 ----
list_products() {
  say "SUNMI 公开发布平台 · 可安装产品："
  say ""
  # products/ 下有哪些产品：GitHub 无目录列举 API 的免 token 简法，这里读内置清单文件 products/index.txt
  local idx
  if idx="$(fetch "${RAW_BASE}/products/index.txt")"; then
    while IFS= read -r p; do
      [ -z "$p" ] && continue
      local meta disp
      meta="$(fetch "${RAW_BASE}/products/${p}.json" 2>/dev/null || true)"
      disp="$(json_str "$meta" display_name)"
      printf '  • %-22s %s\n' "$p" "${disp:-}"
    done <<< "$idx"
  else
    say "  （无法获取产品清单，请检查网络或仓库 products/index.txt）"
  fi
  say ""
  say "安装：curl -fsSL ${RAW_BASE}/install.sh | bash -s -- <product> [version]"
}

if [ -z "$PRODUCT" ]; then
  list_products
  exit 0
fi

say "== SUNMI 发布平台 · 安装 ${PRODUCT} =="

# ---- 3) 读产品元数据 ----
META="$(fetch "${RAW_BASE}/products/${PRODUCT}.json" 2>/dev/null || true)"
[ -n "$META" ] || { say "✗ 未知产品：${PRODUCT}"; say ""; list_products; exit 1; }

ASSET="$(json_str "$META" asset)"
[ -n "$ASSET" ] || die "产品 ${PRODUCT} 的元数据缺少 asset 字段。"
INSTALL_DIR="$(json_str "$META" install_dir)"
INSTALL_DIR="${INSTALL_DIR:-$INSTALL_DIR_DEFAULT}"
INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"   # 展开 ~

# 后置步骤开关
PI_HOMEBREW="$(json_bool "$META" '.post_install.homebrew')"
PI_GITSECRETS="$(json_bool "$META" '.post_install.git_secrets_template')"
PI_QUARANTINE="$(json_bool "$META" '.post_install.strip_quarantine')"
# brew 工具列表
if [ "$HAVE_JQ" -eq 1 ]; then
  BREW_TOOLS="$(printf '%s' "$META" | jq -r '.post_install.brew_tools[]? // empty' | tr '\n' ' ')"
else
  BREW_TOOLS="$(printf '%s' "$META" | grep -o '"brew_tools"[^]]*]' \
    | grep -o '"[a-z0-9-]*"' | sed 's/"//g' | grep -v brew_tools | tr '\n' ' ')"
fi

# ---- 4) 定位 tag（方式二）----
if [ -z "$VERSION" ]; then
  TAG="${PRODUCT}/latest"
  say "→ 版本：latest（${TAG}）"
else
  case "$VERSION" in
    v*) : ;;        # 已带 v
    *)  VERSION="v${VERSION}" ;;
  esac
  TAG="${PRODUCT}/${VERSION}"
  say "→ 版本：${VERSION}（${TAG}）"
fi

# ---- 5) 下载 asset + sha256 ----
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ART_URL="${REL_BASE}/${TAG}/${ASSET}"
SHA_URL="${ART_URL}.sha256"

say "↓ 下载 ${ASSET} ..."
curl -fL --progress-bar "$ART_URL" -o "$TMP/$ASSET" \
  || die "下载失败：$ART_URL（确认该 tag 的 Release 已发布且 asset 名正确）"

# ---- 6) sha256 校验（有 .sha256 则强校验；无则告警继续）----
if curl -fsSL "$SHA_URL" -o "$TMP/$ASSET.sha256" 2>/dev/null; then
  EXPECTED="$(awk '{print $1}' "$TMP/$ASSET.sha256")"
  ACTUAL="$(shasum -a 256 "$TMP/$ASSET" | awk '{print $1}')"
  if [ "$EXPECTED" = "$ACTUAL" ]; then
    say "✓ sha256 校验通过"
  else
    die "sha256 校验失败！期望 ${EXPECTED}，实际 ${ACTUAL}。已中止，未安装。"
  fi
else
  say "⚠️  未找到 ${ASSET}.sha256，跳过校验（建议发布端补齐）"
fi

# ---- 7) 安装二进制 ----
mkdir -p "$INSTALL_DIR"
cp "$TMP/$ASSET" "$INSTALL_DIR/$ASSET"
chmod +x "$INSTALL_DIR/$ASSET"
[ "$PI_QUARANTINE" = "true" ] && xattr -d com.apple.quarantine "$INSTALL_DIR/$ASSET" 2>/dev/null || true
say "✓ 已安装到 ${INSTALL_DIR}/${ASSET}"

# ---- 8) 后置步骤（由产品 json 驱动）----
ensure_brew() {
  if ! command -v brew >/dev/null 2>&1; then
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
      [ -x "$b" ] && eval "$("$b" shellenv)" && break
    done
  fi
  if ! command -v brew >/dev/null 2>&1; then
    say "未检测到 Homebrew，正在安装（需联网，可能需要密码）..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
      || { say "✗ Homebrew 安装失败，请手动安装后重试：https://brew.sh"; return 1; }
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
      [ -x "$b" ] && eval "$("$b" shellenv)" && break
    done
  fi
  say "✓ Homebrew 就位"
}

if [ "$PI_HOMEBREW" = "true" ]; then
  ensure_brew || true
  for tool in $BREW_TOOLS; do
    if command -v "$tool" >/dev/null 2>&1; then
      say "✓ $tool 已安装"
    else
      say "↓ 安装 $tool ..."
      if err="$(brew install "$tool" 2>&1)"; then
        say "✓ $tool 安装完成"
      else
        say "✗ $tool 安装失败（可手动重试：brew install $tool）"
        printf '%s\n' "$err" | sed 's/^/    /'
      fi
    fi
  done
fi

if [ "$PI_GITSECRETS" = "true" ] && command -v git-secrets >/dev/null 2>&1; then
  TPL="$HOME/.git-secrets-template"
  CUR="$(git config --global init.templateDir 2>/dev/null || true)"
  if [ -n "$CUR" ] && [ -f "${CUR/#\~/$HOME}/hooks/pre-commit" ]; then
    say "✓ git-secrets 全局模板已配置"
  else
    git secrets --register-aws --global >/dev/null 2>&1 || true
    git secrets --install "$TPL" -f >/dev/null 2>&1 || true
    git config --global init.templateDir "$TPL" >/dev/null 2>&1 || true
    [ -f "$TPL/hooks/pre-commit" ] \
      && say "✓ git-secrets 全局模板配置完成：$TPL" \
      || say "⚠️  git-secrets 模板配置未生效，请手动检查"
  fi
fi

# ---- 9) PATH 提示 ----
case ":$PATH:" in
  *":$INSTALL_DIR:"*) : ;;
  *) say ""
     say "提示：${INSTALL_DIR} 不在 PATH 中，请加入 shell 配置（如 ~/.zshrc）："
     say "    export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

say ""
say "安装完成。运行 ${ASSET} 开始使用。"

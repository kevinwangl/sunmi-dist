# 发布协议 · RELEASE-PROTOCOL

本文件约束如何向 `kevinwangl/sunmi-dist` 发布 release。所有产品统一遵循。

---

## 1. 命名空间与版本

- **Release tag 格式（硬约束）**：`<product>/v<MAJOR.MINOR.PATCH>`，例：`pc-security-check/v0.1.0`
- **移动 latest tag**：每个产品额外维护 `<product>/latest`，每次发版重新指向最新版本。
  `install.sh` 不传版本时即下载此 tag，故它必须始终存在且指向最新正式版本。
- **版本号来源（SSOT）**：产品源码的 `Cargo.toml` 的 `version` 字段。
  发布前校验当前 commit 已打对应 git tag `v<x.y.z>`，保证"二进制 ↔ 明确提交"可回溯。

---

## 2. 每个 Release 的 asset

| asset | 必需 | 说明 |
| --- | --- | --- |
| `<asset>` | 是 | 产品二进制（macOS universal） |
| `<asset>.sha256` | 是 | `shasum -a 256 <asset>` 的输出，供安装端强校验 |

`<asset>` 名需与 `products/<product>.json` 的 `asset` 字段一致。

---

## 3. 上架新产品

1. 在 `products/` 下新增 `<product>.json`（见下方字段说明）。
2. 在 `products/index.txt` 追加一行 `<product>`。
3. 推送该产品首个 Release（见 §4）。
4. `install.sh` 无需改动。

### products/&lt;product&gt;.json 字段

```json
{
  "name": "pc-security-check",
  "display_name": "个人 PC 季度安全自查工具",
  "asset": "pc-security-check",
  "install_dir": "~/.local/bin",
  "post_install": {
    "homebrew": true,
    "brew_tools": ["gitleaks", "git-secrets", "semgrep"],
    "git_secrets_template": true,
    "strip_quarantine": true
  }
}
```

| 字段 | 语义 |
| --- | --- |
| `name` | 产品名，须等于文件名与 tag 前缀 |
| `display_name` | 清单展示名 |
| `asset` | Release 里二进制 asset 的文件名 |
| `install_dir` | 安装目录，支持 `~` |
| `post_install.homebrew` | 是否确保 Homebrew 就位 |
| `post_install.brew_tools` | 需 brew 安装的工具列表 |
| `post_install.git_secrets_template` | 是否配置 git-secrets 全局模板 |
| `post_install.strip_quarantine` | 是否去除 macOS quarantine |

---

## 4. 发布流程（由 release-to-dist.sh 执行）

发布脚本位于**私有源码仓** `office-infosec/pc-security-check/release-to-dist.sh`，由 `build.sh` 在编译出 universal 二进制后调用，或手动运行：

```bash
# 私有仓内，需先 gh auth login
bash pc-security-check/release-to-dist.sh pc-security-check ./pc-security-check/dist/pc-security-check
```

脚本保证的硬约束：
1. 从 `Cargo.toml` 读版本号 → 拼 tag `pc-security-check/v<x.y.z>`。
2. 校验 git tag `v<x.y.z>` 存在（不存在则中止，提示先打 tag）。
3. tag 格式校验：必须 `<product>/v<MAJOR.MINOR.PATCH>`。
4. **二进制敏感串体检**：扫描内网域名 / 密钥 / 硬编码敏感信息，命中即中止（禁止上架）。
5. 生成 `<asset>.sha256`。
6. 发正式版本 Release（永久、可回溯）。
7. 移动 `latest`：先删旧 `<product>/latest`（含 tag），再重建指向本次 asset。
   顺序保证：正式版本先发成功，再动 latest；latest 失败不影响正式版本。

---

## 5. "勿外传" 红线

- 本仓库 public ⇒ 所有 Release 二进制**全世界可下载**。
- 每个产品首次上架前须过"可公开"评审。
- **源码、制度文档、内网信息永不进本仓库。**
- 二进制敏感串体检（§4.4）过检后方可 `gh release create`。

# sunmi-dist · SUNMI 公开发布平台

公司内部工具的统一一键安装入口。本仓库**只放安装脚本与编译产物（GitHub Release）**，不含任何源码。

> 内部工具，供公司员工在本机安装使用。

---

## 一键安装

```bash
# 安装某产品最新版（最常用）
curl -fsSL https://raw.githubusercontent.com/kevinwangl/sunmi-dist/main/install.sh | bash -s -- <product>

# 安装指定版本
curl -fsSL https://raw.githubusercontent.com/kevinwangl/sunmi-dist/main/install.sh | bash -s -- <product> v1.2.0

# 查看可安装产品清单
curl -fsSL https://raw.githubusercontent.com/kevinwangl/sunmi-dist/main/install.sh | bash
```

安装脚本会：下载对应 Release 的二进制 → **sha256 校验** → 装到 `~/.local/bin` → 去除 macOS quarantine → 执行该产品声明的后置步骤（如安装依赖工具）。

---

## 产品目录

| 产品 | 说明 | 安装命令 |
| --- | --- | --- |
| `pc-security-check` | 个人 PC 季度安全自查工具 | `curl -fsSL https://raw.githubusercontent.com/kevinwangl/sunmi-dist/main/install.sh \| bash -s -- pc-security-check` |

### pc-security-check 首次安装会额外做

- 安装 Homebrew（如缺）
- 安装 `gitleaks` / `git-secrets` / `semgrep`
- 配置 git-secrets 全局钩子模板

安装后：

```bash
pc-security-check            # 首次：交互式选检查项 + 扫描范围
pc-security-check --yes -o ~/Desktop   # 之后每季度：用上次配置直接跑
```

> 若提示 `~/.local/bin` 不在 PATH，按脚本提示加入 shell 配置后重开终端。

---

## 仓库结构

```
sunmi-dist/
├── install.sh              统一安装入口（产品/版本参数化、清单驱动、sha256 校验）
├── products/
│   ├── index.txt           产品索引（每行一个产品名）
│   └── <product>.json      产品元数据（asset 名、安装目录、后置步骤开关）
├── RELEASE-PROTOCOL.md     发布协议（维护者阅读）
└── README.md
```

二进制不在 git 本体，而是各产品 Release 的 asset：
`https://github.com/kevinwangl/sunmi-dist/releases/download/<product>/v<x.y.z>/<asset>`

---

## 维护者

发布新版本、上架新产品，见 [RELEASE-PROTOCOL.md](RELEASE-PROTOCOL.md)。

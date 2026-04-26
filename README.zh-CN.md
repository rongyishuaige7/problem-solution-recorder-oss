# Problem Solution Recorder（问题解决记录器）

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![Skill version](https://img.shields.io/badge/skill-0.1.0-blue)](./skill/problem-solution-recorder/SKILL.md)

[English README](README.md)

面向 AI 编程助手的 **Agent Skill**：在 skill 之外维护一套可配置的 **问题–解决 Markdown 知识库**，用于归档已解决问题、保留排障证据、维护人类索引与 AI 摘要索引、检索历史案例、沉淀可复用排障模式，以及做周期性复盘。

## 快速开始

```bash
git clone https://github.com/rongyi/problem-solution-recorder-oss.git
cd problem-solution-recorder-oss

skill/problem-solution-recorder/scripts/init-kb.sh "$HOME/problem-solution-kb"
export PROBLEM_SOLUTION_KB_ROOT="$HOME/problem-solution-kb"

skill/problem-solution-recorder/scripts/install.sh --symlink --codex --claude

skill/problem-solution-recorder/scripts/validate-skill.sh
skill/problem-solution-recorder/scripts/smoke-test.sh
```

## 工作原理

Skill 只提供 **工作流与脚本**；你的真实知识库仍是独立 git 仓库。Agent 先解析 `PROBLEM_SOLUTION_KB_ROOT`，再读 `AI入口.md`，按模板写入 `records/`，并更新 `INDEX.md` 与 `AI_SUMMARY_INDEX.md`。

## 仓库结构

```text
skill/problem-solution-recorder/     # 可发布到 ClawdHub / 本地安装的 skill 目录
examples/minimal-knowledge-base/     # 与内置模板同步的示例（含样例记录）
```

## 知识库根目录解析顺序

1. 环境变量 `PROBLEM_SOLUTION_KB_ROOT`
2. 当前或上级目录中的 `.problem-solution-root`
3. `$XDG_CONFIG_HOME/problem-solution-recorder/root`
4. `~/.config/problem-solution-recorder/root`
5. 询问用户或运行 `init-kb.sh` 初始化

## 本地安装

```bash
skill/problem-solution-recorder/scripts/install.sh --copy --all
```

常用参数：`--symlink`（开发联调）、`--dry-run`、`--uninstall`（仅删除由本安装器创建/标记的目录或指向本 skill 的符号链接）、`--skip-validate`（不推荐）。

## 发布到 ClawdHub

使用 `clawhub` CLI（注意不是 `clawdhub`）。每次发布需在 `SKILL.md` 的 frontmatter 中 **递增 `version`**，并附带 `--tags` 与 `--changelog`。首次发布前可能需在 [clawhub.ai](https://clawhub.ai) 接受条款；若 CLI 提示 license，可按版本说明使用 `--accept-license` 等参数。

详见根目录 [PUBLISHING.md](./PUBLISHING.md) 与 [README.md](./README.md) 中的英文命令示例。

## 安全

禁止写入真实 API key、token、cookie、密码、私钥等；统一使用 `[REDACTED]`。

## 贡献与行为准则

见 [CONTRIBUTING.md](./CONTRIBUTING.md) 与 [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md)。

## 许可证

MIT

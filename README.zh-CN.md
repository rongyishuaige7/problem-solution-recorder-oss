# Problem Solution Recorder（问题解决记录器）

> 面向 AI 工具和独立开发者的 Markdown 问题解决记忆库。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![Skill version](https://img.shields.io/badge/skill-0.2.0-blue)](./skill/problem-solution-recorder/SKILL.md)

[![English README](https://img.shields.io/badge/docs-English-0f62fe)](README.md)
中文说明

面向 AI 编程助手的 **Agent Skill**：在 skill 之外维护一套可配置的 **问题–解决 Markdown 知识库**，用于归档已解决问题、保留排障证据、维护人类索引与 AI 摘要索引、检索历史案例、沉淀可复用排障模式，以及做周期性复盘。

## 亮点

- 用纯 Markdown 记录已解决问题。
- 同时维护人类索引 `INDEX.md` 和 AI 索引 `AI_SUMMARY_INDEX.md`。
- 支持通过环境变量、项目标记或 XDG 配置定位知识库根目录。
- 提供记录、索引、校验、本地安装的一组辅助脚本。
- 自带知识库密钥扫描，便于提交和发布前检查敏感内容。

## 快速开始

```bash
git clone https://github.com/rongyishuaige7/problem-solution-recorder-oss.git
cd problem-solution-recorder-oss

skill/problem-solution-recorder/scripts/init-kb.sh "$HOME/problem-solution-kb"
export PROBLEM_SOLUTION_KB_ROOT="$HOME/problem-solution-kb"

skill/problem-solution-recorder/scripts/install.sh --symlink --codex --claude

skill/problem-solution-recorder/scripts/validate-skill.sh
skill/problem-solution-recorder/scripts/smoke-test.sh
skill/problem-solution-recorder/scripts/check-kb.sh "$PROBLEM_SOLUTION_KB_ROOT"
```

## 工作原理

Skill 只提供 **工作流与脚本**；你的真实知识库仍是独立 git 仓库。Agent 先解析 `PROBLEM_SOLUTION_KB_ROOT`，再读 `AI入口.md`，按模板写入 `records/`，并更新 `INDEX.md` 与 `AI_SUMMARY_INDEX.md`。

## 仓库结构

```text
skill/problem-solution-recorder/     # 可发布的 skill 目录（本地或注册表安装）
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

## 安全

禁止写入真实 API key、token、cookie、密码、私钥等；统一使用 `[REDACTED]`。

`check-kb.sh` 会扫描 Markdown 知识库中的疑似密钥，建议在提交、分享或重新生成 AI 摘要索引前运行。

## 贡献与行为准则

见 [CONTRIBUTING.md](./CONTRIBUTING.md) 与 [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md)。维护者发布与注册表说明见 [PUBLISHING.md](./PUBLISHING.md)。

## 许可证

MIT

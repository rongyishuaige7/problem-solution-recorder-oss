# AI 工具记录规则

把下面规则加入你常用 AI 工具的全局规则、项目规则或记忆文件中。

## 通用规则

```text
使用 Problem Solution Recorder 保存有复用价值的已解决问题。

知识库根目录解析顺序：
1. PROBLEM_SOLUTION_KB_ROOT
2. 当前项目或父目录的 .problem-solution-root
3. ~/.config/problem-solution-recorder/root
4. 如果仍找不到，询问用户

记录问题时：
- 先读取 AI入口.md 和 _templates/问题记录模板.md。
- 写入 records/YYYY/YYYY-MM-DD-NNN-short-topic.md。
- 更新 INDEX.md 和 AI_SUMMARY_INDEX.md。
- 方法可复用时，更新 patterns/。
- 不保存 API key、token、cookie、密码、私钥、授权码、session 或 bearer token 的真实值，统一写成 [REDACTED]。
```

## 完成后自动询问

```text
任务完成后，如果这是一次排障、工具接入、依赖/权限/配置/API/MCP/构建/测试/AI 工具异常问题，请静默判断是否值得记录。

强信号：
- 排查步骤超过三步
- 有明确原始现象、根因和最终修复
- 有失败尝试或误导路径
- 涉及本地环境、权限、认证、配置、依赖、适配器、MCP、API 或 AI 工具行为
- 解决方法以后可能复用

若至少两个强信号成立，并且用户没有明确拒绝记录，请问：
"这个问题值得记录到问题解决知识库吗？"

若用户已经要求记录，请直接记录。
```

## Codex 示例位置

```text
~/.codex/AGENTS.md
```

## Claude Code 示例位置

```text
~/.claude/CLAUDE.md
```

## OpenClaw 示例位置

```text
~/.openclaw/workspace/AGENTS.md
```

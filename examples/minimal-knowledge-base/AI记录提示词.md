# AI 记录提示词

这些提示词可以复制给 Codex、Claude Code、OpenClaw、Cursor 或其他 AI 编程工具。

## 记录已解决问题

```text
请把这次已经解决的问题记录到我的 Problem Solution Recorder 知识库。

要求：
- 先解析知识库根目录：PROBLEM_SOLUTION_KB_ROOT、.problem-solution-root、~/.config/problem-solution-recorder/root。
- 读取 AI入口.md 和 _templates/问题记录模板.md。
- 写入 records/YYYY/YYYY-MM-DD-NNN-short-topic.md。
- 更新 INDEX.md 和 AI_SUMMARY_INDEX.md。
- 如果方法可复用，更新 patterns/。
- 隐藏 API key、token、cookie、密码、私钥、授权码、session、bearer token 等秘密值。
```

## 搜索历史问题

```text
请在我的 Problem Solution Recorder 知识库里搜索相关历史问题。

优先读取 AI_SUMMARY_INDEX.md，其次搜索 patterns/，最后只打开相关的 records/YYYY/*.md。请总结命中的记录、复用经验和源文件路径。
```

## 复盘日报或周报

```text
请基于我的 Problem Solution Recorder 知识库生成复盘。

先读 AI_SUMMARY_INDEX.md，再按需打开相关 records。请输出重复出现的问题类型、可复用方法、未完成后续事项和下一步建议，并写入 reviews/。
```

## 完成后自动询问规则

```text
当你完成排障、环境配置、依赖修复、权限问题、MCP/API 集成、构建测试错误、AI 工具行为异常等任务后，请静默判断这件事是否值得以后复用。

如果满足至少两个信号：排查步骤超过三步、有明确根因、有失败尝试、涉及复杂配置或本地环境、以后可能复用，请问我：
"这个问题值得记录到问题解决知识库吗？"

如果我已经明确要求记录，则不要再问，直接记录。
```

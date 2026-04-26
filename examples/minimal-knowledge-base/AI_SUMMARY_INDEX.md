# AI Summary Index

Use this file as the first stop for AI recall. It is generated from records and can be edited by hand when more precision is needed.

## Entries

### 2026-01-15 - MCP tool call timeout under slow network

- source: `records/2026/2026-01-15-001-mcp-tool-timeout.md`
- status: solved
- tools: ["codex", "mcp"]
- tags: ["mcp", "timeout", "retry"]
- problem_signature: 调用 MCP 搜索工具时客户端报 `timeout` 或长时间无响应；同一请求在较快网络下可成功。
- root_cause: 单次请求 payload 偏大且默认超时偏短，在高延迟链路上容易触发客户端超时。
- final_fix: 调大 MCP 客户端超时配置。 拆分大查询为多个小查询。 对幂等读请求加入有限次数的指数退避重试。
- verification: 连续执行 20 次等价查询，失败率为 0；大查询拆分后 P95 延迟下降。
- reusable_lesson: 对 MCP/HTTP 类工具：先量 payload 与超时，再加退避重试；写清「可重试」边界避免破坏写操作。
- follow_up: 在 patterns 中沉淀一份 MCP 排障清单供团队复用。


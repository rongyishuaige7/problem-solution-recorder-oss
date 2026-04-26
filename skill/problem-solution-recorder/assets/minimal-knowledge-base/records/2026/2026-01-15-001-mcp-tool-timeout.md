---
title: "MCP tool call timeout under slow network"
date: "2026-01-15"
status: solved
tools: ["codex", "mcp"]
tags: ["mcp", "timeout", "retry"]
---

# MCP tool call timeout under slow network

## 一句话结论

MCP 工具偶发超时可通过增加超时时间、减少单次 payload、以及幂等重试解决。

## 原始现象

调用 MCP 搜索工具时客户端报 `timeout` 或长时间无响应；同一请求在较快网络下可成功。

## 环境与关键配置

- 工具：Codex + MCP server（示例名称 `[REDACTED]`）
- 网络：家庭宽带，偶发高延迟

## 排查时间线

1. 确认本地到 MCP 的网络与 DNS 正常。
2. 对比小查询与大查询成功率。
3. 查看 MCP server 日志中的处理耗时。

## 失败尝试

- 仅重复点击重试，无退避，仍易失败。

## 根因分析

单次请求 payload 偏大且默认超时偏短，在高延迟链路上容易触发客户端超时。

## 最终解决方案

- 调大 MCP 客户端超时配置。
- 拆分大查询为多个小查询。
- 对幂等读请求加入有限次数的指数退避重试。

## 验证方法

连续执行 20 次等价查询，失败率为 0；大查询拆分后 P95 延迟下降。

## 复用经验

对 MCP/HTTP 类工具：先量 payload 与超时，再加退避重试；写清「可重试」边界避免破坏写操作。

## 后续事项

- 在 patterns 中沉淀一份 MCP 排障清单供团队复用。

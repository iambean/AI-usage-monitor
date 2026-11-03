# Codex 认证恢复

AI Usage 使用自己启动的 `codex app-server`，该进程与 Codex 客户端独立运行。
客户端刷新登录或同步套餐后，监控子进程仍可能保留旧凭证，导致
`account/rateLimits/read` 返回 `401 Unauthorized / token_expired`。

正常刷新依次读取账户与用量。只有明确的认证失效才触发一次恢复：

1. 停止本应用的 App Server，丢弃其内存中的旧登录状态。
2. 启动新的 App Server，重新加载 Codex 管理的共享凭证。
3. 调用 `account/read`，传 `refreshToken: true`，由 Codex 完成令牌刷新。
4. 重新读取账户与用量，并使用恢复后的账户名称、套餐和历史记录范围。

单次刷新最多恢复一次；恢复仍失败时进入原有失败退避，并显示重新登录指引。
恢复操作之间至少间隔 30 秒，避免恢复期间产生的账户更新通知触发循环恢复。
网络超时、403 权限错误不触发认证恢复。正常查询仍使用 `refreshToken: false`，
避免每轮查询都刷新令牌。此流程只恢复只读查询，不重试额度重置操作。
账户更新通知仍使用现有 generation 校验，避免发布旧账户的在途结果。

AI Usage 不解析、记录或改写 Codex 的 access token 或 refresh token，也不退出
用户正在使用的 Codex 客户端。认证失败后清除旧额度，防止把缓存显示为最新结果。

验证：`swift test --filter CodexAuthenticationRecoveryTests` 通过本地模拟 App Server
及真实 JSON-RPC 管道覆盖过期后恢复、持续 401、刷新失败、恢复期间的账户更新通知、
正常查询和网络／权限错误。
测试使用合成账户，不连接服务端，也不消耗重置额度。

接口依据：[OpenAI App Server 认证接口](https://developers.openai.com/codex/app-server#auth-endpoints)。
其中 `account/read` 的 `refreshToken: true` 用于刷新 Codex 管理的 ChatGPT 登录令牌。

# AI Usage

一个原生 macOS 菜单栏工具，用来常驻显示 AI 编程工具或模型账户的剩余用量、余额等关键信息。

默认只启用 Codex。展开菜单后可以查看更详细的用量窗口，并可在设置中启用其他数据源。

## 支持情况

| 数据源 | 配置方式 | 展示内容 |
| --- | --- | --- |
| Codex | 自动检测本机 Codex CLI | 剩余百分比、各用量周期和重置时间 |
| Claude Code | 自动检测本机 Claude Code | 状态栏提供的用量窗口 |
| Kimi Code | 自动检测本机 Kimi Code 登录信息 | 套餐用量窗口 |
| MiniMax | Token Plan 订阅 Key | 剩余百分比和周期信息 |
| DeepSeek | API Key | API 余额 |
| Qoder Teams | API Key、Organization ID、Member ID | Teams 配额 |
| GLM Coding Plan | 暂不可用 | 保留入口，等待稳定查询接口 |

## 特点

- 原生 SwiftUI 菜单栏应用，支持 macOS 13 及以上版本
- 菜单栏常驻显示首个已启用数据源的关键用量
- 展开后逐行显示各数据源的详细信息
- 自动发现本机 Codex、Claude Code 和 Kimi Code，无需手动填写路径
- API Key 仅保存在本机 macOS 钥匙串
- 按数据源合理控制刷新频率，不进行高频轮询
- 支持登录时启动
- 同时支持 Apple Silicon 和 Intel Mac

## 本地构建

需要 Xcode Command Line Tools 或完整 Xcode。

```bash
swift test
./scripts/build-app.sh
open "dist/AI Usage.app"
```

生成通用架构的 DMG 和 ZIP：

```bash
./scripts/package-release.sh
```

默认使用 ad-hoc 签名。若要面向其他用户正式分发，请配置 Developer ID 签名并完成 Apple 公证：

```bash
AI_USAGE_SIGNING_IDENTITY="Developer ID Application: ..." \
  ./scripts/package-release.sh

AI_USAGE_NOTARY_PROFILE="notary-profile" \
  ./scripts/notarize-release.sh "dist/AI-Usage-<version>-universal.dmg"
```

## 隐私

- 应用不经过自建中转服务器。
- 本机工具的数据直接从对应 CLI 或本地缓存读取。
- MiniMax、DeepSeek 和 Qoder 的凭证保存在 macOS 钥匙串中。
- 需要查询厂商账户信息时，应用会直接请求对应厂商接口。

## 说明

本项目与 OpenAI、Anthropic、Moonshot AI、MiniMax、DeepSeek、Qoder、智谱 AI 无隶属或官方合作关系。产品名称、商标和品牌图标归各自权利人所有，仅用于标识对应的数据源。

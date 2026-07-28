# AI Usage

[English](./README.md) | 简体中文

一款轻量、原生的 macOS 菜单栏应用，用于查看 AI 编程服务的剩余额度、用量周期或账户余额。

应用默认只启用 Codex。你可以在设置中启用其他数据源；菜单栏会常驻显示第一个已启用数据源的精简摘要，展开后显示各数据源的详细信息。

> [!IMPORTANT]
> AI Usage 是独立、非官方的社区项目，与下列任何厂商均不存在隶属、授权、认可或赞助关系。

## 功能特点

- 基于 SwiftUI 的原生 macOS 菜单栏体验，支持 macOS 13 及以上版本
- 菜单栏常驻显示精简用量，展开后逐行查看详细数据
- 自动发现本机安装的 Codex、Claude Code 和 Kimi Code
- API 型数据源的凭证保存在 macOS 钥匙串
- 按数据源设置合理刷新间隔，避免不必要的频繁查询
- 支持登录时启动
- 同时支持 Apple Silicon 和 Intel Mac
- 不经过项目自建中转服务器，不包含项目自建的分析或遥测后端

## 数据源支持

| 数据源 | 状态 | 配置方式 | 展示内容 |
| --- | --- | --- | --- |
| Codex | 可用，默认启用 | 自动发现本机 Codex CLI | 剩余百分比、各用量周期和重置时间 |
| Claude Code | 可用 | 自动发现 Claude Code，并安装由本应用管理的状态栏采集器 | 可用用量周期和重置时间 |
| Kimi Code | 可用，尽力兼容 | 自动发现 Kimi Code，并读取本机登录态 | 套餐用量周期 |
| MiniMax | 可用，尽力兼容 | Token Plan 订阅 Key | 剩余百分比和重置周期 |
| DeepSeek | 可用 | DeepSeek API Key | API 账户余额 |
| Qoder Teams | 可用 | Teams API Key、Organization ID 和 Member ID | 套餐、资源包、团队共享和总额度 |
| GLM Coding Plan | 暂不可选 | 无 | 保留入口，等待稳定的用量查询集成 |

厂商接口和本地 CLI 数据格式可能在不通知本项目的情况下变化。“可用”表示本项目已经实现相应集成，不代表能够永久兼容上游变化。

## 安装

### 下载发布版本

发布产物可用时，请从
[GitHub Releases](https://github.com/iambean/codex-usage-monitor/releases)
下载最新的 DMG 或 ZIP。

对外发布版本应使用 Developer ID 证书签名并经过 Apple 公证。本地构建的 ad-hoc 安装包可能触发 macOS Gatekeeper 提示。

### 从源码构建

环境要求：

- macOS 13 或更高版本
- Xcode Command Line Tools 或完整 Xcode
- Swift 5.10 或更高版本

```bash
git clone https://github.com/iambean/codex-usage-monitor.git
cd codex-usage-monitor
swift test
./scripts/build-app.sh
open "dist/AI Usage.app"
```

生成通用架构的 DMG 和 ZIP：

```bash
./scripts/package-release.sh
```

打包脚本默认使用 ad-hoc 签名。面向其他用户分发时，请配置 Developer ID 签名和公证信息：

```bash
AI_USAGE_SIGNING_IDENTITY="Developer ID Application: ..." \
  ./scripts/package-release.sh

AI_USAGE_NOTARY_PROFILE="notary-profile" \
  ./scripts/notarize-release.sh "dist/AI-Usage-<version>-universal.dmg"
```

## 配置方式与本地改动

- **Codex：**应用自动定位 `codex` 可执行文件，并与其本地 App Server 进程通信。
- **Claude Code：**启用后可能在 `~/.claude/settings.json` 中添加由 AI Usage 管理的 `statusLine` 命令；如果已有其他 `statusLine` 配置，应用不会覆盖。关闭该数据源时，只移除由 AI Usage 创建的配置。
- **Kimi Code：**应用自动定位 `kimi` 可执行文件，并读取 Mac 上保存的 Kimi Code 登录态。
- **MiniMax、DeepSeek 和 Qoder：**密钥保存在 macOS 钥匙串；非敏感的数据源配置保存在应用的本地偏好设置中。
- **登录时启动：**通过 macOS Service Management 框架管理。

## 隐私与安全

- AI Usage 不运营任何中转服务器。
- 数据源请求由 Mac 直接发送至对应厂商。
- API Key 保存在 macOS 钥匙串中，不会写入本仓库。
- Codex、Claude Code 和 Kimi Code 集成只读取采集用量所需的本地状态。
- 应用不包含自建的分析或遥测服务。

各厂商仍会按照其隐私政策和服务条款处理请求。启用集成前，请自行阅读对应厂商政策。

## 开发方式：vibecoding

本项目明确公开为一个 **vibecoding 项目**。产品方向、交互决策、评审与发布验收由人类维护者负责；相当一部分实现和文档由 AI 编程 Agent（主要为 Codex）协助起草并迭代完成。

AI 辅助开发不代表代码天然正确。本项目会在可行范围内进行自动化测试、人工审查和真机验证，但使用者与贡献者仍应审查安全敏感行为，并及时报告问题。

## 参与贡献

欢迎提交 Issue 和 Pull Request。请注意：

1. 说明涉及的数据源、期望行为和实际行为。
2. 不要在 Issue 中提交 API Key、Access Token、账户标识或原始私密响应。
3. 修改解析器或数据源集成时，请同步新增或更新测试。
4. 提交 Pull Request 前运行 `swift test`。
5. 保持保守的查询频率，并遵循厂商的上游要求。

提交贡献即表示你同意相关内容可以按照本项目的 MIT License 分发。

## 第三方资源与商标

本仓库没有使用第三方 Swift Package 依赖。项目使用 Apple 系统框架和系统提供的 SF Symbols，并仅为识别数据源而包含各厂商的品牌标识。

厂商名称、产品名称、商标及 Logo 均归各自权利人所有，**不属于** MIT License 的授权范围。完整归属说明与许可证边界请参阅
[THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md)。

## 开源协议

源代码与项目原创资源采用 [MIT License](./LICENSE) 开源。

MIT License 不授予任何第三方商标、服务标识、Logo 或其他品牌资源的使用权，具体请参阅
[THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md)。

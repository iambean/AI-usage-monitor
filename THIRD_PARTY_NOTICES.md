# Third-Party Notices / 第三方资源声明

This document describes third-party resources referenced or used by AI Usage
and clarifies what is not covered by the project's MIT License.

本文说明 AI Usage 引用或使用的第三方资源，并明确不属于本项目 MIT License
授权范围的内容。

## 1. Bundled open-source dependency / 打包的开源依赖

AI Usage bundles Sparkle 2, an MIT-licensed macOS software-update framework:

AI Usage 打包了 Sparkle 2，这是一个采用 MIT License 的 macOS 软件更新框架：

| Dependency / 依赖 | Purpose / 用途 | License / 协议 | Source / 来源 |
| --- | --- | --- | --- |
| Sparkle 2 | Secure update download, verification, installation, and relaunch / 安全更新下载、验证、安装和重启 | MIT License | [sparkle-project/Sparkle](https://github.com/sparkle-project/Sparkle) |

The complete Sparkle license and bundled external notices are distributed as
`SPARKLE-LICENSE.txt` inside the app bundle.

Sparkle 的完整协议及其内含第三方声明会以 `SPARKLE-LICENSE.txt` 随 App Bundle
一同分发。

AI Usage does not redistribute the Codex, Claude Code, Kimi Code, MiniMax,
DeepSeek, Cursor, Qoder, Volcengine Ark, Alibaba Cloud Model Studio, Tencent
Cloud, or GLM applications, SDKs, or model weights.

AI Usage 不会重新分发 Codex、Claude Code、Kimi Code、MiniMax、DeepSeek、Cursor、Qoder、火山方舟、
阿里云百炼、腾讯云或 GLM 的应用、SDK 或模型权重。

## 2. Provider names and brand marks / 厂商名称与品牌标识

The following files are provider brand marks used only to identify their
corresponding integrations in the user interface:

下列文件是数据源品牌标识，仅用于在界面中识别对应集成：

| Resource / 资源 | Owner / 权利人 | Official reference / 官方参考 |
| --- | --- | --- |
| `Resources/ProviderIcons/provider-codex.png` | OpenAI — Codex | [Codex CLI documentation](https://developers.openai.com/codex/cli/) |
| `Resources/ProviderIcons/provider-claude.png` | Anthropic — Claude Code | [Claude Code documentation](https://code.claude.com/docs/en/overview) |
| `Resources/ProviderIcons/provider-cursor.png` | Anysphere — Cursor | [Cursor documentation](https://docs.cursor.com/) |
| `Resources/ProviderIcons/provider-kimi.png` | Moonshot AI — Kimi Code | [Kimi Code repository](https://github.com/MoonshotAI/kimi-code) |
| `Resources/ProviderIcons/provider-minimax.png` | MiniMax | [MiniMax Token Plan documentation](https://platform.minimax.io/docs/token-plan/intro) |
| `Resources/ProviderIcons/provider-deepseek.png` | DeepSeek | [DeepSeek API documentation](https://api-docs.deepseek.com/api/get-user-balance/) |
| `Resources/ProviderIcons/provider-qoder.png` | Qoder | [Qoder Teams OpenAPI documentation](https://docs.qoder.com/account/teams/openapi/index) |
| `Resources/ProviderIcons/provider-ark.png` | ByteDance — Volcengine Ark | [Volcengine Ark Coding Plan](https://www.volcengine.com/activity/codingplan) |
| `Resources/ProviderIcons/provider-aliyun.png` | Alibaba Cloud — Model Studio | [Model Studio Coding Plan documentation](https://help.aliyun.com/zh/model-studio/coding-plan) |
| `Resources/ProviderIcons/provider-tencent.png` | Tencent Cloud — Coding Plan | [Tencent Cloud Coding Plan](https://cloud.tencent.com/act/pro/codingplan) |
| `Resources/ProviderIcons/provider-glm.png` | Zhipu AI / Z.AI — GLM | [GLM Coding Plan documentation](https://docs.bigmodel.cn/cn/coding-plan/overview) |

All provider names, product names, trademarks, service marks, and logos are
the property of their respective owners. They are excluded from the project's
MIT License and are not offered for reuse, modification, or redistribution
under that license. Their inclusion does not imply affiliation, endorsement,
authorization, or sponsorship.

所有厂商名称、产品名称、商标、服务标识和 Logo 均归各自权利人所有。它们不属于
本项目 MIT License 的授权范围，本项目也不以该协议授予其复用、修改或再分发权。
包含这些标识不代表双方存在隶属、认可、授权或赞助关系。

If you redistribute a modified build, you are responsible for reviewing the
applicable trademark and brand-usage rules and replacing or removing marks
when necessary.

如果你再分发修改后的构建版本，应自行审查相关商标与品牌使用规则，并在必要时替换或
移除这些标识。

## 3. Apple platform resources / Apple 平台资源

AI Usage uses platform frameworks supplied with macOS, including Foundation,
SwiftUI, AppKit, Charts, Security, and ServiceManagement. It also references
system-provided SF Symbols by symbol name. These frameworks and symbols are
provided by Apple and remain subject to Apple's applicable licenses and usage
terms; they are not relicensed by this project.

AI Usage 使用 macOS 自带的平台框架，包括 Foundation、SwiftUI、AppKit、Charts、
Security 和 ServiceManagement，并通过符号名称引用系统提供的 SF Symbols。
这些框架与符号由 Apple 提供，继续受 Apple 相应许可和使用条款约束，本项目不会对其
重新授权。

Reference / 参考：

- [Apple Developer Terms and Agreements](https://developer.apple.com/support/terms/)
- [SF Symbols](https://developer.apple.com/sf-symbols/)

## 4. Project artwork / 项目原创视觉资源

`Resources/AppIcon-1024.png` is project-specific artwork. It is included with
the original project assets covered by the MIT License. It is not an official
icon of any provider.

`Resources/AppIcon-1024.png` 是本项目专属视觉资源，属于 MIT License 覆盖的
项目原创资源，并非任何厂商的官方图标。

## 5. External services and compatibility / 外部服务与兼容性

AI Usage interoperates with provider CLIs or HTTPS APIs. Use of those products
and services remains governed by each provider's own terms, privacy policy,
rate limits, and account rules. The project's MIT License applies only to AI
Usage itself.

AI Usage 会与厂商 CLI 或 HTTPS API 互操作。对这些产品与服务的使用仍受各厂商自身
服务条款、隐私政策、频率限制和账户规则约束；本项目 MIT License 仅适用于 AI Usage
自身。

Provider behavior and response formats may change without notice and may
temporarily break an integration. This project makes no warranty regarding
the availability or accuracy of third-party services.

厂商行为和响应格式可能随时变化，并可能暂时导致集成失效。本项目不对第三方服务的
可用性或数据准确性作出保证。

# CodexMulti

[English](README.md) · [한국어](README.ko.md) · [日本語](README.ja.md) · **简体中文** · [Español](README.es.md)

<p align="center">
  <img src="assets/hero.png" width="100%" alt="CodexMulti：一台 Mac，多个 Codex 账户，自动切换">
</p>

**一个 Codex 账户达到限额时，继续使用下一个。**

CodexMulti 将你的 Codex 账户集中在一个 macOS 菜单栏应用中。查看各账户的剩余用量，调整使用顺序，并在确认遇到用量限额错误时自动切换账户。

[下载](https://github.com/moonsunkim/codexmulti/releases/latest) · [更新日志](CHANGELOG.md) · [安全](SECURITY.md) · [参与贡献](CONTRIBUTING.md)

[![CI](https://github.com/moonsunkim/codexmulti/actions/workflows/ci.yml/badge.svg)](https://github.com/moonsunkim/codexmulti/actions/workflows/ci.yml)

- **查看整个账户池。** 剩余用量、重置时间和账户可用状态集中在一个窗口中。菜单栏显示账户池汇总，点击“账户…”即可打开完整列表。
- **设置使用顺序。** 拖动账户调整优先顺序。符合条件的请求遇到已确认的用量限额时，代理会尝试下一个可用账户。
- **一个开关即可启用。** 自动切换所需的本地代理和 Node 运行时均已内置。应用打开时，新添加或重新登录的账户会自动加入。
- **凭据留在本机。** 每个账户都有独立的 Codex 目录和钥匙串备份。无需注册 CodexMulti 账户，也无需连接托管服务。

## 什么是自动切换，为什么要使用它？

一个 Codex 账户达到用量限额时，即使其他账户仍有额度，编程任务也可能中断。没有自动切换时，你需要自行选择其他账户并重试请求。

**当前账户返回已确认的用量限额错误时，自动切换会尝试下一个可用账户。** 添加账户、调整顺序，然后打开“使用自动切换”。CodexMulti 会通过 Mac 上的本地代理转发符合条件的 Codex 请求。

例如，账户 A 在响应开始前达到限额，代理会使用账户 B 重试同一请求。如果 B 也达到限额，则继续尝试下一个符合条件的账户，无需每次手动切换。

各账户仍有独立的订阅和限额；自动切换只是让剩余容量更方便使用。它不会重放已开始的响应，也不会重试所有类型的错误。具体条件见[何时会切换账户](#何时会切换账户)。

## 安装

需要**运行 macOS 26 或更高版本的 Apple Silicon Mac**，以及使用 ChatGPT 登录的 Codex CLI。至少有两个账户时，自动切换才有实际作用。

```sh
brew install --cask moonsunkim/tap/codexmulti
```

也可以下载[最新版本](https://github.com/moonsunkim/codexmulti/releases/latest)。从 0.2.1 起，发布版本均使用 Developer ID 签名并经 Apple 公证。

<details>
<summary>脚本安装或手动安装</summary>

```sh
curl -fsSL https://raw.githubusercontent.com/moonsunkim/codexmulti/main/install.sh | bash
```

安装脚本会校验发布的 SHA-256，将已有应用保留为 `CodexMulti.app.previous`，安装至 `/Applications`，并在后台打开应用。Gatekeeper 的隔离属性会保留。

手动安装时，下载 `CodexMulti-<version>.zip` 和对应的 `.sha256` 文件，放在同一目录中，解压前先校验：

```sh
shasum -a 256 -c CodexMulti-<version>.zip.sha256
```

将校验通过的 `CodexMulti.app` 移至 `/Applications` 并打开。

</details>

## 两步开始使用

1. **添加账户。** 点击“+”，为账户命名，并在官方浏览器页面完成登录。重复此步骤，添加要放入账户池的其他账户。
2. **打开“使用自动切换”。** 打开“设置”。应用会准备内置代理、检查其运行状态，并将 Codex 连接至代理。

之后照常使用 Codex。如果账户在响应开始前返回已确认的用量限额错误，同一请求可通过下一个符合条件的账户继续。已暂停、无效或处于冷却状态的账户会被跳过。

应用打开时，添加账户、重新登录和顺序调整都会自动应用。需要重新加载代理的更改会等待当前请求完成。退出菜单栏应用后，正常运行的代理会继续工作；关闭自动切换后，当前请求完成时会恢复 Codex 的直接连接。

从菜单栏打开“账户…”可查看整个账户池。在账户的“…”菜单中，“用于自动切换…”会将该账户用于新请求。“暂停参与自动切换”会停止向该账户发送新请求；“恢复参与自动切换”会重新将其纳入。正在处理的请求继续使用原账户。

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/screenshots/accounts-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="assets/screenshots/accounts-light.png">
  <img alt="账户池：剩余用量、重置时间，以及使用中、就绪、冷却和暂停状态" src="assets/screenshots/accounts-light.png">
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/screenshots/settings-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="assets/screenshots/settings-light.png">
  <img alt="包含自动切换开关和语言选择器的设置界面" src="assets/screenshots/settings-light.png">
</picture>

你可以选择用量刷新间隔、优先显示的用量周期和主题。语言菜单支持**跟随系统、English、한국어、日本語、简体中文和 Español**。
中文目前支持简体（`zh-Hans`）；西班牙语使用通用版本（`es`）。选择“跟随系统”时会识别简体中文和西班牙语的地区设置。繁体中文尚未提供翻译。以上截图为英文界面。

<details>
<summary>查看账户详情</summary>

展开账户可查看用量周期、认证和自动切换状态、上次刷新时间，以及服务商报告的可用重置次数。

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/screenshots/accounts-expanded-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="assets/screenshots/accounts-expanded-light.png">
  <img alt="账户详情：用量、令牌状态、刷新时间和可用重置次数" src="assets/screenshots/accounts-expanded-light.png">
</picture>

所有截图均使用虚构账户。

</details>

## 何时会切换账户？

仅在收到已确认的用量限额响应后切换：流式响应开始前，HTTP `429` 的错误类型为 `usage_limit_reached`；WebSocket 握手期间返回同样的错误；或 Responses WebSocket 内部在任何响应事件送达客户端之前出现 `usage_limit_reached`。每个符合条件的账户在同一请求中最多尝试一次。

即使 Codex 复用现有 WebSocket，手动切换也会作用于下一个请求。已开始的响应会使用原账户完成。账户切换时会保留对话上下文，独立的流式响应可以继续，不受干扰。

网络故障、`5xx`、流中断、订阅不匹配、`usage_not_included` 和无法识别的 `429` 会终止请求。已开始的响应不会在其他账户上重放。若没有符合条件的账户，请求会失败，不会无限重试。

应用不会提高单个账户的限额或更改其订阅。代理兼容性随 Codex CLI 更新；升级前请查看[发布说明](https://github.com/moonsunkim/codexmulti/releases/latest)。

## 账户数据留在你的 Mac 上

没有遥测、分析或由 CodexMulti 托管的控制服务。认证、用量查询和推理直接连接服务商。代理仅监听回环地址，其控制 API 使用每用户私有的访问凭证。

每个账户使用独立的 Codex 主目录。凭据保留在本机，并备份到钥匙串；个人 `~/.codex/auth.json` 不会被替换。开启自动切换只会编辑 `~/.codex/config.toml` 中由应用管理的两个基础 URL 条目，并创建带时间戳的备份。关闭后恢复直接路由。

信任边界和日志处理详情见[安全说明](SECURITY.md)及[代理安全说明](proxy/README.md#state-logs-and-security)。

## 从源码构建

需要 `PATH` 中的 Zig 0.16.0，包含 Swift 6 和 macOS 26 SDK 的 Xcode（或命令行工具），以及运行 macOS 26 的 Apple Silicon Mac。

```sh
./app/scripts/fetch-node.sh                                        # 下载固定版本的 Node 并校验 SHA-256
./app/scripts/build-app.sh                                         # → app/dist/staging/CodexMulti.app
./app/scripts/screenshots.sh
./app/scripts/verify-provenance.sh app/dist/staging/CodexMulti.app
./app/scripts/verify-bundled-proxy.sh app/dist/staging/CodexMulti.app
```

构建会将核心编译为 `aarch64-macos` 对象，链接到 Swift 可执行文件，再与固定版本的 Node 和代理源码组装成应用。来源标记记录核心源码摘要、桥接协议、代理提交、内置代理目录摘要和 Node 哈希；`verify-provenance.sh` 会重新计算这些值，而非仅信任标记文本。

测试：

```sh
(cd core && zig build test && zig build test-bridge)
(cd app && CODEXMULTI_TEST_HEADLESS=1 swift test)   # 不要直接运行 swift test，否则会打开窗口
(cd proxy && npm test)
```

CI 在 macOS 上检查 Zig 核心、Node 代理、SwiftUI 界面和分发脚本。SwiftUI 检查使用 macOS 26 SDK。

签名和发布打包独立于普通构建。`app/scripts/package-signed-macos.sh` 会核验本地签名身份，先签名内置 Node，再由内向外签名应用；来源信息或指定签名要求不匹配时会拒绝打包。

添加或更新翻译时，请参阅 [i18n 维护说明](docs/i18n.md)。

## 架构

| 组件 | 职责 |
| --- | --- |
| [SwiftUI 应用](app/) | 窗口、菜单、辅助功能和 macOS 集成。 |
| [Zig 核心](core/) | 账户、后台任务、受保护的路由更改和全部界面文案。 |
| [Node 代理](proxy/) | 本地请求转发，以及符合条件的账户之间的自动切换。 |
| [原生更新器](updater/) | 已签名运行时的暂存、新请求接入控制和崩溃恢复。 |

应用向核心发送带类型的操作指令，并呈现返回的状态。代理作为每用户 LaunchAgent 独立运行，因此菜单栏应用退出后，请求仍可继续。代理及固定版本的 Node 均内置于应用中。完成一次性更新设置后，代理使用 `~/Library/Application Support/CodexMulti/runtimes/` 下经过验证、不可变的副本运行。

### 应用内更新

打开“设置”中的“软件更新”。首次设置需要关闭 Codex 客户端，因为旧版安装没有原子性的新请求接入控制。之后的更新会在替换应用时保留运行中的代理。若代理运行时有变化，会等待 HTTP 请求、WebSocket 连接和凭据刷新结束。仅更新界面时，会保留当前代理进程。运行时切换期间，新连接可能短暂失败；活动请求不会被强制中断或重放。

更新期间会暂停账户更改。设置界面显示待处理的更新，在停止操作正式提交前可取消，也可选择“请求结束后关闭”。菜单栏应用退出后，更新代理仍会继续运行。若新运行时无法启动，会恢复之前兼容的版本。仍存活但无法连接的进程需要恢复处理，不会被强制停止。若应用安装需要手动恢复，“显示旧版应用”可打开保留的已签名应用。

正式版本配置 HTTPS 更新源和固定的 Sparkle 公钥后可检查更新。本地未签名构建会显示分发配置不可用。详见[更新设计与实现约束](docs/update-design.md)和[发布配置](docs/updater-release.md)。

<details>
<summary>恢复、卸载和手动修复路由</summary>

开启自动切换期间，应用会重试恢复。更改需要等待当前请求时，状态会说明原因。关闭自动切换后，请求结束时会恢复 Codex 的直接路由。

已配置安全更新的安装，请先退出 Codex 客户端和 CodexMulti 菜单栏应用，然后运行：

```sh
"/Applications/CodexMulti.app/Contents/Helpers/codexmulti-update-agent" prepare-removal \
  --app "/Applications/CodexMulti.app" \
  --config "$HOME/.config/codexmulti/proxy.json"
brew uninstall --cask codexmulti
```

若代理配置路径不同，请使用实际路径。准备过程会等待请求结束，仅恢复 CodexMulti 管理的路由条目，并移除自动启动注册。若报告 `proxy_busy`，更新代理会继续等待；客户端结束后请重试准备操作。账户凭据、用量历史和重置记录会保留，供重新安装使用。

Homebrew cask 会在删除应用前确认卸载准备已完成。它标记为 `auto_updates`，日常升级请使用应用内更新器。Homebrew 无法向卸载脚本可靠地区分升级与卸载，因此未准备的 `--greedy` 升级和重新安装会在替换应用前停止，不会悄悄关闭自动切换。`--zap` 还会删除已保存的账户数据。没有原生更新辅助程序的旧版安装，卸载前请继续使用其内置的 `codexmulti-maintenance prepare-uninstall` 流程。

若应用或辅助程序无法运行，用文本编辑器打开 `~/.codex/config.toml`。仅移除存在的以下两个顶层条目，保留所有其他设置：

```toml
chatgpt_base_url = "http://127.0.0.1:8787/backend-api/"
openai_base_url = "http://127.0.0.1:8787/backend-api/codex"
```

接着检查 `launchctl print "gui/$(id -u)/dev.codexmulti.app.proxy"`。只有其程序参数指向你的 CodexMulti 应用中的 `Contents/Helpers/node`、`Contents/Resources/proxy/src/server.mjs`、`--config` 和你的代理配置时，才使用 `launchctl bootout "gui/$(id -u)/dev.codexmulti.app.proxy"` 停止它，并移除 `~/Library/LaunchAgents/dev.codexmulti.app.proxy.plist`。重启 Codex 客户端，使其重新读取直接连接配置。不要用旧备份替换整个共享配置文件。

代理控制需要每用户私有的访问凭证。普通 Codex 代理流量以本机为信任边界，因此只应在本地用户和进程均可信的 Mac 上使用。详见[代理安全说明](proxy/README.md#state-logs-and-security)。

</details>

## 许可证

MIT，详见 [LICENSE](LICENSE)。内置 Node.js 的声明收录于 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

CodexMulti 是独立的开源项目，与 OpenAI 无隶属关系，也未获其背书。Codex 是 OpenAI 的商标。

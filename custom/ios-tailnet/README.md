# Immich iOS 内嵌网络定制版

新增的独立 EasyTier 模块、三模式切换、凭据与地址约束见 [EasyTier 集成说明](../ios-easytier/README.md)。原有 Tailscale 身份和上游接入点保持兼容。以下原始 Tailscale 设计与历史安装说明不代表当前 Apple 团队状态；签名材料仅留在 Mac，CI 始终输出 unsigned。

此 fork 只增加 iOS 入口，可选择普通连接、内嵌 Tailscale 或内嵌 EasyTier。两个 SDK 使用进程内用户态网络及本机代理，互斥运行，不创建系统 VPN、NetworkExtension、Packet Tunnel 或 Funnel。Android、服务端、Web 不增加功能。定制版最低 iOS 18.1。

## 上游与改动边界

初始稳定基线：Immich `v3.3.5`，提交 `8303cb117e197c700332b33b61b45314c9cc5bb4`。
原 fork main：`fda68f972ff1f0e1f010f7083de2a4a75b59bce0`，保留在 `archive/main-before-tailnet-20261026`；不强制覆盖原历史。

| 位置 | 作用 |
| --- | --- |
| `mobile/ios/Tailnet/Sources/TailnetPlugin.swift` | 兼容桥接、共享代理、网络变化与有限后台任务 |
| `EmbeddedNetworkController.swift`、各 Provider | 互斥生命周期、独立 SDK、身份与就绪等待 |
| `mobile/ios/EasyTierCore/`、`custom/ios-easytier/` | 独立 EasyTier 二进制依赖、锁定构建与协议验证 |
| `mobile/ios/Runner/Core/URLSessionManager.swift` | 唯一的原生会话配置边界，保留官方 Cookie、证书、请求头处理 |
| `mobile/ios/Runner/AppDelegate.swift` | 把官方 API/图片会话、下载器、视频层接到同一策略 |
| `mobile/lib/infrastructure/repositories/network.repository.dart` | 共享客户端的稳定转发引用，原生会话更换时业务对象不用重建 |
| `mobile/lib/tailnet/` | 连接开关、授权、状态与后台限制提示，无上传/下载业务实现 |
| `patches/background-downloader.patch` | 为固定依赖增加会话工厂和失效重建接口；依赖不认识 Tailscale |
| `patches/video-loopback.patch` | 复用官方视频转发器，限定 loopback 并校验随机访问令牌 |
| `tests/` | 临时 tailnet、HTTP/HTTPS、图片、multipart、WS/WSS、Range、取消及身份恢复的模拟器测试 |

没有给登录、缩略图、上传、下载和分享各写一套网络代码。官方 Dart 上传/下载/分享逻辑保留。后台备份入口只有显式策略检查；备份和网络设置页面增加状态组件。官方 URLSession 的证书校验继续有效。

上游根目录及稳定基线中未找到 `AGENTS.md`；已读取 `CONTRIBUTING.md`。所有 PR 都在本 fork，不向官方仓库提 PR 或发消息。

## 固定依赖与安全

`dependencies.json` 固定 libtailscale `d1dc45d039edb7759ecbee6ba2aea0c4bca884b8`、Go `1.27.1` 及上游基线。该提交的 Swift 源码是 API 的依据：`tailscaleSession` 返回配置与 loopback 信息的元组；使用 `kDefaultControlURL`。README 的早期示例与当前 API 有差异，不照抄示例。

`mobile/pubspec.lock` 及官方 mise 锁文件继续生效。两个业务插件适配补丁在 `flutter pub get --enforce-lockfile` 后统一应用；脚本验证下载器版本 `9.5.6`、视频依赖提交 `cdf621bdb7edaf996e118a58a48f6441187d79c6` 和补丁上下文。版本或上下文变化会使 CI 失败，必须人工复核，不自动猜测新 API。

节点使用交互式网页授权，`authKey` 永远为 nil。没有共用密钥、Apple ID、证书或 Profile 入库。身份只放在本 App 私有的 Application Support/ImmichTailnet，目录权限 0700，启用 iOS Data Protection（首次解锁后可访问），排除设备备份；不放共享 App Group。SDK 另有一个隔离的日志补丁：logfd=-1 时同时关闭 UserLogf，防止授权 URL 仍进入控制台。Go 和 Swift 的本机运行日志静默，loopback 密码不跨 Flutter、不写日志。

关闭入口保留身份；“退出并清除节点身份”尝试 LocalAPI logout 后关闭节点、清除私有目录。若设备离线导致服务端注销未完成，仍需在 Tailscale 管理后台删除遗留设备。重连复用同一目录。网络切换优先由 SDK 自身处理；原生路径监听只检查本机代理是否仍可用，确实失效才重建，避免每次切换都取消所有请求。节点状态表示 tailnet 节点状态，不等于家中服务端已可达；恢复期间可能短暂失败，不对未知结果的 POST 盲目重放。当前固定 SDK 的 `down()` 源码行为不符合其注释，因此本模块不用它，使用 `close()` 重建。

节点启动或重连期间采用拒绝连接的本机代理配置，避免悄悄切回直连。视频转发器仅监听 127.0.0.1，路径需要进程随机令牌。无新的 VPN、定位、音频或其它后台权限；已有 Immich 权限不是 Tailscale 的新增需求。

## 使用与后台限制

登录/API 的目标是 App 内密码登录；系统浏览器的 OAuth 流程不能继承进程内隧道，如果 OAuth 回跳必须访问私有 Immich 地址，当前未接入此路径，不能声称支持。外部投屏设备同样不会继承此隧道。

在登录页或设置的网络页面开启内嵌 Tailscale，点击“请求授权”，再打开授权网页。返回 Immich 后，节点状态应变为 Running。服务器地址仍填写家中的 tailnet HTTP/HTTPS 地址；ACL 必须允许这个 App 节点访问 Immich 端口。不要填写 Funnel 公网地址，也不需要另装 Tailscale App。

| 情况 | 行为 |
| --- | --- |
| 前台 API、图片、原图、分享、上传、实时事件 | 统一经过配置后的原生会话 |
| 视频播放及拖动 | 官方视频转发器转给相同会话，保留 Range/206/Content-Range |
| 普通连接模式 | 保留官方直连及系统后台下载器配置 |
| Tailscale 模式的文件下载 | 下载器使用进程内 default URLSession，不伪装成可长期存活的后台隧道 |
| 离开 App 时的前台备份 | 保留官方取消/恢复逻辑；返回后按原备份设置重新检查候选项 |
| 已开始的文件传输 | 仅申请有限 UIKit background task；预算由 iOS 决定，过期取消，不能保证完成 |
| 无人值守后台自动备份 | 明确暂停，备份页和设置显示状态；不提交依赖本进程代理的长期系统任务 |
| 系统短暂唤醒 App | 原有有限后台元数据工作可能有执行机会；不能承诺唤醒时机或传输成功 |
| App 被杀、系统挂起、桌面小组件/分享扩展独立进程 | 不能依赖此隧道；重新打开 App 或改用普通可达地址 |

Apple 的后台 URLSession 会在系统进程执行；App 内代理没有同等生命周期。这个限制无法在“无系统 VPN”条件下变成永久后台隧道。不会用音频、定位、无限循环或虚假 VPN 绕过。普通模式的系统后台能力不因此被关掉。

## 全云端构建与验证

开发目录、Flutter/Go/Java 依赖和临时测试只存在于云容器或 GitHub 托管机。工作不访问用户 Mac，不访问用户 Mac 的项目目录，不在 Mac 克隆源码或安装 SDK。

Actions 的 `Tailnet iOS` 使用标准 `xcode-27` Arm64 托管 runner，固定选择 Xcode 27.1，不用 `-large`/`-xlarge` 付费机型。该镜像目前是公开预览；镜像缺失或工具链变动会使构建失败并阻止提升。

构建顺序：

1. 从固定提交编译 TailscaleKit 的设备与模拟器 framework。
2. 复用官方 mise 版本、锁文件、OpenAPI 和 Dart/Pigeon/Drift/翻译生成流程。
3. 应用两个固定依赖的原生适配补丁，再解析 Pods/SPM。
4. Dart 分析、控制桥与后台策略回归测试。
5. 创建临时控制面、DERP/STUN 和假 Immich 服务，在 iOS 模拟器测试协议；不连接真实用户 tailnet。
6. 编译完整模拟器 App，再编译无签名设备 App。
7. 打包明确标记 UNSIGNED 的 IPA、模拟器压缩包、构建元数据及 SHA256SUMS。

`tests/TransportTests.swift` 测试 HTTP/HTTPS、Cookie 登录、图片字节、multipart 文件上传、WS/WSS、重定向、Range 206/416、视频转发、取消和同目录身份恢复。测试用自签证书仅在测试中作为固定信任锚，生产代码没有关闭 HTTPS 验证。协议模拟器测试不等于真机验收，也不等于对家中服务端的验收。

框架缓存按依赖清单、架构和 Xcode 版本区分，不缓存节点身份或签名材料。日志/xcresult 留存 7 天，临时 App 制品留存 14 天；完整成功的稳定更新可保存到本 fork 的 Release 作为恢复点，失败更新不删除上一份成功 Release。定期人工清理不再需要的历史 Release；GitHub 会按自身策略回收缓存。

## 版本跟进与恢复

**实际权限情况（已实跑）**：运行 [40261139589](https://github.com/chinghoi/immich/actions/runs/40261139589) 被 GitHub 拒绝同步 workflow 文件，原因是默认 GITHUB_TOKEN 缺少 workflows 写权限；一次性权限探测也返回 403。不能把这次配置描述成 GitHub 原生自动合入已经成功。

当前采用两条明确通道：GitHub cron 只读发现并输出状态，构建仍由 GitHub Actions 完成；另已创建并启用每 6 小时执行的 ChatGPT 维护任务，用用户已授权且本次实际成功写入的 GitHub 插件维护镜像、候选分支、PR 和验证后的精确提交。维护任务已实际执行检查和构建修复，后续是否完成合入以 PR 和对应提交的完整 Actions 为准；连接失效、任务暂停或 CI 失败都必须显示阻断，不承诺永久无人值守。

若希望维护完全独立于 ChatGPT，可在仓库 Actions Secrets 配置 `TAILNET_SYNC_TOKEN`：使用只允许 chinghoi/immich 的限时 fine-grained token，授予 Contents、Workflows、Pull requests、Actions 的读写权限。工作流已有此可选接入；不在源码、聊天、制品或日志中存密钥，也不会擅自创建凭据。未配置时只读发现，不反复尝试被拒绝的写入。

默认 main 只附加维护入口，原历史有归档分支。`upstream/main` 是发现用镜像；面向使用者的版本来自官方稳定 Release，定制开发在 `ios/tailscale`，验证后的稳定线为 `ios/stable`。不把官方 main 的每次提交直接发给手机。

`Tailnet upstream maintenance` 每 6 小时检查一次，避开整点，实际计划为 UTC 00:17/06:17/12:17/18:17（北京时间 08:17/14:17/20:17/次日02:17）。GitHub 可能排队、延迟甚至丢弃定时运行，不能承诺实时或严格 6 小时内。

由维护任务（或配置了专用 Secret 后的 GitHub 工作流）为新稳定版创建独立 `sync/tailnet-vX.Y.Z` 候选分支，通过普通 merge 保留补丁并创建本 fork PR。GITHUB_TOKEN 创建的 push/PR 不会递归触发构建，因此同步脚本显式 dispatch。维护任务或具备权限的成功回调再次核对仓库、分支、提交、必需步骤、PR 头，再只把**实际测试过的提交**快进到目标分支。不能快进就暂停；不强推，也不把未经测试的新组合强行合入。初始开发 PR 尚未合入稳定线时，发现任务只检查开发基线。

冲突时先 abort merge，然后创建带 `update-blocked.json` 的 draft PR；不改稳定线。构建失败则保留候选 PR、失败运行和上一份稳定制品。既有候选分支不会被下一次 cron 强制覆盖。恢复步骤：在云端从候选分支处理冲突，合入目标稳定 tag，复核依赖补丁，更新清单，推送并重跑 `Tailnet iOS`；全通过后才提升。要回滚使用历史成功 Release 与其提交；不要重置或强推现有补丁线。

公开 fork 的 scheduled workflows 默认可能未启用；公开仓库 60 天无活动也可能自动停用。维护者每月检查 Actions 的最近成功时间，若停用则在 Actions 启用 `Tailnet upstream maintenance` 并手动 Run workflow。正常代码提交不会保证已停用的 cron 自动复活，不用空提交伪造活动。Actions 的“允许创建 PR”仓库设置若禁用，候选创建会失败并在运行中显示，需要仓库管理员开启相应权限；不在源码内存 PAT 绕过。

## 本机签名与安装

GitHub Actions 只生成 unsigned 设备 IPA 和模拟器包；模拟器包不能安装到 iPhone。证书私钥、P12、密码及设备描述文件不上传 GitHub、不进入 Actions Secrets 或构建制品。签名使用 Mac 钥匙串中的既有身份，最终设备 IPA 才下载到 Mac 处理。

本定制版沿用 `com.test.immich`、`com.test.immich.ShareExtension`、`com.test.immich.Widget` 与 `group.com.test.immich`。签名前同时验证主 App、两个扩展、App Group、Profile 的证书/设备/有效期及 entitlement；框架、扩展和主 App 分别签名，最后验证深层严格签名、IPA 内容及哈希。升级沿用同一组标识和可用材料；不因增加内嵌网络模块而创建系统 VPN 扩展或申请新的网络扩展权限。

安装页仅在每次获准的临时分发期间开放，使用新的随机路径和 HTTPS 链接；用户确认安装后关闭隧道。旧 Quick Tunnel 地址不可当作永久下载地址。签名有效期取决于实际证书和 Profile；重新签同一份 Profile 不会延长其原有到期日。真机安装、网络授权、SDK 挂起恢复和蜂窝网络吞吐仍须在设备上验证。

## 服务端兼容与真机验收

优先安装与家中服务端相同稳定版本的 App。当前基线是 v3.3.5；发布前应核对实际服务端版本，服务端升级独立评估。官方 `getVersionCompatibilityMessage` 的主版本粗检查仍保留，但通过该检查不代表每个跨版本功能都兼容，升级前还要查看上游 Release notes。此仓库和 Actions 从不升级家中服务端。

最终验收还需要用户安装后：完成真实网页授权；验证 tailnet ACL；分别在 Wi-Fi/蜂窝网络登录、浏览缩略图/原图、拖动长视频、上传和下载；切换网络、锁屏、离开 App、杀进程再打开；确认节点身份不重复、后台状态清楚，取消/失败后数据不误标成功。iOS 真机的挂起、锁屏和系统任务预算无法靠模拟器证明。

验证记录以 Actions 和 `VERIFICATION.md` 为准；没有实际成功运行的项必须写“未验证”。

## 一手参考

- [libtailscale 固定提交](https://github.com/tailscale/libtailscale/tree/d1dc45d039edb7759ecbee6ba2aea0c4bca884b8)
- [Apple 后台 URLSession](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background)
- [Apple 普通账号与 Personal Team 限制](https://developer.apple.com/help/account/basics/about-your-developer-account)
- [SideStore 官方 FAQ](https://docs.sidestore.io/docs/faq)
- [GitHub schedule 限制](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule)
- [GitHub runner 镜像与标准标签](https://github.com/actions/runner-images)

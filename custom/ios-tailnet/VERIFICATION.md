# 验证记录

日期：2026-10-27。所有开发与验证均在云端完成。

## 当前候选验证：2748a8e

[Tailnet iOS #11](https://github.com/chinghoi/immich/actions/runs/40445647135) 在标准 GitHub 托管 macOS runner（`xcode-27`）上，对完整 SHA `2748a8e976586d8f081b724ca2b6791bf7cb9a4a` 全部通过。

| 项目 | 实际状态 |
| --- | --- |
| 云端工具链、依赖安装、官方代码生成 | #11 通过 |
| Dart 分析与传输/回归测试 | #11 通过；7 项桥接及后台策略回归通过 |
| 临时 tailnet 的 iOS 模拟器协议集成 | #11 通过；使用一次性 tailnet 夹具 |
| iOS 模拟器 App（不签名） | #11 通过 |
| iOS 设备 Release App（不签名） | #11 通过；约 26 分 23 秒 |
| IPA、模拟器包和验证产物上传 | #11 通过 |
| 真正的 Tailscale 账号授权及 iPhone 安装 | 未验证；设备包没有 Apple 签名 |
| 真机锁屏、系统挂起、Wi-Fi/蜂窝切换与后台上传 | 未验证；模拟器结果不能代替真机 |
| TestFlight 或 App Store 发布 | 未进行 |
| `ios/stable` | 未改动，未提升 |

该运行保存了以下 Actions 产物，可从运行页下载：

- `tailnet-ios-unsigned-2748a8e976586d8f081b724ca2b6791bf7cb9a4a`：未签名 IPA 与模拟器验证包，保留至 2026-11-10。
- `tailnet-simulator-tests-2748a8e976586d8f081b724ca2b6791bf7cb9a4a`：模拟器测试结果，保留至 2026-11-03。
- `tailnet-build-logs-2748a8e976586d8f081b724ca2b6791bf7cb9a4a`：构建日志，保留至 2026-11-03。

## 故障修复记录

前一轮 [40290137262](https://github.com/chinghoi/immich/actions/runs/40290137262) 的唯一失败，是一次性 tailnet 启动后首个 SOCKS5 请求超时（`NSURLErrorDomain -1000`）。候选提交 `2748a8e` 在登录请求前，通过同一个 Tailscale SOCKS5 会话轮询 fixture 的 `/api/ready`：每次请求有短超时，整体最多等待 30 秒，并在失败时保留最后的传输错误；原有协议断言没有删减。该集成测试已在 #11 对相同的一次性 fixture 通过。这验证了 CI 中的协议路径，不代表真实账号或 iPhone 上的连接验证。

## 2026-10-26 维护修复

[运行 40264827974](https://github.com/chinghoi/immich/actions/runs/40264827974) 发现 `patch --batch --reverse --dry-run` 会自动猜测相反方向，导致尚未应用的补丁被误判。维护脚本改用方向明确的 `git apply --check` / `--reverse --check`，检查下载器公开接口，并在完整构建前复核。libtailscale 日志补丁采用相同判断；框架缓存键加入构建脚本，废弃旧缓存。

云端容器使用实际发布的 background_downloader 9.5.6 包验证：干净依赖不会被误判为已打补丁、首次应用成功、已应用补丁能反向检查、重复应用会被拒绝，且公开接口存在。该专项验证与 #11 的完整 macOS 工作流相互补充。

## 后续维护边界

依赖保持固定版本，第三方改动通过可审计补丁维护。每个候选都应在准确提交上跑完文档所列检查；失败则暂停提升。GitHub Actions 已恢复，本次托管 macOS 工作流可运行。当前通过只覆盖提交 `2748a8e` 及 CI 夹具；真机签名、安装和后台行为仍需在可签名设备上验证后才能确认。
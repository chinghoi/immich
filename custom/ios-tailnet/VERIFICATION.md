# 验证记录

日期：2026-10-27。所有开发与验证均在云端。

| 项目 | 实际状态 |
| --- | --- |
| 正式 fork、上游关系与 GitHub 写入 | 已验证；chinghoi/immich，parent=immich-app/immich |
| 原 main 保护 | 已建立 archive/main-before-tailnet-20261026；定制在独立分支 |
| 标准 macOS runner 启动 | 已通过 [40258032335](https://github.com/chinghoi/immich/actions/runs/40258032335) |
| 固定 TailscaleKit 设备及模拟器 framework | [40290137262](https://github.com/chinghoi/immich/actions/runs/40290137262) 通过 |
| 依赖安装与官方代码生成 | 已在运行 [40259687707](https://github.com/chinghoi/immich/actions/runs/40259687707) 通过 |
| Dart 分析 | 40290137262 通过 |
| 控制桥与后台策略测试 | 40290137262 的 macOS 7 项测试通过 |
| 临时 tailnet 的 iOS 模拟器协议测试 | 40290137262 失败：启动后首次 SOCKS 请求超时（NSURLError -1000）；新候选加入真实路由可达性等待，待重跑验证 |
| 完整模拟器 App / 无签名设备 App | 40290137262 两者构建通过；集成测试失败，因此候选尚未验证通过 |
| 真实 tailnet、iPhone、普通 Apple ID 重签安装 | 未验证，尚无用户设备/安装渠道 |
| 真机锁屏、系统挂起、Wi-Fi/蜂窝切换 | 未验证；模拟器不能替代 |
| 自动上游发现、PR 与提升 | 默认 GITHUB_TOKEN 实跑因 workflows 权限被拒；已改为只读发现，运行 40261916066 已通过。插件维护已于 2026-10-26 实际检查并修复失败；原生全自动提升未验证 |

该表会按实际最终运行更新；单独的环境探测或 framework 通过不代表完整 App 通过。

## 2026-10-26 维护修复

[运行 40264827974](https://github.com/chinghoi/immich/actions/runs/40264827974) 的失败原因是 `patch --batch --reverse --dry-run` 可自动猜测相反方向，导致未应用的补丁被判为已应用。改用不猜测方向的 `git apply --check` / `--reverse --check`，检查下载器公开接口，并在两种完整构建前再次核验。libtailscale 日志补丁也修正同一判定；框架缓存键加入构建脚本以废弃旧缓存。

云容器已用真实 background_downloader 9.5.6 发布包验证：干净依赖不能被判成已应用、首次应用成功、已应用依赖反向检查成功、重复应用被拒绝、公开接口实际存在。此验证不等于新的 macOS 完整构建成功。官方稳定版仍为 v3.3.5，没有新版本合并；ios/stable 保持原基线。真实设备、安装与后台挂起验证仍未完成。


## 2026-10-27 模拟器 tailnet 就绪门槛

运行 [40290137262](https://github.com/chinghoi/immich/actions/runs/40290137262) 中，除临时 tailnet 协议集成外的分析、7 项桥接/后台策略测试、framework、模拟器 App 和无签名设备 App 均通过。唯一失败发生在首个 `http://100.64.0.1:2283/api/auth/login` 请求：SOCKS5 连接超时并被 URLSession 报为 -1000。前一轮在相同 `authKey:nil` 测试夹具下通过，日志也显示节点起步时仍处于 NeedsLogin，支持启动就绪竞态这一解释。

新候选在登录请求前轮询 fixture 的 `/api/ready`，通过同一 Tailscale SOCKS5 会话验证目标确实可达；每次请求有短超时，整体等待最多 30 秒，超时保留具体错误。服务端 fixture 为该探针返回 204。没有删减已有协议断言。该候选仍待托管 macOS CI 重跑；此记录不把修复当作验证通过。

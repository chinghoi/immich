# 验证记录

日期：2026-10-26。所有开发与验证均在云端。

| 项目 | 实际状态 |
| --- | --- |
| 正式 fork、上游关系与 GitHub 写入 | 已验证；chinghoi/immich，parent=immich-app/immich |
| 原 main 保护 | 已建立 archive/main-before-tailnet-20261026；定制在独立分支 |
| 标准 macOS runner 启动 | 已通过 [40258032335](https://github.com/chinghoi/immich/actions/runs/40258032335) |
| 固定 TailscaleKit 设备及模拟器 framework | 40264827974 已编译通过；本次修复日志补丁判定后需重新编译验证 |
| 依赖安装与官方代码生成 | 已在运行 [40259687707](https://github.com/chinghoi/immich/actions/runs/40259687707) 通过 |
| Dart 分析 | 40264827974 的 macOS 分析已通过 |
| 控制桥与后台策略测试 | 40264827974 的 macOS 7 项测试已通过 |
| 临时 tailnet 的 iOS 模拟器协议测试 | 40264827974 两项套件通过，包括真实 MP4 的 AVPlayer 播放、拖动与 Range；严格补丁修复后仍须重跑 |
| 完整模拟器 App / 无签名设备 App | 40264827974 两者均失败：下载器 configurationFactory/resetSession 未进入编译；未提升稳定线 |
| 真实 tailnet、iPhone、普通 Apple ID 重签安装 | 未验证，尚无用户设备/安装渠道 |
| 真机锁屏、系统挂起、Wi-Fi/蜂窝切换 | 未验证；模拟器不能替代 |
| 自动上游发现、PR 与提升 | 默认 GITHUB_TOKEN 实跑因 workflows 权限被拒；已改为只读发现，运行 40261916066 已通过。插件维护已于 2026-10-26 实际检查并修复失败；原生全自动提升未验证 |

该表会按实际最终运行更新；单独的环境探测或 framework 通过不代表完整 App 通过。

## 2026-10-26 维护修复

[运行 40264827974](https://github.com/chinghoi/immich/actions/runs/40264827974) 的失败原因是 `patch --batch --reverse --dry-run` 可自动猜测相反方向，导致未应用的补丁被判为已应用。改用不猜测方向的 `git apply --check` / `--reverse --check`，检查下载器公开接口，并在两种完整构建前再次核验。libtailscale 日志补丁也修正同一判定；框架缓存键加入构建脚本以废弃旧缓存。

云容器已用真实 background_downloader 9.5.6 发布包验证：干净依赖不能被判成已应用、首次应用成功、已应用依赖反向检查成功、重复应用被拒绝、公开接口实际存在。此验证不等于新的 macOS 完整构建成功。官方稳定版仍为 v3.3.5，没有新版本合并；ios/stable 保持原基线。真实设备、安装与后台挂起验证仍未完成。

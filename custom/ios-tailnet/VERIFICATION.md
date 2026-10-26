# 验证记录

日期：2026-10-26。所有开发与验证均在云端。

| 项目 | 实际状态 |
| --- | --- |
| 正式 fork、上游关系与 GitHub 写入 | 已验证；chinghoi/immich，parent=immich-app/immich |
| 原 main 保护 | 已建立 archive/main-before-tailnet-20261026；定制在独立分支 |
| 标准 macOS runner 启动 | 已通过 [40258032335](https://github.com/chinghoi/immich/actions/runs/40258032335) |
| 固定 TailscaleKit 设备及模拟器 framework | 已在早期云端运行通过；后续完整运行仍需检查 |
| 依赖安装与官方代码生成 | 已在运行 [40259687707](https://github.com/chinghoi/immich/actions/runs/40259687707) 通过 |
| Dart 分析 | 云端 Linux 修复后通过：No issues found；完整 macOS CI 待最终运行 |
| 控制桥与后台策略测试 | 云端 Linux 5 项通过；完整 macOS CI 待最终运行 |
| 临时 tailnet 的 iOS 模拟器协议测试 | 代码已加入，未记为通过 |
| 完整模拟器 App / 无签名设备 App | 尚未通过，不可宣称已可安装 |
| 真实 tailnet、iPhone、普通 Apple ID 重签安装 | 未验证，尚无用户设备/安装渠道 |
| 真机锁屏、系统挂起、Wi-Fi/蜂窝切换 | 未验证；模拟器不能替代 |
| 自动上游发现、PR 与提升 | 配置开发中，成功运行前不记为启用/通过 |

该表会按实际最终运行更新；单独的环境探测或 framework 通过不代表完整 App 通过。

# iOS 无签名制品与签名配置核对

核对日期：2026-10-27。开发、下载、解包与校验均在云容器完成，未访问用户 Mac。此文记录已验证制品，不注册 Apple 标识、不创建证书、不执行签名。

## 当前签名边界

用户明确要求：**Apple 签名证书及私钥绝不进入 GitHub Actions，包括 Actions Secrets、日志、缓存或制品。** Actions 只编译和交付无签名包；签名由用户控制的独立签名环境处理。不要把 Apple ID 密码、验证码、P12、P8、证书私钥或签名密码发到聊天或仓库。

此要求取代定制分支 README 中曾提到的“未来可向 CI Secrets 提供 P12 并新增签名 job”的旧设想。该设想不再适用。现有 Tailnet iOS workflow 没有签名 job，设备和模拟器构建均使用 `--no-codesign`。

## 已验证的交付物

- 应用源码提交：[8dab6092f19ac516f39190515e35c7adce0c4412](https://github.com/chinghoi/immich/commit/8dab6092f19ac516f39190515e35c7adce0c4412)。
- [Tailnet iOS #12 / 40451748332](https://github.com/chinghoi/immich/actions/runs/40451748332)：分析、7 项 Dart 回归、临时 tailnet 的 iOS 模拟器协议测试、完整模拟器构建、无签名设备 Release 构建、打包及上传全部通过。
- [unsigned artifact](https://github.com/chinghoi/immich/actions/runs/40451748332/artifacts/12711374257)：`tailnet-ios-unsigned-8dab6092f19ac516f39190515e35c7adce0c4412`，保留至 2026-11-10 13:29（北京时间）。
- 文件：`Immich-Tailnet-UNSIGNED.ipa`、`Immich-Tailnet-SIMULATOR.zip`、`build-metadata.json`、`SHA256SUMS`。
- IPA SHA256：`9219e9090cef545e8c298b31b5eb82be252f6dc99aef83ee14a605b453076aed`。

在云端逐项验证 SHA256SUMS，并打开 IPA 内的真实 Info.plist 和 Mach-O：主 App 及两项扩展均无 LC_CODE_SIGNATURE，也无 embedded.mobileprovision；因此没有可直接安装的设备签名或已获授权的签名 entitlement。下表“能力”来自同一源码提交的 entitlement 模板，不能把模板当成已签名能力。

## Release IPA 的实际标识

| 目标 | IPA 中的 CFBundleIdentifier | 源码声明的能力 |
| --- | --- | --- |
| 主 App / Runner | `app.alextran.immich` | App Groups、Associated Domains、Access WiFi Information |
| Share Extension | `app.alextran.immich.ShareExtension` | App Groups |
| Widget Extension | `app.alextran.immich.Widget` | App Groups |

三者 Info.plist 的 `AppGroupId` 都是 `group.app.immich.share`；对应 entitlement 键为 `com.apple.security.application-groups`。主 App 另声明 `com.apple.developer.associated-domains = [applinks:my.immich.app]`、`com.apple.developer.networking.wifi-info = true`。

最低 iOS 版本均为 18.1。Release entitlement 没有 `aps-environment`；只有 Profile 配置的 RunnerProfile.entitlements 声明 development push。不要因此给当前 Release 的三个 App ID 全部开启 Push。Tailscale 模块不要求 Personal VPN、Network Extension 或 Packet Tunnel 能力。

## 重新配置公司团队时需要匹配的项目

这些是上游默认标识，不是已经为公司注册好的专用标识。仓库 Signing.xcconfig 中的 `2W7AC6T8T5` 也属于上游默认值，不能当成用户公司 Team ID。此次没有访问 Apple 团队页面，无法核实用户刚删除的旧 App ID/Group 名称或可否重新注册。

若经公司授权使用其团队，应选择该团队可注册的独立标识，并保持三个显式 App ID、一个共享 Group 与三份目标 Profile 一致。可采用以下独立命名作为待注册配置；它们不是当前 IPA 的实际值，也未声称已可注册：

```
IMMICH_TEAM_ID = <实际获授权的公司 Team ID>
IMMICH_BUNDLE_ID_PROD = io.github.chinghoi.immich.tailnet
IMMICH_BUNDLE_ID_DEV = io.github.chinghoi.immich.tailnet.dev
IMMICH_GROUP_ID = group.io.github.chinghoi.immich.tailnet
```

对应 Release 主 App、Share、Widget 的完整 App ID 分别为 `io.github.chinghoi.immich.tailnet`、`io.github.chinghoi.immich.tailnet.ShareExtension`、`io.github.chinghoi.immich.tailnet.Widget`；三个目标关联同一 `group.io.github.chinghoi.immich.tailnet`。保留现有 Release entitlement 时，主 App 的 Profile 还须允许 Associated Domains 与 Access WiFi Information；扩展无需额外开启这两项。

重新注册/关联后，为三个目标分别重新生成与实际设备、签名证书和能力匹配的 Profile。不能只改主 App Bundle ID：扩展 Bundle ID、三者 Info.plist 的 AppGroupId、签名 entitlement、Profile 必须同步匹配；嵌入 framework/扩展也要在独立环境正确重签。不要复用已删除标识对应的旧 Profile，也不要用上游 Team ID 或未经授权的公司签名身份。现有 `Signing.local.xcconfig` 接口允许未来云端构建注入公开标识，不需要向 Actions 提供任何证书或私钥。

普通 Apple ID 并不自动获得公司团队的签名能力。此次没有验证普通 Apple ID 的重签安装、公司 Profile、真实 tailnet 授权、真机网络切换、锁屏、挂起或后台上传；也没有 TestFlight、App Store 发布或家庭服务端升级。`ios/stable` 保持未提升。

参考：

- [Apple 注册 App Group](https://developer.apple.com/help/account/identifiers/register-an-app-group)
- [Apple 启用能力](https://developer.apple.com/help/account/identifiers/enable-app-capabilities)
- [Apple 创建开发 Profile](https://developer.apple.com/help/account/provisioning-profiles/create-a-development-provisioning-profile/)

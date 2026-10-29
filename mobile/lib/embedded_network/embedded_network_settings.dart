import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:immich_mobile/embedded_network/embedded_network_session.dart';
import 'package:immich_mobile/infrastructure/repositories/network.repository.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:immich_ui/immich_ui.dart';

class EmbeddedNetworkSettings extends StatefulWidget {
  const EmbeddedNetworkSettings({super.key});
  @override
  State<EmbeddedNetworkSettings> createState() => _EmbeddedNetworkSettingsState();
}

class _EmbeddedNetworkSettingsState extends State<EmbeddedNetworkSettings> {
  Map<String, dynamic> _status = const {'mode': 'none', 'state': 'Loading'};
  final _name = TextEditingController();
  final _secret = TextEditingController();
  final _peer = TextEditingController();
  final _ip = TextEditingController();
  Timer? _timer;
  bool _tcpOnly = true;
  bool _allowP2P = true;
  bool _hasSecret = false;
  bool _busy = false;
  bool _refreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      unawaited(_load());
      _timer = Timer.periodic(const Duration(seconds: 3), (_) => unawaited(_refresh()));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final controller in [_name, _secret, _peer, _ip]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final fields = await EmbeddedNetworkSession.configuration();
      if (!mounted) {
        return;
      }
      _name.text = fields['networkName'] as String? ?? '';
      _peer.text = fields['peer'] as String? ?? '';
      _ip.text = fields['ipv4'] as String? ?? '';
      setState(() {
        _hasSecret = fields['hasSecret'] == true;
        _tcpOnly = fields['tcpOnly'] != false;
        _allowP2P = fields['allowP2P'] != false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = '无法读取 EasyTier 配置，请解锁手机后重试。');
      }
    }
    await _refresh();
  }

  Future<void> _refresh() async {
    if (_refreshing) {
      return;
    }
    _refreshing = true;
    try {
      final status = await EmbeddedNetworkSession.status();
      if (mounted) {
        setState(() => _status = status);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = '无法读取网络状态，请重连后重试。');
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
      await NetworkRepository.init();
    } catch (_) {
      if (mounted) {
        setState(() => _error = '请检查当前通道的节点配置或授权后重试。');
      }
    } finally {
      await _refresh();
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _save() async {
    await EmbeddedNetworkSession.saveConfiguration({
      'networkName': _name.text.trim(),
      'networkSecret': _secret.text,
      'peer': _peer.text.trim(),
      'ipv4': _ip.text.trim(),
      'tcpOnly': _tcpOnly,
      'allowP2P': _allowP2P,
    });
    _secret.clear();
    if (mounted) {
      setState(() => _hasSecret = true);
    }
  }


  Future<T?> _choose<T>(String title, T selected, Map<T, String> choices) {
    FocusScope.of(context).unfocus();
    return showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SettingGroupTitle(title: title),
              for (final entry in choices.entries)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                  title: Text(entry.value),
                  trailing: entry.key == selected
                      ? Icon(Icons.check_rounded, color: Theme.of(context).colorScheme.primary)
                      : null,
                  onTap: () => Navigator.pop(sheetContext, entry.key),
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.iOS) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final mode = EmbeddedNetworkMode.values.firstWhere(
      (mode) => mode.name == _status['mode'],
      orElse: () => EmbeddedNetworkMode.none,
    );
    const modes = {
      EmbeddedNetworkMode.none: '普通连接',
      EmbeddedNetworkMode.tailscale: 'Tailscale',
      EmbeddedNetworkMode.easytier: 'EasyTier',
    };
    const strategies = {
      'tcp': 'TCP 直连优先（推荐）',
      'auto': '自动（允许 UDP）',
      'relay': '仅 TCP 中继',
    };
    final strategy = !_allowP2P ? 'relay' : _tcpOnly ? 'tcp' : 'auto';
    final state = switch (_status['state']) {
      'Running' => _status['connected'] == false ? '等待节点连接' : '已启动',
      'NeedsLogin' => '等待授权',
      'NeedsMachineAuth' => '等待管理员批准',
      'NeedsConfiguration' => '尚未配置',
      'Disabled' => '使用系统网络',
      'Unavailable' => '连接不可用',
      _ => '正在连接',
    };
    final authURL = Uri.tryParse(_status['authURL'] as String? ?? '');
    final canAuthorize = authURL != null && authURL.scheme == 'https' &&
        (authURL.host == 'login.tailscale.com' || authURL.host.endsWith('.tailscale.com'));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SettingGroupTitle(title: 'App 网络', icon: Icons.hub_outlined),
          SettingListTile(
            title: '连接方式',
            subtitle: modes[mode],
            leading: const Icon(Icons.route_outlined),
            trailing: const Icon(Icons.chevron_right_rounded),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            onTap: _busy ? null : () async {
              final selected = await _choose('连接方式', mode, modes);
              if (selected != null && selected != mode && mounted) {
                await _run(() => EmbeddedNetworkSession.select(selected));
              }
            },
          ),
          SettingListTile(
            title: '网络状态',
            subtitle: state,
            leading: const Icon(Icons.info_outline_rounded),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          ),
          if (mode == EmbeddedNetworkMode.easytier) ...[
            ExpansionTile(
              key: ValueKey('configuration-$_hasSecret'),
              initiallyExpanded: !_hasSecret,
              tilePadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: const Icon(Icons.settings_ethernet_rounded),
              title: const Text('连接配置'),
              subtitle: Text(_peer.text.isEmpty ? '设置网络名称、密钥和连接节点' : _peer.text),
              childrenPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              children: [
            SettingListTile(
              title: '连接策略',
              subtitle: strategies[strategy],
              leading: const Icon(Icons.alt_route_rounded),
              trailing: const Icon(Icons.chevron_right_rounded),
              contentPadding: EdgeInsets.zero,
              onTap: _busy ? null : () async {
                final selected = await _choose('连接策略', strategy, strategies);
                if (selected != null && mounted) {
                  setState(() {
                    _allowP2P = selected != 'relay';
                    _tcpOnly = selected != 'auto';
                  });
                }
              },
            ),
                const SizedBox(height: 12),
                ImmichTextInput(
                  controller: _name, enabled: !_busy, autocorrect: false,
                  label: '网络名称', keyboardAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                ImmichTextInput(
                  controller: _secret, enabled: !_busy, obscureText: true, autocorrect: false,
                  label: '网络密钥', keyboardAction: TextInputAction.next,
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_hasSecret ? '已安全保存；留空沿用原密钥' : '仅保存在这台手机的钥匙串',
                    style: theme.textTheme.bodySmall),
                ),
                const SizedBox(height: 16),
                ImmichTextInput(
                  controller: _peer, enabled: !_busy, autocorrect: false,
                  label: '连接节点', hintText: 'tcp://服务器地址:11010',
                  keyboardType: TextInputType.url, keyboardAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                ImmichTextInput(
                  controller: _ip, enabled: !_busy, autocorrect: false,
                  label: '手机虚拟 IPv4', hintText: '10.77.23.2',
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  keyboardAction: TextInputAction.done,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('embedded-network-connect'),
                  onPressed: _busy ? null : () {
                    FocusScope.of(context).unfocus();
                    unawaited(_run(_save));
                  },
                  child: Text(_hasSecret ? '连接' : '保存并连接'),
                ),
              ),
            ),
          ],
          if (mode == EmbeddedNetworkMode.tailscale)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(spacing: 8, children: [
                TextButton(onPressed: _busy ? null : () => unawaited(_run(() => EmbeddedNetworkSession.action('login'))),
                  child: const Text('请求授权')),
                if (canAuthorize)
                  TextButton(onPressed: () => unawaited(launchUrl(authURL, mode: LaunchMode.externalApplication)),
                    child: const Text('打开授权网页')),
              ]),
            ),
          if (mode != EmbeddedNetworkMode.none) ...[
            if (mode == EmbeddedNetworkMode.tailscale)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextButton.icon(
                onPressed: _busy ? null : () => unawaited(_run(() => EmbeddedNetworkSession.action('reconnect'))),
                icon: const Icon(Icons.refresh_rounded), label: const Text('重连'),
              ),
            ),
            ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 20),
              title: const Text('更多'),
              childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              children: [
                const Text('内嵌网络需要 App 保持前台。后台备份和桌面组件使用普通网络。切换通道不会修改服务器地址。'),
                if (mode == EmbeddedNetworkMode.easytier) ...[
                  const SizedBox(height: 8),
                  const Text('手机和 Mac 使用相同网络名称与密钥、不同虚拟 IP。Immich 服务器地址填写 Mac 的虚拟 IP。'),
                  const SizedBox(height: 8),
                  Text(!_allowP2P ? '仅连接所填节点，不尝试打洞。'
                      : _tcpOnly ? '先通过节点接通，后台尝试 TCP 直连；失败继续中继。'
                      : '自动尝试 TCP/UDP 直连；失败继续中继。'),
                ],
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy ? null : () => unawaited(_run(() async {
                    await EmbeddedNetworkSession.action('logout');
                    _secret.clear();
                    await _load();
                  })),
                  child: Text('退出并清除当前通道身份', style: TextStyle(color: theme.colorScheme.error)),
                ),
              ],
            ),
          ],
          if (_busy)
            const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: LinearProgressIndicator()),
          if (_error != null)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: Icon(Icons.error_outline_rounded, color: theme.colorScheme.error),
              title: Text('操作未完成', style: TextStyle(color: theme.colorScheme.error)),
              subtitle: Text(_error!),
            ),
        ],
      ),
    );
  }
}

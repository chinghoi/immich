import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:immich_mobile/embedded_network/embedded_network_session.dart';
import 'package:immich_mobile/infrastructure/repositories/network.repository.dart';
import 'package:url_launcher/url_launcher.dart';

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
      if (!mounted) return;
      _name.text = fields['networkName'] as String? ?? '';
      _peer.text = fields['peer'] as String? ?? '';
      _ip.text = fields['ipv4'] as String? ?? '';
      setState(() {
        _hasSecret = fields['hasSecret'] == true;
        _tcpOnly = fields['tcpOnly'] != false;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取 EasyTier 配置，请解锁手机后重试。');
    }
    await _refresh();
  }
  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final status = await EmbeddedNetworkSession.status();
      if (mounted) setState(() => _status = status);
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取网络状态，请重连后重试。');
    } finally {
      _refreshing = false;
    }
  }
  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      await operation();
      await NetworkRepository.init();
    } catch (_) {
      if (mounted) setState(() => _error = '操作未完成。EasyTier 请检查配置、密钥和节点是否在线；Tailscale 请检查授权。');
    } finally {
      await _refresh();
      if (mounted) setState(() => _busy = false);
    }
  }
  Future<void> _save() async {
    await EmbeddedNetworkSession.saveConfiguration({
      'networkName': _name.text.trim(), 'networkSecret': _secret.text,
      'peer': _peer.text.trim(), 'ipv4': _ip.text.trim(), 'tcpOnly': _tcpOnly,
    });
    _secret.clear();
    if (mounted) setState(() => _hasSecret = true);
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.iOS) return const SizedBox.shrink();
    final mode = EmbeddedNetworkMode.values.firstWhere(
      (mode) => mode.name == _status['mode'], orElse: () => EmbeddedNetworkMode.none);
    final nodeState = switch (_status['state']) {
      'Running' => '核心已启动',
      'NeedsLogin' => '等待授权',
      'NeedsMachineAuth' => '等待管理员批准',
      'NeedsConfiguration' => '请填写配置',
      'Disabled' => '普通连接',
      'Unavailable' => '连接不可用',
      _ => '连接中',
    };
    final authURL = Uri.tryParse(_status['authURL'] as String? ?? '');
    final canAuthorize = authURL != null && authURL.scheme == 'https' &&
        (authURL.host == 'login.tailscale.com' || authURL.host.endsWith('.tailscale.com'));
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          DropdownButtonFormField<EmbeddedNetworkMode>(
            initialValue: mode,
            isExpanded: true,
            key: ValueKey(mode),
            decoration: const InputDecoration(labelText: 'App 网络通道'),
            items: const [
              DropdownMenuItem(value: EmbeddedNetworkMode.none, child: Text('普通连接')),
              DropdownMenuItem(value: EmbeddedNetworkMode.tailscale, child: Text('Tailscale')),
              DropdownMenuItem(value: EmbeddedNetworkMode.easytier, child: Text('EasyTier')),
            ],
            onChanged: _busy ? null : (mode) {
              if (mode != null) unawaited(_run(() => EmbeddedNetworkSession.select(mode)));
            },
          ),
          const SizedBox(height: 12),
          Text('状态：$nodeState'),
          const SizedBox(height: 8),
          const Text('三种模式互斥，不占用系统 VPN。切换不会自动修改 Immich 服务器地址；请使用所选网络能访问的服务器地址。'),
          if (mode != EmbeddedNetworkMode.none) ...[
            const SizedBox(height: 8),
            const Text('内嵌组网需要保持 App 在前台。离开 App 可能暂停；后台自动备份和桌面小组件不使用此通道。'),
          ],
          if (mode == EmbeddedNetworkMode.tailscale)
            Wrap(spacing: 8, children: [
              TextButton(onPressed: _busy ? null : () => unawaited(_run(() => EmbeddedNetworkSession.action('login'))),
                child: const Text('请求授权')),
              if (canAuthorize)
                TextButton(onPressed: () => unawaited(launchUrl(authURL, mode: LaunchMode.externalApplication)),
                  child: const Text('打开授权网页')),
            ]),
          if (mode == EmbeddedNetworkMode.easytier) ...[
            const SizedBox(height: 12),
            const Text('Mac 和手机须使用相同网络名称和密钥、不同虚拟 IP。服务器 URL 填 Mac 的 EasyTier 虚拟 IP。'),
            const SizedBox(height: 12),
            TextField(controller: _name, enabled: !_busy, autocorrect: false,
              decoration: const InputDecoration(labelText: 'EasyTier 网络名称')),
            const SizedBox(height: 12),
            TextField(controller: _secret, enabled: !_busy, obscureText: true, enableSuggestions: false, autocorrect: false,
              decoration: InputDecoration(labelText: '网络密钥', helperText: _hasSecret ? '已安全保存；留空沿用原密钥' : '仅保存在这台手机的钥匙串')),
            const SizedBox(height: 12),
            TextField(controller: _peer, enabled: !_busy, autocorrect: false, keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: '连接节点', hintText: 'tcp://服务器地址:11010')),
            const SizedBox(height: 12),
            TextField(controller: _ip, enabled: !_busy, autocorrect: false,
              decoration: const InputDecoration(labelText: '手机的 EasyTier 虚拟 IPv4', hintText: '10.77.23.2')),
            SwitchListTile(contentPadding: EdgeInsets.zero,
              title: const Text('仅使用 TCP'),
              subtitle: const Text('关闭 UDP 打洞，数据经所填 TCP 节点；节点须在线且允许转发。'),
              value: _tcpOnly, onChanged: _busy ? null : (value) => setState(() => _tcpOnly = value)),
            TextButton(onPressed: _busy ? null : () => unawaited(_run(_save)), child: const Text('保存并连接')),
          ],
          if (mode != EmbeddedNetworkMode.none)
            Wrap(spacing: 8, children: [
              TextButton(onPressed: _busy ? null : () => unawaited(_run(() => EmbeddedNetworkSession.action('reconnect'))),
                child: const Text('重连')),
              TextButton(onPressed: _busy ? null : () => unawaited(_run(() async {
                await EmbeddedNetworkSession.action('logout');
                _secret.clear();
                await _load();
              })), child: const Text('退出并清除当前通道身份')),
            ]),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ]),
      ),
    );
  }
}

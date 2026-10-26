import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:immich_mobile/infrastructure/repositories/network.repository.dart';
import 'package:immich_mobile/tailnet/tailnet_session.dart';
import 'package:url_launcher/url_launcher.dart';

class TailnetSettings extends StatefulWidget {
  const TailnetSettings({super.key});

  @override
  State<TailnetSettings> createState() => _TailnetSettingsState();
}

class _TailnetSettingsState extends State<TailnetSettings> {
  Map<String, dynamic> _status = const {'enabled': false, 'state': 'Loading'};
  Timer? _timer;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isIOS) {
      unawaited(_refresh());
      _timer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => unawaited(_refresh()),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final status = await TailnetSession.status();
      if (mounted) setState(() => _status = status);
    } catch (_) {
      if (mounted) setState(() => _error = '连接不可用，请重连或重新授权。');
    }
  }

  Future<void> _action(String action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await TailnetSession.action(action);
      await NetworkRepository.init();
      await _refresh();
    } catch (_) {
      if (mounted) setState(() => _error = '操作未完成，请重连后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS) return const SizedBox.shrink();
    final enabled = _status['enabled'] == true;
    final authURL = Uri.tryParse(_status['authURL'] as String? ?? '');
    final canAuthorize =
        authURL != null &&
        authURL.scheme == 'https' &&
        (authURL.host == 'login.tailscale.com' ||
            authURL.host.endsWith('.tailscale.com'));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('内嵌 Tailscale（iOS 18.1+）'),
              subtitle: Text('状态：${_status['state']} · 不占用系统 VPN'),
              value: enabled,
              onChanged: _busy
                  ? null
                  : (value) => unawaited(_action(value ? 'enable' : 'disable')),
            ),
            if (enabled) ...[
              const Text(
                '服务器地址填写家中 Immich 的 tailnet 地址。前台可备份；退到后台会暂停，回到前台继续。后台自动备份和桌面小组件无法使用此隧道。',
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => unawaited(_action('login')),
                    child: const Text('请求授权'),
                  ),
                  if (canAuthorize)
                    TextButton(
                      onPressed: () => unawaited(
                        launchUrl(
                          authURL,
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                      child: const Text('打开 Tailscale 授权网页'),
                    ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => unawaited(_action('reconnect')),
                    child: const Text('重连'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => unawaited(_action('logout')),
                    child: const Text('退出并清除节点身份'),
                  ),
                ],
              ),
            ],
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }
}

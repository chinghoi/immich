import 'dart:async';

import 'package:flutter/material.dart';
import 'package:immich_mobile/embedded_network/embedded_network_session.dart';
import 'package:immich_mobile/utils/url_helper.dart';

/// One upstream widget insertion; provider details stay outside Immich's bar.
class EmbeddedNetworkStatusIndicator extends StatefulWidget {
  const EmbeddedNetworkStatusIndicator({super.key});
  @override
  State<EmbeddedNetworkStatusIndicator> createState() => _EmbeddedNetworkStatusIndicatorState();
}

class _EmbeddedNetworkStatusIndicatorState extends State<EmbeddedNetworkStatusIndicator> with WidgetsBindingObserver {
  Map<String, dynamic> _status = const {'state': 'Loading'};
  Timer? _timer;
  bool _refreshing = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => unawaited(_refresh()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    if (_refreshing || WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    _refreshing = true;
    try {
      final status = await EmbeddedNetworkSession.status(serverHost: Uri.tryParse(getServerUrl() ?? '')?.host);
      if (mounted) {
        setState(() => _status = status);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _status = {..._status, 'state': 'Unavailable'});
      }
    } finally {
      _refreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = _status['mode'] as String? ?? '';
    final name = switch (mode) {
      'tailscale' => 'Tailscale',
      'easytier' => 'EasyTier',
      _ => '网络',
    };
    final state = _status['state'];
    final protocol = _status['protocol'] as String? ?? '';
    final suffix = protocol.isEmpty ? '' : '（$protocol）';
    final (label, detail, icon, color) = switch ((mode, state, _status['targetRoute'])) {
      ('none', _, _) => ('普通连接', '当前未使用内嵌组网，连接遵循手机的普通网络设置。', Icons.public_rounded, Colors.grey),
      (_, 'NeedsLogin', _) => ('等待授权', '请在网络设置中完成 Tailscale 授权。', Icons.login_rounded, Colors.orange),
      (_, 'NeedsMachineAuth', _) => (
        '等待批准',
        '此设备等待 Tailscale 管理员批准。',
        Icons.admin_panel_settings_outlined,
        Colors.orange,
      ),
      (_, 'NeedsConfiguration', _) => ('等待配置', '请在网络设置中填写 EasyTier 配置并保存。', Icons.settings_ethernet, Colors.orange),
      (_, 'Unavailable', _) => ('连接不可用', '无法读取连接状态，请检查网络设置或重连。', Icons.error_outline_rounded, Colors.red),
      (_, 'Running', 'Direct') => ('直连', '当前服务器的 $name 路由为直连$suffix。直连表示路径，不代表吞吐速度。', Icons.link_rounded, Colors.green),
      (_, 'Running', 'Relay') => ('中继', '当前服务器的 $name 路由经过中继$suffix。', Icons.compare_arrows_rounded, Colors.orange),
      (_, 'Running', 'Unlinked') => (
        '未链接',
        '网络核心已启动，但未找到当前服务器的路由。请检查服务器地址；两种组网的虚拟 IP 通常不同。',
        Icons.link_off_rounded,
        Colors.grey,
      ),
      (_, 'Disabled' || 'Stopped' || 'NoState', _) => ('未链接', '内嵌网络尚未启动。', Icons.link_off_rounded, Colors.grey),
      _ => ('连接中', '$name 正在启动或恢复连接。', Icons.sync_rounded, Colors.blue),
    };
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      tooltip: '$name：$label',
      onPressed: () => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('$name · $label'),
          content: Text(detail),
          actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('知道了'))],
        ),
      ),
      icon: Icon(icon, color: color, size: 24, semanticLabel: '$name：$label'),
    );
  }
}

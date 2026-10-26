import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// iOS-only control bridge. HTTP bodies, tokens and node keys do not cross it.
class TailnetSession {
  static const channel = MethodChannel('app.immich/tailnet');
  static bool _listening = false;
  static Future<void> Function()? onTransportChanged;

  static Future<void> prepare() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    if (!_listening) {
      _listening = true;
      channel.setMethodCallHandler((call) async {
        if (call.method == 'transportChanged') {
          await onTransportChanged?.call();
        }
      });
    }
    try {
      await channel.invokeMethod<void>('prepare');
    } on PlatformException catch (error) {
      // Native transport remains fail-closed. Keep the UI reachable so the user
      // can disable/reconnect instead of getting stuck at bootstrap forever.
      if (error.code != 'TAILNET_UNAVAILABLE') {
        rethrow;
      }
    }
  }

  static Future<bool> get enabled async =>
      defaultTargetPlatform == TargetPlatform.iOS && (await channel.invokeMethod<bool>('enabled') ?? false);

  static Future<Map<String, dynamic>> status() async =>
      await channel.invokeMapMethod<String, dynamic>('status') ?? {'enabled': false, 'state': 'Disabled'};

  static Future<void> action(String action) => channel.invokeMethod<void>(action);

  static Future<void> requireSystemBackgroundTransport() async {
    if (await enabled) {
      throw StateError('Tailscale：后台自动备份已暂停，请保持 Immich 在前台或切换普通连接。');
    }
  }
}

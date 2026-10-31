import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// iOS-only control bridge. HTTP bodies, tokens and node keys do not cross it.
enum EmbeddedNetworkMode { none, tailscale, easytier }

class EmbeddedNetworkSession {
  static const channel = MethodChannel('app.immich/tailnet');
  static bool _listening = false;
  static Future<void> Function()? onTransportChanged;

  static bool get isRootIsolate => ui.RootIsolateToken.instance != null;

  @visibleForTesting
  static void installTransportListener() {
    if (!isRootIsolate || _listening) return;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'transportChanged') {
        await onTransportChanged?.call();
      }
    });
    _listening = true;
  }

  static Future<void> prepare() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    installTransportListener();
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

  static Future<Map<String, dynamic>> status({String? serverHost}) async =>
      await channel.invokeMapMethod<String, dynamic>(
        'status',
        serverHost == null ? null : {'serverHost': serverHost},
      ) ??
      {'enabled': false, 'state': 'Disabled', 'targetRoute': 'Unlinked'};

  static Future<void> select(EmbeddedNetworkMode mode) => channel.invokeMethod<void>('select', {'mode': mode.name});

  static Future<Map<String, dynamic>> configuration() async =>
      await channel.invokeMapMethod<String, dynamic>('configuration') ?? {};

  static Future<void> saveConfiguration(Map<String, dynamic> fields) =>
      channel.invokeMethod<void>('saveConfiguration', fields);

  static Future<void> releaseClientPointer(int pointer) =>
      channel.invokeMethod<void>('releaseClientPointer', {'pointer': pointer});

  static Future<void> confirmClientPointer(int pointer) =>
      channel.invokeMethod<void>('confirmSessionPointer', {'pointer': pointer});

  static Future<void> action(String action) => channel.invokeMethod<void>(action);

  static Future<void> requireSystemBackgroundTransport() async {
    if (await enabled) {
      throw StateError('内嵌网络：后台自动备份已暂停，请保持 Immich 在前台或切换普通连接。');
    }
  }
}

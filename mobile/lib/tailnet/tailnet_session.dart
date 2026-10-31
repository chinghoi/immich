// Compatibility boundary for existing Immich hooks. Provider implementations
// and UI live in embedded_network; upstream call sites need no provider logic.
import 'package:immich_mobile/embedded_network/embedded_network_session.dart';
export 'package:immich_mobile/embedded_network/embedded_network_session.dart' show EmbeddedNetworkMode;

class TailnetSession {
  static const channel = EmbeddedNetworkSession.channel;
  static bool get isRootIsolate => EmbeddedNetworkSession.isRootIsolate;
  static set onTransportChanged(Future<void> Function()? callback) =>
      EmbeddedNetworkSession.onTransportChanged = callback;
  static Future<void> prepare() => EmbeddedNetworkSession.prepare();
  static Future<bool> get enabled => EmbeddedNetworkSession.enabled;
  static Future<Map<String, dynamic>> status({String? serverHost}) =>
      EmbeddedNetworkSession.status(serverHost: serverHost);
  static Future<void> releaseClientPointer(int pointer) => EmbeddedNetworkSession.releaseClientPointer(pointer);
  static Future<void> confirmClientPointer(int pointer) => EmbeddedNetworkSession.confirmClientPointer(pointer);
  static Future<void> action(String action) => EmbeddedNetworkSession.action(action);
  static Future<void> requireSystemBackgroundTransport() => EmbeddedNetworkSession.requireSystemBackgroundTransport();
}

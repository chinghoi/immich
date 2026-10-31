import 'dart:ffi';
import 'dart:io';

import 'package:cupertino_http/cupertino_http.dart';
import 'package:http/http.dart' as http;
import 'package:immich_mobile/embedded_network/transport_refresh_queue.dart';
import 'package:immich_mobile/providers/infrastructure/platform.provider.dart';
import 'package:immich_mobile/tailnet/tailnet_session.dart';
import 'package:ok_http/ok_http.dart';
import 'package:web_socket/web_socket.dart';

class NetworkRepository {
  static http.Client? _client;
  static Pointer<Void>? _clientPointer;
  static URLSession? _sharedSession;
  static final http.Client _forwardingClient = _CurrentSessionClient();
  static final _refreshQueue = TransportRefreshQueue();

  static Future<void> init() {
    if (!Platform.isIOS) {
      return _initialize();
    }
    return _refreshQueue.run(_initialize);
  }

  static Future<void> _initialize() async {
    if (Platform.isIOS) {
      if (TailnetSession.isRootIsolate) {
        TailnetSession.onTransportChanged = () => _refreshQueue.run(_initialize, refresh: true);
        await TailnetSession.prepare();
      }
    }
    final clientPointer = Pointer<Void>.fromAddress(await networkApi.getClientPointer());
    if (Platform.isIOS) {
      // Native keeps this exact generation alive until the ObjC wrapper owns it.
      late final URLSession session;
      try {
        session = URLSession.fromRawPointer(clientPointer.cast());
      } finally {
        await TailnetSession.releaseClientPointer(clientPointer.address);
      }
      if (clientPointer == _clientPointer) {
        if (TailnetSession.isRootIsolate) {
          await TailnetSession.confirmClientPointer(clientPointer.address);
        }
        return;
      }
      final replacement = CupertinoClient.fromSharedSession(session);
      final previous = _client;
      _sharedSession = session;
      _clientPointer = clientPointer;
      _client = replacement;
      previous?.close();
      if (TailnetSession.isRootIsolate) {
        await TailnetSession.confirmClientPointer(clientPointer.address);
      }
    } else {
      if (clientPointer == _clientPointer) {
        return;
      }
      _clientPointer = clientPointer;
      _client?.close();
      _client = OkHttpClient.fromJniGlobalRef(
        clientPointer,
        configuration: const OkHttpClientConfiguration(
          connectTimeout: Duration(seconds: 30),
          readTimeout: Duration(seconds: 60),
          writeTimeout: Duration(seconds: 60),
        ),
      );
    }
  }

  static Future<void> setHeaders(Map<String, String> headers, List<String> serverUrls, {String? token}) async {
    await networkApi.setRequestHeaders(headers, serverUrls, token);
    if (Platform.isIOS) {
      await init();
    }
  }

  // ignore: avoid-unused-parameters
  static Future<WebSocket> createWebSocket(Uri uri, {Map<String, String>? headers, Iterable<String>? protocols}) {
    if (Platform.isIOS) {
      return CupertinoWebSocket.connectWithSession(_sharedSession!, uri, protocols: protocols);
    } else {
      return OkHttpWebSocket.connectFromJniGlobalRef(_clientPointer!, uri, protocols: protocols);
    }
  }

  /// Returns a shared HTTP client that uses native SSL configuration.
  ///
  /// On iOS: Uses SharedURLSessionManager's URLSession.
  /// On Android: Uses SharedHttpClientManager's OkHttpClient.
  ///
  /// Must call [init] before using this method.
  static http.Client get client => Platform.isIOS ? _forwardingClient : _client!;
}

/// ApiService and uploads can retain this object across a native session change.
class _CurrentSessionClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Background isolates cannot receive transport-change events. Reacquire
    // the current native session at each request boundary.
    if (!TailnetSession.isRootIsolate) await NetworkRepository.init();
    return NetworkRepository._client!.send(request);
  }

  @override
  void close() {} // The native session's lifetime is managed by NetworkRepository.
}

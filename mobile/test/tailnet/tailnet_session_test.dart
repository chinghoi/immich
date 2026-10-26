import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/tailnet/tailnet_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <String>[];
  var enabled = false;

  setUp(() {
    calls.clear();
    enabled = false;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(TailnetSession.channel, (call) async {
          calls.add(call.method);
          if (call.method == 'enabled') return enabled;
          if (call.method == 'status')
            return {'enabled': enabled, 'state': 'NeedsLogin'};
          return null;
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TailnetSession.onTransportChanged = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(TailnetSession.channel, null);
  });

  test('system background queue is rejected even before tailnet authorization completes', () async {
    enabled = true;
    await expectLater(
      TailnetSession.requireSystemBackgroundTransport(),
      throwsStateError,
    );
    expect(calls, ['enabled']);
  });

  test('ordinary iOS connections retain system background transfers', () async {
    await TailnetSession.requireSystemBackgroundTransport();
    expect(calls, ['enabled']);
  });

  test('Android never invokes the iOS bridge', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await TailnetSession.prepare();
    await TailnetSession.requireSystemBackgroundTransport();
    expect(calls, isEmpty);
  });

  test(
    'authorization status can be displayed without exposing proxy secrets',
    () async {
      enabled = true;
      final status = await TailnetSession.status();
      expect(status, {'enabled': true, 'state': 'NeedsLogin'});
    },
  );

  test('native reconnect notifies the cached HTTP session owner', () async {
    var refreshed = false;
    TailnetSession.onTransportChanged = () async {
      refreshed = true;
    };
    await TailnetSession.prepare();
    final message = const StandardMethodCodec().encodeMethodCall(
      const MethodCall('transportChanged'),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage('app.immich/tailnet', message, (_) {});
    expect(refreshed, isTrue);
  });
}

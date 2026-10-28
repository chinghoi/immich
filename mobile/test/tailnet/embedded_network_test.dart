import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/embedded_network/embedded_network_session.dart';
import 'package:immich_mobile/embedded_network/embedded_network_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  var mode = 'none';
  setUp(() {
    calls.clear();
    mode = 'none';
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(EmbeddedNetworkSession.channel, (call) async {
      calls.add(call);
      if (call.method == 'select') mode = (call.arguments as Map)['mode'] as String;
      if (call.method == 'enabled') return mode != 'none';
      if (call.method == 'status') return {'mode': mode, 'enabled': mode != 'none', 'state': 'Running'};
      if (call.method == 'configuration') return {'tcpOnly': true, 'hasSecret': true};
      return null;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(EmbeddedNetworkSession.channel, null);
  });
  test('all three choices cross the same control boundary with distinct modes', () async {
    for (final mode in EmbeddedNetworkMode.values) {
      await EmbeddedNetworkSession.select(mode);
      expect((await EmbeddedNetworkSession.status())['mode'], mode.name);
    }
    expect(calls.where((c) => c.method == 'select').map((c) => c.arguments),
        [{'mode': 'none'}, {'mode': 'tailscale'}, {'mode': 'easytier'}]);
  });
  test('EasyTier uses the same foreground restriction as Tailscale', () async {
    await EmbeddedNetworkSession.select(EmbeddedNetworkMode.easytier);
    await expectLater(EmbeddedNetworkSession.requireSystemBackgroundTransport(), throwsStateError);
    await EmbeddedNetworkSession.select(EmbeddedNetworkMode.none);
    await EmbeddedNetworkSession.requireSystemBackgroundTransport();
  });
  test('configuration read does not request the stored secret', () async {
    expect(await EmbeddedNetworkSession.configuration(), {'tcpOnly': true, 'hasSecret': true});
    expect(calls.single.method, 'configuration');
    expect(calls.single.arguments, isNull);
  });
  testWidgets('provider settings are absent on Android', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(const EmbeddedNetworkSettings());
    expect(calls, isEmpty);
  });
}

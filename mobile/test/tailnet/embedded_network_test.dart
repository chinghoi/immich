import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/embedded_network/embedded_network_session.dart';
import 'package:immich_mobile/embedded_network/embedded_network_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  var mode = 'none';
  var rejectSave = false;
  setUp(() {
    calls.clear();
    mode = 'none';
    rejectSave = false;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      EmbeddedNetworkSession.channel,
      (call) async {
        calls.add(call);
        if (call.method == 'saveConfiguration' && rejectSave) {
          throw PlatformException(code: 'TEST_SAVE_FAILURE');
        }
        if (call.method == 'select') {
          mode = (call.arguments as Map)['mode'] as String;
        }
        if (call.method == 'enabled') {
          return mode != 'none';
        }
        if (call.method == 'status') {
          return {'mode': mode, 'enabled': mode != 'none', 'state': 'Running'};
        }
        if (call.method == 'configuration') {
          return {'tcpOnly': true, 'hasSecret': true};
        }
        return null;
      },
    );
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      EmbeddedNetworkSession.channel,
      null,
    );
  });
  test('all three choices cross the same control boundary with distinct modes', () async {
    for (final mode in EmbeddedNetworkMode.values) {
      await EmbeddedNetworkSession.select(mode);
      expect((await EmbeddedNetworkSession.status())['mode'], mode.name);
    }
    expect(calls.where((c) => c.method == 'select').map((c) => c.arguments), [
      {'mode': 'none'},
      {'mode': 'tailscale'},
      {'mode': 'easytier'},
    ]);
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
  testWidgets('EasyTier form stays scrollable on a small screen with keyboard and larger text', (tester) async {
    mode = 'easytier';
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            viewInsets: EdgeInsets.only(bottom: 260),
            textScaler: TextScaler.linear(1.3),
          ),
          child: const Scaffold(
            body: SingleChildScrollView(
              child: Center(child: SizedBox(width: 300, child: EmbeddedNetworkSettings())),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('连接配置'));
    await tester.tap(find.text('连接配置'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('embedded-network-connect')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('embedded-network-connect')), findsOneWidget);
    expect(find.text('已安全保存；留空沿用原密钥'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('connection strategy passes independent policies to the native boundary', (tester) async {
    mode = 'easytier';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: EmbeddedNetworkSettings())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('连接配置'));
    await tester.tap(find.text('连接配置'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('TCP 直连优先（推荐）'));
    await tester.tap(find.text('TCP 直连优先（推荐）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('仅 TCP 中继').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('embedded-network-connect')));
    // Stop at the native configuration boundary; the widget test has no native networking SDK.
    rejectSave = true;
    await tester.tap(find.byKey(const ValueKey('embedded-network-connect')));
    await tester.pumpAndSettle();
    final saved = calls.lastWhere((call) => call.method == 'saveConfiguration').arguments as Map;
    expect(saved['tcpOnly'], isTrue);
    expect(saved['allowP2P'], isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('settings use compact list rows in light and dark themes', (tester) async {
    mode = 'easytier';
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final brightness in Brightness.values) {
      final previewKey = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff4756b5), brightness: brightness),
          useMaterial3: true,
        ),
        home: Scaffold(body: SingleChildScrollView(
          child: RepaintBoundary(key: previewKey, child: const EmbeddedNetworkSettings()),
        )),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(Card), findsNothing);
      expect(find.text('连接方式'), findsOneWidget);
      expect(find.text('连接策略'), findsNothing);
      expect(find.text('连接配置'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('NETWORK_UI_PREVIEWS')) {
        await tester.runAsync(() async {
          final boundary = previewKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
          final output = File('build/network-previews/${brightness.name}.png');
          await output.parent.create(recursive: true);
          await output.writeAsBytes(data.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('provider settings are absent on Android', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(const EmbeddedNetworkSettings());
    expect(calls, isEmpty);
    debugDefaultTargetPlatformOverride = null;
  });
}

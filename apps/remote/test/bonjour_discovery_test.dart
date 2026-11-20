import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lg_discovery/lg_discovery.dart';
import 'package:smart_remote/discovery/bonjour_discovery.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.smartremote/lg_discovery.app-test');
  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('maps resolved Bonjour services to discovered TVs on iOS', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          return <Object?>[
            <Object?, Object?>{
              'name': 'Living room TV',
              'host': '192.168.1.31',
            },
          ];
        });

    final discovery = BonjourDiscovery(LgDiscovery(channel: channel));

    expect(discovery.isSupported, isTrue);
    final tvs = await discovery.search(timeout: const Duration(seconds: 1));

    expect(calls.single.method, 'browseBonjour');
    expect(tvs, hasLength(1));
    expect(tvs.single.host, '192.168.1.31');
    expect(tvs.single.displayName, 'Living room TV');
  });

  test('is skipped entirely on Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          return <Object?>[];
        });

    final discovery = BonjourDiscovery(LgDiscovery(channel: channel));

    expect(discovery.isSupported, isFalse);
    expect(await discovery.search(), isEmpty);
    expect(calls, isEmpty);
  });
}

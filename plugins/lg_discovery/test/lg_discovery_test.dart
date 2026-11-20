import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lg_discovery/lg_discovery.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.smartremote/lg_discovery.test');
  late List<MethodCall> calls;
  late Object? Function(MethodCall call) handler;

  setUp(() {
    calls = <MethodCall>[];
    handler = (MethodCall call) => null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      return handler(call);
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('Android holds and releases the multicast lock', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final discovery = LgDiscovery(channel: channel);

    expect(discovery.supportsMulticastLock, isTrue);
    expect(discovery.supportsBonjour, isFalse);

    await discovery.acquireMulticastLock();
    await discovery.releaseMulticastLock();

    expect(
      calls.map((MethodCall call) => call.method),
      <String>['acquireMulticastLock', 'releaseMulticastLock'],
    );
  });

  test('non-Android platforms never touch the channel for the lock', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final discovery = LgDiscovery(channel: channel);

    await discovery.acquireMulticastLock();
    await discovery.releaseMulticastLock();

    expect(calls, isEmpty);
  });

  test('iOS browses Bonjour with the requested timeout and maps results',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    handler = (MethodCall call) {
      expect(call.method, 'browseBonjour');
      expect(call.arguments, <String, Object>{'timeoutMs': 3000});
      return <Object?>[
        <Object?, Object?>{'name': 'Living room', 'host': '192.168.1.30'},
        <Object?, Object?>{'name': 'No host', 'host': ''},
        'garbage',
      ];
    };

    final discovery = LgDiscovery(channel: channel);
    final tvs = await discovery.browseBonjour(
      timeout: const Duration(seconds: 3),
    );

    expect(tvs, hasLength(1));
    expect(tvs.single.name, 'Living room');
    expect(tvs.single.host, '192.168.1.30');
  });

  test('a platform without Bonjour returns an empty list without a call',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final discovery = LgDiscovery(channel: channel);

    expect(await discovery.browseBonjour(), isEmpty);
    expect(calls, isEmpty);
  });

  test('a native error surfaces as a PlatformException', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    handler =
        (MethodCall call) => throw PlatformException(code: 'browse_failed');
    final discovery = LgDiscovery(channel: channel);

    expect(
      discovery.browseBonjour(),
      throwsA(isA<PlatformException>()),
    );
  });
}

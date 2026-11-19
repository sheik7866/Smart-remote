import 'dart:async';
import 'dart:convert';

import 'package:mock_webos_tv/mock_webos_tv.dart';
import 'package:test/test.dart';
import 'package:webos_ssap/webos_ssap.dart';

import 'support.dart';

void main() {
  group('over a real socket', () {
    late MockWebOsTv tv;
    late SsapSession session;
    late SsapClient client;

    setUp(() async {
      tv = await startTv(MockTvConfig());
      session = await paired(tv);
      client = SsapClient(session: session);
    });

    test('sends the request with an id the TV can answer', () async {
      await client.volumeUp();

      final frame = tv.requests.last;
      expect(frame['type'], 'request');
      expect(frame['uri'], 'ssap://audio/volumeUp');
      expect(frame['id'], isA<String>());
    });

    test('request ids are never reused', () async {
      await client.volumeUp();
      await client.volumeDown();
      await client.volumeUp();

      final ids = <String>[
        for (final request in tv.requests)
          if (request['type'] == 'request') request['id'] as String,
      ];
      expect(ids.toSet().length, ids.length);
    });

    test('unknown URI maps to a capability error', () async {
      await expectLater(
        session.request('ssap://does/notExist'),
        throwsA(
          isA<SsapError>()
              .having((e) => e.code, 'code', 'unknown_uri')
              .having((e) => e.kind, 'kind', SsapErrorKind.capability),
        ),
      );
    });

    test('a silent request times out and leaves nothing pending', () async {
      tv.silentUris.add('ssap://audio/getVolume');

      await expectLater(
        session.request('ssap://audio/getVolume',
            timeout: const Duration(milliseconds: 80)),
        throwsA(isA<SsapError>().having((e) => e.code, 'code', 'timeout')),
      );
      expect(session.pendingRequests, 0);
    });

    test('subscriptions deliver updates from the TV', () async {
      final subscription = await client.subscribeVolume();
      final next = Completer<Map<String, dynamic>>();
      final listener = subscription.updates.listen((update) {
        if (!next.isCompleted) next.complete(update);
      });

      await client.volumeUp();
      final update =
          await next.future.timeout(const Duration(seconds: 2));

      expect(update['volume'], 13);
      expect(subscription.id, isNotEmpty);
      await listener.cancel();
      await subscription.cancel();
    });

    test('a cancelled subscription stops delivering', () async {
      var received = 0;
      final subscription = await client.subscribeVolume();
      final listener =
          subscription.updates.listen((_) => received += 1);

      await subscription.cancel();
      await client.volumeUp();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(received, 0);
      expect(session.activeSubscriptions, 0);
      await listener.cancel();
    });

    test('the session reports the TV going away', () async {
      await tv.dropClients();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(session.isOpen, isFalse);
    });
  });

  group('lifecycle', () {
    test('a late response is counted and dropped, not matched', () async {
      final transport = FakeTransport();
      final session = SsapSession(
        transport: transport,
        timeouts: const SsapTimeouts(
          request: Duration(milliseconds: 60),
          pairing: Duration(milliseconds: 200),
        ),
      );
      await session.connect();
      addTearDown(session.close);

      await expectLater(
        session.request('ssap://audio/getVolume'),
        throwsA(isA<SsapError>().having((e) => e.code, 'code', 'timeout')),
      );

      final id = (jsonDecode(transport.sent.single) as Map<String, dynamic>)['id'];
      transport.deliver(jsonEncode(<String, dynamic>{
        'type': 'response',
        'id': id,
        'payload': <String, dynamic>{'returnValue': true},
      }));
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(session.lateResponses, 1);
      expect(session.pendingRequests, 0);
    });

    test('closing fails pending requests with a closed error', () async {
      final session = SsapSession(transport: FakeTransport());
      await session.connect();

      final pending = session.request(
        'ssap://audio/getVolume',
        timeout: const Duration(seconds: 5),
      );
      final expectation = expectLater(
        pending,
        throwsA(isA<SsapError>()
            .having((e) => e.kind, 'kind', SsapErrorKind.closed)),
      );
      await session.close();
      await expectation;
    });

    test('malformed frames are dropped without killing the session',
        () async {
      final transport = FakeTransport();
      final session = SsapSession(transport: transport);
      await session.connect();
      addTearDown(session.close);

      transport.deliver('<html>not ssap</html>');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(session.droppedFrames, 1);
      expect(session.isOpen, isTrue);
    });

    test('register on a closed session fails without throwing raw errors',
        () async {
      final session = SsapSession(transport: FakeTransport());
      await expectLater(
        session.register(manifest: defaultManifest),
        throwsA(isA<SsapError>()),
      );
    });
  });
}

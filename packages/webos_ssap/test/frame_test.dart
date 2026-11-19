import 'dart:convert';

import 'package:test/test.dart';
import 'package:webos_ssap/webos_ssap.dart';

void main() {
  group('SsapFrame.decode', () {
    test('reads a request envelope', () {
      final frame = SsapFrame.decode(jsonEncode(<String, dynamic>{
        'id': 'request_1',
        'type': 'request',
        'uri': 'ssap://audio/volumeUp',
        'payload': <String, dynamic>{'volume': 10},
      }));

      expect(frame.type, SsapMessageType.request);
      expect(frame.id, 'request_1');
      expect(frame.uri, 'ssap://audio/volumeUp');
      expect(frame.payload['volume'], 10);
    });

    test('reads a registered frame and its client key', () {
      final frame = SsapFrame.decode(jsonEncode(<String, dynamic>{
        'type': 'registered',
        'payload': <String, dynamic>{'client-key': 'abc123'},
      }));

      expect(frame.type, SsapMessageType.registered);
      expect(frame.payload['client-key'], 'abc123');
    });

    test('keeps a top-level error string', () {
      final frame = SsapFrame.decode(jsonEncode(<String, dynamic>{
        'id': 'request_2',
        'type': 'error',
        'error': '404 no such service or method',
      }));

      expect(frame.errorText, contains('404'));
      expect(frame.payload, isEmpty);
    });

    test('rejects non-JSON text', () {
      expect(
        () => SsapFrame.decode('not json at all'),
        throwsA(isA<FrameFormatException>()),
      );
    });

    test('rejects JSON that is not an object', () {
      expect(
        () => SsapFrame.decode('[1,2,3]'),
        throwsA(isA<FrameFormatException>()),
      );
    });

    test('rejects a frame without a type', () {
      expect(
        () => SsapFrame.decode('{"id":"x"}'),
        throwsA(isA<FrameFormatException>()),
      );
    });

    test('maps unknown types without throwing', () {
      final frame = SsapFrame.decode('{"type":"hello"}');
      expect(frame.type, SsapMessageType.unknown);
      expect(frame.rawType, 'hello');
    });
  });

  group('encoding', () {
    test('register omits the client key when there is none', () {
      final decoded = jsonDecode(SsapFrame.encodeRegister(
        id: 'register_1',
        manifest: defaultManifest,
      )) as Map<String, dynamic>;
      final payload = decoded['payload'] as Map<String, dynamic>;

      expect(decoded['type'], 'register');
      expect(payload.containsKey('client-key'), isFalse);
      expect(payload['pairingType'], 'PROMPT');
      expect(payload['manifest'], defaultManifest);
    });

    test('register includes a stored key', () {
      final decoded = jsonDecode(SsapFrame.encodeRegister(
        id: 'register_2',
        manifest: defaultManifest,
        clientKey: 'stored-key',
      )) as Map<String, dynamic>;

      expect((decoded['payload'] as Map)['client-key'], 'stored-key');
    });

    test('subscribe sets the subscribe flag', () {
      final decoded = jsonDecode(SsapFrame.encodeSubscribe(
        id: 'sub_1',
        uri: 'ssap://audio/getVolume',
      )) as Map<String, dynamic>;

      expect(decoded['type'], 'subscribe');
      expect((decoded['payload'] as Map)['subscribe'], isTrue);
    });
  });
}

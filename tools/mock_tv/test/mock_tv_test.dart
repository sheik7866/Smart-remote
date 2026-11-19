import 'dart:convert';
import 'dart:io';

import 'package:mock_webos_tv/mock_webos_tv.dart';
import 'package:test/test.dart';

void main() {
  test('accept pairing shows a prompt then registers a client key', () async {
    final tv = MockWebOsTv(MockTvConfig(promptDelay: Duration.zero));
    await tv.start();
    addTearDown(tv.stop);

    final socket = await WebSocket.connect(tv.wsEndpoint);
    addTearDown(socket.close);
    final frames = <Map<String, dynamic>>[];
    socket.listen((dynamic data) {
      if (data is String) {
        frames.add(jsonDecode(data) as Map<String, dynamic>);
      }
    });

    socket.add(jsonEncode(<String, dynamic>{
      'id': 'register_1',
      'type': 'register',
      'payload': <String, dynamic>{'pairingType': 'PROMPT'},
    }));
    await _waitFor(() => frames.any((f) => f['type'] == 'registered'));

    expect(frames.first['type'], 'response');
    expect((frames.first['payload'] as Map)['pairingType'], 'PROMPT');
    final registered = frames.firstWhere((f) => f['type'] == 'registered');
    expect((registered['payload'] as Map)['client-key'], tv.issuedClientKey);
  });

  test('deny pairing answers 403', () async {
    final tv = MockWebOsTv(MockTvConfig(pairing: PairingBehaviour.deny));
    await tv.start();
    addTearDown(tv.stop);

    final socket = await WebSocket.connect(tv.wsEndpoint);
    addTearDown(socket.close);
    final frames = <Map<String, dynamic>>[];
    socket.listen((dynamic data) {
      if (data is String) {
        frames.add(jsonDecode(data) as Map<String, dynamic>);
      }
    });

    socket.add(jsonEncode(<String, dynamic>{
      'id': 'register_1',
      'type': 'register',
      'payload': <String, dynamic>{},
    }));
    await _waitFor(() => frames.isNotEmpty);

    expect(frames.single['type'], 'error');
    expect(frames.single['error'], contains('403'));
  });
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('condition not met before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

import 'package:mock_webos_tv/mock_webos_tv.dart';
import 'package:test/test.dart';
import 'package:webos_ssap/webos_ssap.dart';

import 'support.dart';

void main() {
  test('volume commands send the documented URIs', () async {
    final tv = await startTv(MockTvConfig());
    final session = await paired(tv);
    final client = SsapClient(session: session);

    await client.volumeUp();
    await client.volumeDown();

    expect(tv.uris, containsAll(<String>[
      'ssap://audio/volumeUp',
      'ssap://audio/volumeDown',
    ]));
  });

  test('setVolume clamps to the protocol range', () async {
    final tv = await startTv(MockTvConfig());
    final session = await paired(tv);
    final client = SsapClient(session: session);

    await client.setVolume(150);
    expect((await client.getVolume()).volume, 100);

    await client.setVolume(-20);
    expect((await client.getVolume()).volume, 0);
  });

  test('mute reflects TV state', () async {
    final tv = await startTv(MockTvConfig());
    final session = await paired(tv);
    final client = SsapClient(session: session);

    await client.setMute(true);
    expect((await client.getVolume()).muted, isTrue);

    await client.setMute(false);
    expect((await client.getVolume()).muted, isFalse);
  });

  test('turnOff is sent once per tap', () async {
    final tv = await startTv(MockTvConfig());
    final session = await paired(tv);
    final client = SsapClient(session: session);

    await client.turnOff();

    expect(tv.turnOffCount, 1);
    expect(tv.uris, contains('ssap://system/turnOff'));
  });

  test('launchApp sends the app id as a payload', () async {
    final tv = await startTv(MockTvConfig());
    final session = await paired(tv);
    final client = SsapClient(session: session);

    await client.launchApp('netflix');

    final request = tv.requests.last;
    expect(request['uri'], 'ssap://system.launcher/launch');
    expect((request['payload'] as Map)['id'], 'netflix');
  });

  test('ARC soundbar: volume reports -1 and absolute control is rejected',
      () async {
    final tv = await startTv(MockTvConfig(volume: VolumeMode.arcExternal));
    final session = await paired(tv);
    final client = SsapClient(session: session);

    final state = await client.getVolume();
    expect(state.volume, -1);
    expect(state.absoluteVolumeSupported, isFalse);

    await expectLater(
      client.setVolume(20),
      throwsA(isA<SsapError>()
          .having((e) => e.kind, 'kind', SsapErrorKind.capability)
          .having((e) => e.code, 'code', 'tv_rejected')),
    );

    // Step volume still works on ARC setups and must not throw.
    await client.volumeUp();
  });

  test('serviceList returns the advertised services', () async {
    final tv = await startTv(MockTvConfig());
    final session = await paired(tv);
    final client = SsapClient(session: session);

    final services = await client.serviceList();

    expect(services, contains('com.webos.service.networkinput'));
    expect(services, contains('tv'));
  });
}

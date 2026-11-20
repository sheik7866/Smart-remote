import 'package:mock_webos_tv/mock_webos_tv.dart';
import 'package:test/test.dart';
import 'package:webos_ssap/webos_ssap.dart';

import 'support.dart';

void main() {
  test('presses and pointer moves reach the TV', () async {
    final tv = await startTv(MockTvConfig());
    final session = await paired(tv);
    final channel = PointerInputChannel(
      client: SsapClient(session: session),
      transports: ioTransport,
    );
    addTearDown(channel.close);

    await channel.open();
    expect(channel.isOpen, isTrue);

    await channel.press(PointerButtons.up);
    await channel.press(PointerButtons.enter);
    await channel.move(dx: 10, dy: -4);
    await channel.scroll(dy: -1);
    await channel.click();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(
      tv.pointerEvents,
      contains(equals(<String, dynamic>{'type': 'button', 'name': 'UP'})),
    );
    expect(
      tv.pointerEvents,
      contains(equals(<String, dynamic>{'type': 'button', 'name': 'ENTER'})),
    );
    expect(
      tv.pointerEvents,
      contains(equals(<String, dynamic>{'type': 'move', 'dx': 10, 'dy': -4})),
    );
    expect(
      tv.pointerEvents,
      contains(equals(<String, dynamic>{'type': 'scroll', 'dx': 0, 'dy': -1})),
    );
    expect(tv.pointerEvents.last, equals(<String, dynamic>{'type': 'click'}));
  });

  test('reports pointer_unsupported when the TV returns no socket path',
      () async {
    final tv = await startTv(MockTvConfig());
    tv.omitPointerSocket = true;
    final session = await paired(tv);
    final channel = PointerInputChannel(
      client: SsapClient(session: session),
      transports: ioTransport,
    );

    await expectLater(
      channel.open(),
      throwsA(isA<SsapError>()
          .having((e) => e.code, 'code', 'pointer_unsupported')),
    );
    await channel.close();
  });

  test('sending before open is a closed error, not a crash', () async {
    final tv = await startTv(MockTvConfig());
    final session = await paired(tv);
    final channel = PointerInputChannel(
      client: SsapClient(session: session),
      transports: ioTransport,
    );

    await expectLater(
      channel.press(PointerButtons.up),
      throwsA(isA<SsapError>().having((e) => e.code, 'code', 'pointer_closed')),
    );
    await session.close();
  });

  test('the pointer socket dies with the main connection', () async {
    final tv = await startTv(MockTvConfig());
    final session = await paired(tv);
    final channel = PointerInputChannel(
      client: SsapClient(session: session),
      transports: ioTransport,
    );
    await channel.open();
    expect(channel.isOpen, isTrue);

    await tv.stop();
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(channel.isOpen, isFalse);
    await channel.close();
  });
}

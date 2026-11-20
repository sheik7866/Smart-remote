import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remote_core/remote_core.dart';
import 'package:smart_remote/features/remote/remote_screen.dart';
import 'package:smart_remote/theme/remote_theme.dart';

const TvDevice _tv = TvDevice(
  host: '192.168.1.20',
  port: 3001,
  secure: true,
  name: 'Living room TV',
);

RemoteCapabilities _caps({bool arc = false, bool navigation = true}) =>
    RemoteCapabilities(
      absoluteVolume: !arc,
      absoluteVolumeKnown: true,
      mute: true,
      muteKnown: true,
      navigation: navigation,
      navigationKnown: true,
      probed: true,
      externalAudio: arc,
    );

RemoteSnapshot _connected({bool arc = false, int volume = 12}) =>
    RemoteSnapshot(
      status: arc ? RemoteStatus.degraded : RemoteStatus.connected,
      device: _tv,
      volume: arc ? null : volume,
      capabilities: _caps(arc: arc),
    );

Widget _screen(
  RemoteSnapshot snapshot, {
  VoidCallback? onVolumeUp,
  VoidCallback? onVolumeDown,
  VoidCallback? onToggleMute,
  void Function(int)? onSetVolume,
  void Function(RemoteKey)? onPress,
  VoidCallback? onPowerOff,
}) => MaterialApp(
  theme: buildRemoteTheme(),
  home: Scaffold(
    body: RemoteScreen(
      snapshot: snapshot,
      onVolumeUp: onVolumeUp ?? () {},
      onVolumeDown: onVolumeDown ?? () {},
      onSetVolume: onSetVolume ?? (_) {},
      onToggleMute: onToggleMute ?? () {},
      onBeginVolumeHold: ({required bool up}) {},
      onEndVolumeHold: () {},
      onRefreshVolume: () {},
      onPress: onPress ?? (_) {},
      onPowerOff: onPowerOff ?? () {},
    ),
  ),
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(800, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(child);
  await tester.pump();
}

void main() {
  testWidgets('renders volume and navigation for a connected TV', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _screen(_connected()));

    expect(find.text('Volume'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Navigation'), findsOneWidget);
    expect(find.byKey(const Key('volume-up')), findsOneWidget);
    expect(find.byKey(const Key('dpad-ok')), findsOneWidget);
  });

  testWidgets('volume and mute buttons call their actions', (
    WidgetTester tester,
  ) async {
    var up = 0;
    var down = 0;
    var mute = 0;
    await _pump(
      tester,
      _screen(
        _connected(),
        onVolumeUp: () => up += 1,
        onVolumeDown: () => down += 1,
        onToggleMute: () => mute += 1,
      ),
    );

    await tester.tap(find.byKey(const Key('volume-up')));
    await tester.tap(find.byKey(const Key('volume-down')));
    await tester.tap(find.byKey(const Key('mute-button')));

    expect(up, 1);
    expect(down, 1);
    expect(mute, 1);
  });

  testWidgets('ARC TVs disable the slider and explain why', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _screen(_connected(arc: true)));

    final slider = tester.widget<Slider>(
      find.byKey(const Key('volume-slider')),
    );
    expect(slider.onChanged, isNull);
    expect(find.byKey(const Key('volume-disabled-reason')), findsOneWidget);
    expect(find.byKey(const Key('degraded-banner')), findsOneWidget);
    expect(find.textContaining('soundbar'), findsWidgets);
  });

  testWidgets('D-pad sends the protocol-independent key', (
    WidgetTester tester,
  ) async {
    final pressed = <RemoteKey>[];
    await _pump(
      tester,
      _screen(_connected(), onPress: pressed.add),
      size: const Size(800, 1400),
    );

    await tester.ensureVisible(find.byKey(const Key('dpad-ok')));
    await tester.tap(find.byKey(const Key('dpad-ok')));
    await tester.tap(find.byKey(const Key('dpad-up')));
    await tester.ensureVisible(find.byKey(const Key('back-button')));
    await tester.tap(find.byKey(const Key('back-button')));

    expect(pressed, <RemoteKey>[RemoteKey.ok, RemoteKey.up, RemoteKey.back]);
  });

  testWidgets('navigation is disabled with a visible reason when unsupported', (
    WidgetTester tester,
  ) async {
    const snapshot = RemoteSnapshot(
      status: RemoteStatus.connected,
      device: _tv,
      volume: 10,
      capabilities: RemoteCapabilities(
        absoluteVolume: true,
        absoluteVolumeKnown: true,
        navigation: false,
        navigationKnown: true,
        probed: true,
      ),
    );
    await _pump(tester, _screen(snapshot), size: const Size(800, 1400));

    expect(find.byKey(const Key('navigation-disabled-reason')), findsOneWidget);
    final ok = tester.widget<IconButton>(find.byKey(const Key('dpad-ok')));
    expect(ok.onPressed, isNull);
  });

  testWidgets('power off asks for confirmation first', (
    WidgetTester tester,
  ) async {
    var poweredOff = 0;
    await _pump(
      tester,
      _screen(_connected(), onPowerOff: () => poweredOff += 1),
      size: const Size(800, 1400),
    );

    await tester.ensureVisible(find.byKey(const Key('power-button')));
    await tester.tap(find.byKey(const Key('power-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('power-confirm-dialog')), findsOneWidget);
    expect(poweredOff, 0);

    await tester.tap(find.byKey(const Key('power-confirm')));
    await tester.pumpAndSettle();
    expect(poweredOff, 1);
  });

  testWidgets('reconnecting shows attempt count and reason', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      _screen(
        const RemoteSnapshot(
          status: RemoteStatus.asleep,
          device: _tv,
          reconnectAttempt: 1,
          error: 'The TV stopped responding.',
        ),
      ),
    );

    expect(find.byKey(const Key('reconnect-banner')), findsOneWidget);
    expect(find.text('Reconnecting (attempt 2)'), findsOneWidget);
  });

  testWidgets('a command failure is surfaced without dropping the session', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      _screen(
        const RemoteSnapshot(
          status: RemoteStatus.connected,
          device: _tv,
          volume: 12,
          commandError: 'This TV does not support that command.',
        ),
      ),
    );

    expect(find.byKey(const Key('command-error')), findsOneWidget);
    expect(find.text('This TV does not support that command.'), findsOneWidget);
  });

  testWidgets('uses one column on a phone and two on a wide screen', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _screen(_connected()));
    expect(find.byKey(const Key('remote-phone-layout')), findsOneWidget);

    await _pump(tester, _screen(_connected()), size: const Size(1200, 900));
    expect(find.byKey(const Key('remote-wide-layout')), findsOneWidget);
  });

  testWidgets('every control exposes an accessibility label', (
    WidgetTester tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, _screen(_connected()));

    expect(find.bySemanticsLabel('Volume up'), findsOneWidget);
    expect(find.bySemanticsLabel('Volume down'), findsOneWidget);
    expect(find.bySemanticsLabel('OK'), findsWidgets);
    handle.dispose();
  });
}

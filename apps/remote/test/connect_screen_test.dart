import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remote_core/remote_core.dart';
import 'package:smart_remote/features/connect/connect_screen.dart';
import 'package:smart_remote/theme/remote_theme.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: buildRemoteTheme(),
  home: Scaffold(body: child),
);

Future<void> _pumpAt(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(800, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_wrap(child));
  await tester.pump();
}

void main() {
  testWidgets('idle state offers discovery and manual entry', (
    WidgetTester tester,
  ) async {
    var discovered = 0;
    await _pumpAt(
      tester,
      ConnectScreen(
        snapshot: const RemoteSnapshot(),
        onDiscover: () => discovered += 1,
        onConnectHost: (_, _) {},
        onConnectDevice: (_) {},
      ),
    );

    expect(find.text('No TV connected'), findsOneWidget);
    await tester.tap(find.byKey(const Key('find-tv-button')));
    expect(discovered, 1);
    expect(find.byKey(const Key('manual-host-field')), findsOneWidget);
  });

  testWidgets('discovering state disables discovery and shows progress', (
    WidgetTester tester,
  ) async {
    await _pumpAt(
      tester,
      ConnectScreen(
        snapshot: const RemoteSnapshot(status: RemoteStatus.discovering),
        onDiscover: () {},
        onConnectHost: (_, _) {},
        onConnectDevice: (_) {},
      ),
    );

    expect(find.text('Looking for your TV'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('find-tv-button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('discovered TVs are listed and connect by device', (
    WidgetTester tester,
  ) async {
    DiscoveredTv? chosen;
    await _pumpAt(
      tester,
      ConnectScreen(
        snapshot: const RemoteSnapshot(
          hasSearched: true,
          discovered: <DiscoveredTv>[
            DiscoveredTv(host: '192.168.1.40', name: 'Living room TV'),
          ],
        ),
        onDiscover: () {},
        onConnectHost: (_, _) {},
        onConnectDevice: (tv) => chosen = tv,
      ),
    );

    expect(find.text('Living room TV'), findsOneWidget);
    expect(find.text('192.168.1.40'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Connect'));
    expect(chosen?.host, '192.168.1.40');
  });

  testWidgets('awaiting approval explains what to do and offers a way out', (
    WidgetTester tester,
  ) async {
    var stopped = 0;
    await _pumpAt(
      tester,
      ConnectScreen(
        snapshot: const RemoteSnapshot(status: RemoteStatus.awaitingApproval),
        onDiscover: () {},
        onConnectHost: (_, _) {},
        onConnectDevice: (_) {},
        onStopWaiting: () => stopped += 1,
      ),
    );

    expect(find.text('Approve on your TV'), findsOneWidget);
    expect(find.text('Waiting for the TV'), findsOneWidget);
    await tester.tap(find.text('Stop waiting'));
    expect(stopped, 1);
  });

  testWidgets('errors are shown with the server-provided reason', (
    WidgetTester tester,
  ) async {
    await _pumpAt(
      tester,
      ConnectScreen(
        snapshot: const RemoteSnapshot(
          status: RemoteStatus.error,
          error: 'The TV declined the pairing request.',
        ),
        onDiscover: () {},
        onConnectHost: (_, _) {},
        onConnectDevice: (_) {},
      ),
    );

    expect(find.byKey(const Key('connection-error')), findsOneWidget);
    expect(find.text('The TV declined the pairing request.'), findsOneWidget);
  });

  testWidgets('web limitations are stated before connecting', (
    WidgetTester tester,
  ) async {
    await _pumpAt(
      tester,
      ConnectScreen(
        snapshot: const RemoteSnapshot(),
        onDiscover: () {},
        onConnectHost: (_, _) {},
        onConnectDevice: (_) {},
        webLimitations: true,
      ),
    );

    expect(find.byKey(const Key('web-limits-banner')), findsOneWidget);
  });

  testWidgets('manual entry validates and forwards host and port', (
    WidgetTester tester,
  ) async {
    String? host;
    int? port;
    await _pumpAt(
      tester,
      ConnectScreen(
        snapshot: const RemoteSnapshot(),
        onDiscover: () {},
        onConnectHost: (String h, int? p) {
          host = h;
          port = p;
        },
        onConnectDevice: (_) {},
      ),
    );

    await tester.enterText(
      find.byKey(const Key('manual-host-field')),
      '192.168.1.77',
    );
    await tester.enterText(find.byKey(const Key('manual-port-field')), '3000');
    await tester.ensureVisible(find.byKey(const Key('manual-connect-button')));
    await tester.tap(find.byKey(const Key('manual-connect-button')));

    expect(host, '192.168.1.77');
    expect(port, 3000);
  });

  testWidgets('an empty address is rejected locally', (
    WidgetTester tester,
  ) async {
    var calls = 0;
    await _pumpAt(
      tester,
      ConnectScreen(
        snapshot: const RemoteSnapshot(),
        onDiscover: () {},
        onConnectHost: (_, _) => calls += 1,
        onConnectDevice: (_) {},
      ),
    );

    await tester.ensureVisible(find.byKey(const Key('manual-connect-button')));
    await tester.tap(find.byKey(const Key('manual-connect-button')));
    await tester.pump();

    expect(calls, 0);
    expect(find.text('Enter the TV IP address first.'), findsOneWidget);
  });
}

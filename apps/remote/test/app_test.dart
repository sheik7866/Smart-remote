import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remote_core/remote_core.dart';
import 'package:smart_remote/app.dart';
import 'package:smart_remote/wiring.dart';
import 'package:webos_ssap/webos_ssap.dart';

class _FakeDiscovery implements RemoteDiscovery {
  @override
  bool get isSupported => true;

  @override
  String? get unsupportedReason => null;

  @override
  Future<List<DiscoveredTv>> search({
    Duration timeout = const Duration(seconds: 4),
  }) async => const <DiscoveredTv>[];
}

RemoteController _controller() {
  final store = MemoryCredentialStore();
  final transports = createTransportFactory();
  final service = PairingService(transports: transports, store: store);
  return RemoteController(
    pairing: PairingController(service: service, store: store),
    transports: transports,
    discovery: _FakeDiscovery(),
  );
}

void main() {
  testWidgets('app starts on the no-TV screen with discovery available', (
    WidgetTester tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(SmartRemoteApp(controller: controller));
    await tester.pump();

    expect(find.text('Smart Remote'), findsOneWidget);
    expect(find.text('No TV connected'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('find-tv-button')),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('web builds state their limits up front', (
    WidgetTester tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      SmartRemoteApp(controller: controller, webLimitations: true),
    );
    await tester.pump();

    expect(find.byKey(const Key('web-limits-banner')), findsOneWidget);
  });

  testWidgets('the menu opens the browser limitations screen', (
    WidgetTester tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);

    await tester.pumpWidget(SmartRemoteApp(controller: controller));
    await tester.pump();

    await tester.tap(find.byKey(const Key('menu-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Browser limitations'));
    await tester.pumpAndSettle();

    expect(find.text('No automatic discovery'), findsOneWidget);
  });
}

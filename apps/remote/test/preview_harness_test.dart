import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:smart_remote/preview/stop_button_harness.dart';

void main() {
  testWidgets('harness shows and cancels the simulated sweep', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const StopButtonPreviewApp());
    await tester.pump();

    expect(find.byKey(const Key('preview-harness-banner')), findsOneWidget);
    expect(find.text('Stop searching'), findsOneWidget);

    await tester.tap(find.byKey(const Key('stop-discovery-button')));
    await tester.pump();

    expect(find.text('Stop searching'), findsNothing);
    expect(find.text('Find my TV'), findsOneWidget);

    await tester.tap(find.byKey(const Key('find-tv-button')));
    await tester.pump();

    expect(find.text('Stop searching'), findsOneWidget);
  });
}

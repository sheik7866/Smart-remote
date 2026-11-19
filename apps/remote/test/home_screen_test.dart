import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_remote/app.dart';

void main() {
  testWidgets('shell renders the empty state with no active controls',
      (WidgetTester tester) async {
    await tester.pumpWidget(const SmartRemoteApp());

    expect(find.text('Smart Remote'), findsOneWidget);
    expect(find.text('No TV connected'), findsOneWidget);

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull,
        reason: 'discovery is not implemented until M5');
  });
}

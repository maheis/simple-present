import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter/material.dart';
import 'package:simple_present/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('basic task flow: create, stopwatch placeholders', (WidgetTester tester) async {
    // Start the app
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Enter a new task in the composer (first TextField)
    final textField = find.byType(TextField).first;
    expect(textField, findsOneWidget);
    await tester.enterText(textField, 'integration test task');
    await tester.pumpAndSettle();

    // Tap the add button (ElevatedButton with Icon)
    final addButton = find.widgetWithIcon(ElevatedButton, Icons.add);
    expect(addButton, findsOneWidget);
    await tester.tap(addButton);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Verify the new task text appears
    expect(find.text('integration test task'), findsWidgets);
  });
}

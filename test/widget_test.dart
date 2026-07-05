// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:simple_present/main.dart';

void main() {
  testWidgets('Adds a task to today list', (WidgetTester tester) async {
    await initializeDateFormatting('de_DE');
    await tester.pumpWidget(const SimplePresentApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Milch kaufen');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('Milch kaufen'), findsOneWidget);
  });
}

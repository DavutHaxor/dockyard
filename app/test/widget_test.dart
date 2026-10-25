import 'package:dockyard/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the app shell', (WidgetTester tester) async {
    await tester.pumpWidget(const DockyardApp());

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Dockyard'), findsOneWidget);
  });
}

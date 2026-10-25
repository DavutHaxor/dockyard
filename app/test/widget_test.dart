import 'package:dockyard/app.dart';
import 'package:dockyard/core/config/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpApp(
  WidgetTester tester, {
  Map<String, Object> preferences = const {},
}) async {
  SharedPreferences.setMockInitialValues(preferences);
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const DockyardApp(),
    ),
  );
  await tester.pump();
}

Finder _railLabel(String label) => find.descendant(
  of: find.byType(NavigationRail),
  matching: find.text(label),
);

void main() {
  testWidgets('renders a vertical rail with all sections', (tester) async {
    await _pumpApp(tester);

    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.selectedIndex, 0);
    expect(rail.destinations, hasLength(4));
    expect(_railLabel('Overview'), findsOneWidget);
    expect(_railLabel('Containers'), findsOneWidget);
    expect(_railLabel('Metrics'), findsOneWidget);
    expect(_railLabel('Settings'), findsOneWidget);

    // No login screen: the first run asks for connection details instead.
    expect(find.text('Connect your daemon'), findsOneWidget);
    expect(find.text('Open settings'), findsOneWidget);
  });

  testWidgets('switches sections from the rail', (tester) async {
    await _pumpApp(tester);

    await tester.tap(_railLabel('Settings'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      3,
    );
    expect(find.text('Daemon connection'), findsOneWidget);
    expect(find.text('Server URL'), findsOneWidget);
    expect(find.text('Admin token'), findsOneWidget);

    await tester.tap(_railLabel('Containers'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      1,
    );
    expect(find.text('No daemon configured'), findsOneWidget);
  });

  testWidgets('validates the settings form before saving', (tester) async {
    await _pumpApp(tester);
    await tester.tap(_railLabel('Settings'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    expect(find.text('Admin token is required.'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'not-a-url');
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    expect(
      find.text('Use a full URL, for example http://192.168.1.10:8080'),
      findsOneWidget,
    );
  });

  testWidgets('shows a setup prompt on metrics and containers too', (
    tester,
  ) async {
    await _pumpApp(tester);

    await tester.tap(_railLabel('Metrics'));
    await tester.pumpAndSettle();
    expect(find.text('No metrics yet'), findsOneWidget);

    await tester.tap(_railLabel('Containers'));
    await tester.pumpAndSettle();
    expect(find.text('No daemon configured'), findsOneWidget);
  });
}

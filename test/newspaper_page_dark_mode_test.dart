import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_qbank/pages/newspaper_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('NewspaperPage toggles and persists dark mode',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const MaterialApp(
        home: NewspaperPage(
          name: 'Daily News',
          url: 'https://example.com',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Starts in light mode
    expect(find.byIcon(Icons.dark_mode_rounded), findsOneWidget);
    expect(find.byIcon(Icons.light_mode_rounded), findsNothing);
    final lightScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(lightScaffold.backgroundColor, Colors.grey.shade50);

    // Toggle to dark mode
    await tester.tap(find.byIcon(Icons.dark_mode_rounded));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.light_mode_rounded), findsOneWidget);
    expect(find.byIcon(Icons.dark_mode_rounded), findsNothing);
    final darkScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(darkScaffold.backgroundColor, const Color(0xFF121212));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('newspaper_dark_mode'), isTrue);

    // Toggle back to light mode
    await tester.tap(find.byIcon(Icons.light_mode_rounded));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.dark_mode_rounded), findsOneWidget);
    expect(prefs.getBool('newspaper_dark_mode'), isFalse);
  });

  testWidgets('NewspaperPage restores persisted dark mode on init',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'newspaper_dark_mode': true});

    await tester.pumpWidget(
      const MaterialApp(
        home: NewspaperPage(
          name: 'Daily News',
          url: 'https://example.com',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.light_mode_rounded), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, const Color(0xFF121212));
  });
}

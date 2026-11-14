import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_qbank/pages/newspaper_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_cef/webview_cef.dart' as cef;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NewspaperPage on Linux', () {
    final List<MethodCall> methodCalls = [];

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      NewspaperPage.resetCefInitialization();
      cef.WebviewManager().value = false;
      methodCalls.clear();
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      NewspaperPage.resetCefInitialization();
      cef.WebviewManager().value = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('webview_cef'), null);
    });

    testWidgets(
        'successfully initializes embedded CEF webview in the app on Linux',
        (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel('webview_cef'),
                (MethodCall call) async {
          methodCalls.add(call);
          if (call.method == 'init') {
            return null;
          }
          if (call.method == 'create') {
            return [1, 100];
          }
          if (call.method == 'setJavaScriptChannels') {
            return 1;
          }
          if (call.method == 'close') {
            return null;
          }
          return null;
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: NewspaperPage(
              name: 'Prothom Alo',
              url: 'https://prothomalo.com',
            ),
          ),
        );

        // Advance through WebviewManager.initialize() 300ms delayed timer
        await tester.pump(const Duration(milliseconds: 350));
        // Advance through controller.initialize() 50ms delayed timer
        await tester.pump(const Duration(milliseconds: 100));
        // Rebuild with updated controller
        await tester.pump();

        // Ensure method calls were made in the correct order:
        // 'init' -> 'create' -> 'setJavaScriptChannels'
        final methodNames = methodCalls.map((c) => c.method).toList();
        expect(methodNames, contains('init'));
        expect(methodNames, contains('create'));
        expect(methodNames, contains('setJavaScriptChannels'));

        final createIndex = methodNames.indexOf('create');
        final channelsIndex = methodNames.indexOf('setJavaScriptChannels');
        expect(createIndex, lessThan(channelsIndex),
            reason:
                'controller.initialize must be called before setJavaScriptChannels');

        // The embedded view must render the CEF Texture widget, not the unsupported fallback
        expect(find.byType(Texture), findsOneWidget);
        expect(find.text('Prothom Alo'), findsOneWidget);
        expect(find.byIcon(Icons.arrow_back), findsOneWidget);
        expect(find.byIcon(Icons.open_in_browser), findsOneWidget);
        expect(find.textContaining('Embedded web view is not supported'),
            findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('shows fallback card when CEF fails to initialize',
        (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel('webview_cef'),
                (MethodCall call) async {
          if (call.method == 'init') {
            throw PlatformException(
                code: 'UNAVAILABLE', message: 'CEF runtime not found');
          }
          return null;
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: NewspaperPage(
              name: 'Daily Star',
              url: 'https://thedailystar.net',
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();

        expect(find.text('Daily Star'), findsWidgets);
        expect(
            find.text(
                'Embedded web view could not be loaded. You can read Daily Star directly in your default browser.'),
            findsOneWidget);
        expect(find.text('Open in Browser'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}

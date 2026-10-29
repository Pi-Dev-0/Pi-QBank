import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_qbank/pages/mcq_test_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Build a paper in the payload shape the runner reads.
String paper(int count) => jsonEncode({
      'questions': [
        for (var i = 0; i < count; i++)
          {
            'question': 'Question ${i + 1}?',
            'options': {'1': 'A$i', '2': 'B$i', '3': 'C$i', '4': 'D$i'},
            'correct_answer': '1',
          },
      ],
    });

/// A one-question paper with explicit option text.
String paperWithOptions(List<String> options) => jsonEncode({
      'questions': [
        {
          'question': 'Question 1?',
          'options': {
            for (var i = 0; i < options.length; i++) '${i + 1}': options[i],
          },
          'correct_answer': '1',
        },
      ],
    });

/// A phone-sized viewport: the paper HUD has to fit without overflowing.
Future<void> openPaper(WidgetTester tester, int count,
    {String? response}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: MCQTestPage(
        numberOfQuestions: count,
        testTimeInMinutes: 10,
        aiResponse: response ?? paper(count),
        language: 'Bangla',
        showAllQuestions: true,
      ),
    ),
  );
  await tester.pump();
}

/// Tear the page down so its one-second timer is cancelled.
Future<void> closePaper(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
}

void main() {
  testWidgets('shows the whole paper at once, with a live answer HUD',
      (tester) async {
    await openPaper(tester, 3);

    expect(find.text('Question 1?'), findsOneWidget);
    expect(find.text('Question 2?'), findsOneWidget);
    expect(find.text('Question 3?'), findsOneWidget);
    expect(find.text('0/3'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('0 of 3 answered'), findsOneWidget);

    // One card's state changes, and the HUD follows immediately.
    await tester.tap(find.text('B0'));
    await tester.pump();

    expect(find.text('1/3'), findsOneWidget);
    expect(find.text('33%'), findsOneWidget);
    expect(find.text('1 of 3 answered'), findsOneWidget);
    expect(find.text('Answered'), findsOneWidget,
        reason: 'the answered card is marked without opening the palette');

    await closePaper(tester);
  });

  testWidgets('flagging updates the HUD and the card', (tester) async {
    await openPaper(tester, 3);

    await tester.tap(find.byTooltip('Flag for review').first);
    await tester.pump();

    expect(find.byTooltip('Remove flag'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    expect(find.textContaining('1 flagged'), findsOneWidget);

    await closePaper(tester);
  });

  testWidgets('the palette scrolls a far question into view', (tester) async {
    await openPaper(tester, 20);

    final target = find.text('Question 20?');
    final before = tester.getTopLeft(target).dy;

    await tester.tap(find.byTooltip('Question palette'));
    await tester.pumpAndSettle();

    final paletteCell = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text('20'),
    );
    await tester.tap(paletteCell);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep going'));
    await tester.pumpAndSettle();

    final after = tester.getTopLeft(target).dy;
    expect(after, lessThan(before),
        reason: 'jumping must scroll the paper, not only change an index');
    expect(after, inInclusiveRange(0, 800));

    await closePaper(tester);
  });

  testWidgets('the countdown keeps ticking while the paper is open',
      (tester) async {
    await openPaper(tester, 2);

    expect(find.text('10:00'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('09:59'), findsOneWidget);

    await closePaper(tester);
  });

  testWidgets('short options use two columns; long ones keep the full width',
      (tester) async {
    await openPaper(tester, 1);

    final a = tester.getCenter(find.text('A0'));
    final b = tester.getCenter(find.text('B0'));
    final c = tester.getCenter(find.text('C0'));
    expect(b.dy, closeTo(a.dy, 0.5),
        reason: 'A and B should share the first row');
    expect(b.dx, greaterThan(a.dx));
    expect(c.dy, greaterThan(a.dy), reason: 'C should start the second row');

    await closePaper(tester);

    const long = 'A deliberately long option that needs the full card width.';
    await openPaper(tester, 1,
        response:
            paperWithOptions([long, '$long two', '$long three', '$long four']));

    final first = tester.getCenter(find.text(long));
    final second = tester.getCenter(find.text('$long two'));
    expect(second.dy, greaterThan(first.dy),
        reason: 'long options should stack, not squeeze into columns');

    await closePaper(tester);
  });

  testWidgets('results fit a phone width and summarise the paper',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await openPaper(tester, 3);

    // One wrong answer, two skipped.
    await tester.tap(find.text('B0'));
    await tester.pump();
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit Now'));
    await tester.pumpAndSettle();

    expect(find.text('Result'), findsOneWidget);
    expect(find.text('0.0%'), findsOneWidget);
    expect(find.text('0 of 3 correct'), findsOneWidget);
    expect(find.text('Skipped · 2'), findsOneWidget);
    expect(find.text('Wrong · 1'), findsOneWidget);

    await closePaper(tester);
  });
}

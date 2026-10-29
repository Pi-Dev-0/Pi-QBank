import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_qbank/pages/mcq_test_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Build a paper in the shape `MCQTestPage` reads.
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

Future<void> openPaper(WidgetTester tester, int count) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MCQTestPage(
        numberOfQuestions: count,
        testTimeInMinutes: 10,
        aiResponse: paper(count),
        language: 'Bangla',
      ),
    ),
  );
  // A zero-duration pump: the exam runs a one-second periodic timer, and
  // advancing the clock would tick it.
  await tester.pump();
}

/// Tear the page down so its timer is cancelled.
///
/// The runner keeps a periodic timer alive for the whole sitting, and a test
/// that ends with one pending fails for a reason that has nothing to do with
/// what it asserted.
Future<void> closePaper(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
}

void main() {
  testWidgets('shows one question at a time', (tester) async {
    await openPaper(tester, 3);

    expect(find.text('Question 1 of 3'), findsOneWidget);
    expect(find.text('Question 1?'), findsOneWidget);
    expect(find.text('Question 2?'), findsNothing,
        reason: 'the rest are on their own pages, not down a scroll');

    await closePaper(tester);
  });

  testWidgets('the counter and the progress bar follow the index',
      (tester) async {
    await openPaper(tester, 3);

    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, 0.0);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Question 2 of 3'), findsOneWidget);

    await closePaper(tester);
  });

  testWidgets('Previous is disabled on the first question', (tester) async {
    await openPaper(tester, 3);

    final previous = tester.widget<OutlinedButton>(
      find.byWidgetPredicate((w) => w is OutlinedButton),
    );
    expect(previous.onPressed, isNull);

    await closePaper(tester);
  });

  testWidgets('the last question offers Submit instead of Next',
      (tester) async {
    await openPaper(tester, 1);

    expect(find.text('Submit'), findsOneWidget);
    expect(find.text('Next'), findsNothing);

    await closePaper(tester);
  });

  testWidgets('tapping an option answers the question', (tester) async {
    await openPaper(tester, 3);

    expect(find.text('0 answered'), findsOneWidget);

    await tester.tap(find.text('B0'));
    await tester.pump();

    expect(find.text('1 answered'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget,
        reason: 'the chosen option is ticked');

    await closePaper(tester);
  });

  testWidgets('tapping the chosen option again clears it', (tester) async {
    // A mis-tap has to be one tap to undo.
    await openPaper(tester, 3);

    await tester.tap(find.text('B0'));
    await tester.pump();
    await tester.tap(find.text('B0'));
    await tester.pump();

    expect(find.text('0 answered'), findsOneWidget);

    await closePaper(tester);
  });

  testWidgets('an option can be flagged for review', (tester) async {
    await openPaper(tester, 3);

    expect(find.text('Flag'), findsOneWidget);
    await tester.tap(find.text('Flag'));
    await tester.pump();

    expect(find.text('Flagged'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark), findsOneWidget);

    await closePaper(tester);
  });

  testWidgets(
      'the palette opens with a legend, and its badge counts the '
      'unanswered', (tester) async {
    await openPaper(tester, 3);

    expect(find.text('3'), findsOneWidget,
        reason: 'three unanswered, shown on the palette button');

    await tester.tap(find.byTooltip('Question palette'));
    await tester.pumpAndSettle();

    expect(find.text('Question palette'), findsOneWidget);
    expect(find.text('Answered'), findsOneWidget);
    expect(find.text('Flagged'), findsOneWidget);
    expect(find.text('Unanswered'), findsOneWidget);
    expect(find.text('Keep going'), findsOneWidget);

    await closePaper(tester);
  });

  testWidgets('a flagged question is counted in the palette summary',
      (tester) async {
    await openPaper(tester, 4);

    await tester.tap(find.text('Flag'));
    await tester.pump();
    await tester.tap(find.byTooltip('Question palette'));
    await tester.pumpAndSettle();

    expect(find.textContaining('1 flagged'), findsOneWidget);

    await closePaper(tester);
  });

  testWidgets('keyboard digits answer the current question', (tester) async {
    // The desktop path: number keys pick an option without the mouse.
    await openPaper(tester, 3);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pump();

    expect(find.text('1 answered'), findsOneWidget);

    await closePaper(tester);
  });

  testWidgets('an empty paper says so instead of showing a blank page',
      (tester) async {
    await openPaper(tester, 0);

    expect(find.text('This test has no questions.'), findsOneWidget);

    await closePaper(tester);
  });

  group('submitting', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    /// Answer question 1 right and question 2 wrong, then submit.
    Future<void> answerAndSubmit(WidgetTester tester) async {
      await openPaper(tester, 2);
      await tester.tap(find.text('A0')); // option "1" — the correct key
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('B1')); // option "2" — wrong
      await tester.pump();
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit Now'));
      await tester.pumpAndSettle();
    }

    testWidgets('the score and the tally come out of the answers',
        (tester) async {
      await answerAndSubmit(tester);

      expect(find.text('Result'), findsOneWidget);
      expect(find.text('50.0%'), findsOneWidget);
      expect(find.text('1 of 2 correct'), findsOneWidget);
      expect(find.text('Correct · 1'), findsOneWidget);
      expect(find.text('Wrong · 1'), findsOneWidget);
      expect(find.text('Skipped · 0'), findsOneWidget);

      await closePaper(tester);
    });

    testWidgets('the Wrong filter hides the correct answers', (tester) async {
      await answerAndSubmit(tester);

      // The results page is taller than the test viewport, so the chip has to
      // be scrolled into reach before it can be tapped.
      await tester.ensureVisible(find.text('Wrong · 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wrong · 1'));
      await tester.pumpAndSettle();

      expect(find.text('Question 2?'), findsOneWidget);
      expect(find.text('Question 1?'), findsNothing);

      await closePaper(tester);
    });

    testWidgets('Retake clears the answers and starts the paper again',
        (tester) async {
      await answerAndSubmit(tester);

      await tester.ensureVisible(find.text('Retake this paper'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retake this paper'));
      await tester.pumpAndSettle();

      expect(find.text('Question 1 of 2'), findsOneWidget);
      expect(find.text('0 answered'), findsOneWidget,
          reason: 'every answer should have been cleared');

      await closePaper(tester);
    });
  });
}

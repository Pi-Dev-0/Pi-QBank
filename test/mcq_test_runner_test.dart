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

Future<void> openPaper(WidgetTester tester, int count,
    {bool isFromCloud = false}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MCQTestPage(
        numberOfQuestions: count,
        testTimeInMinutes: 10,
        aiResponse: paper(count),
        language: 'Bangla',
        isFromCloud: isFromCloud,
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
    Future<void> answerAndSubmit(WidgetTester tester,
        {bool isFromCloud = false}) async {
      await openPaper(tester, 2, isFromCloud: isFromCloud);
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

    testWidgets(
        'Upload button is shown for local tests but hidden for cloud tests',
        (tester) async {
      // Local test (isFromCloud = false)
      await answerAndSubmit(tester, isFromCloud: false);
      expect(find.text('Upload Test to Google Sheet'), findsOneWidget);
      await closePaper(tester);

      // Cloud test (isFromCloud = true)
      await answerAndSubmit(tester, isFromCloud: true);
      expect(find.text('Upload Test to Google Sheet'), findsNothing);
      await closePaper(tester);
    });
  });

  group('live exam options', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    /// One question answered by option 3, shown in paper mode as the cloud
    /// exams do.
    Future<void> openLivePaper(
      WidgetTester tester, {
      String language = 'Bangla',
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MCQTestPage(
            numberOfQuestions: 1,
            testTimeInMinutes: 10,
            aiResponse: jsonEncode({
              'questions': [
                {
                  'question': 'Question 1?',
                  'options': {
                    '1': 'A0',
                    '2': 'B0',
                    '3': 'C0',
                    '4': 'D0',
                  },
                  'correct_answer': '3',
                },
              ],
            }),
            language: language,
            showAllQuestions: true,
            liveExamOptions: true,
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('the bubbles are ক খ গ ঘ, not A B C D', (tester) async {
      await openLivePaper(tester);

      for (final label in ['ক', 'খ', 'গ', 'ঘ']) {
        expect(find.text(label), findsOneWidget);
      }
      for (final label in ['A', 'B', 'C', 'D']) {
        expect(find.text(label), findsNothing);
      }

      await closePaper(tester);
    });

    testWidgets('an English live paper keeps A B C D bubbles', (tester) async {
      await openLivePaper(tester, language: 'English');

      for (final label in ['A', 'B', 'C', 'D']) {
        expect(find.text(label), findsOneWidget);
      }
      for (final label in ['ক', 'খ', 'গ', 'ঘ']) {
        expect(find.text(label), findsNothing);
      }

      await closePaper(tester);
    });

    testWidgets('only the bubble answers; the option text does nothing',
        (tester) async {
      await openLivePaper(tester);

      await tester.tap(find.text('A0'));
      await tester.pump();

      expect(find.text('0 of 1 answered'), findsOneWidget,
          reason: 'tapping the answer text must not file an answer');

      await tester.tap(find.text('খ'));
      await tester.pump();

      expect(find.text('1 of 1 answered'), findsOneWidget);

      await closePaper(tester);
    });

    testWidgets('the first pick is final, and cannot be cleared',
        (tester) async {
      await openLivePaper(tester);

      await tester.tap(find.text('খ'));
      await tester.pump();

      // Another bubble is inert, and the chosen one cannot be unticked.
      await tester.tap(find.text('গ'));
      await tester.pump();
      await tester.tap(find.text('খ'));
      await tester.pump();

      expect(find.text('1 of 1 answered'), findsOneWidget);

      // Submit and find out which choice was actually filed: খ is option 2,
      // while the key is option 3.
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit Now'));
      await tester.pumpAndSettle();

      expect(find.text('0.0%'), findsOneWidget,
          reason: 'the later tap on গ must not replace the first answer খ');
      expect(find.text('0 of 1 correct'), findsOneWidget);

      await closePaper(tester);
    });
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_qbank/models/highschool_question.dart';
import 'package:pi_qbank/pages/cloud_tests_page.dart';

/// A bank of MCQ rows, `perChapter` questions in each chapter.
List<HighSchoolQuestion> bank({
  int chapters = 2,
  int perChapter = 3,
  List<String> options = const ['৪', '৫', '৬', '৭'],
}) {
  final out = <HighSchoolQuestion>[];
  for (var c = 1; c <= chapters; c++) {
    for (var i = 1; i <= perChapter; i++) {
      out.add(HighSchoolQuestion.fromJson({
        'id': 'c$c-q$i',
        'class': 'Class 8',
        'subject': 'গণিত',
        'chapter_number': '$c',
        'chapter_name': 'অধ্যায় $c',
        'question_type': 'MCQ',
        'stem_text': '',
        'stem_image_url': '',
        'sub_questions_json': jsonEncode({
          'text': 'Chapter $c question $i?',
          'options': options,
          'correct_ans': options[1],
        }),
        'board_year_tag': '',
        'short_mark': '',
      }));
    }
  }
  return out;
}

/// Host the picker the way the page does, capturing what it hands back.
Future<Set<String>? Function()> openPicker(
  WidgetTester tester,
  List<HighSchoolQuestion> questions, {
  Set<String> initial = const {},
}) async {
  Set<String>? result;
  var closed = false;

  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showModalBottomSheet<Set<String>>(
                context: context,
                isScrollControlled: true,
                builder: (_) => QuestionPicker(
                  questions: questions,
                  initial: initial,
                ),
              );
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  return () => closed ? result : null;
}

void main() {
  testWidgets('lists every question it was given', (tester) async {
    await openPicker(tester, bank(chapters: 1, perChapter: 3));

    expect(find.text('Chapter 1 question 1?'), findsOneWidget);
    expect(find.text('Chapter 1 question 2?'), findsOneWidget);
    expect(find.text('Chapter 1 question 3?'), findsOneWidget);
    expect(find.text('3 MCQ'), findsOneWidget);
    expect(find.text('0 selected'), findsOneWidget);
  });

  testWidgets('ticking a row marks it and numbers its place in the paper',
      (tester) async {
    await openPicker(tester, bank(chapters: 1, perChapter: 3));

    await tester.tap(find.text('Chapter 1 question 2?'));
    await tester.pumpAndSettle();

    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('Q1'), findsOneWidget,
        reason: 'the first question picked is question 1 of the paper');
  });

  testWidgets('paper positions follow bank order, not the order tapped',
      (tester) async {
    // Two students picking the same questions should get the same paper.
    await openPicker(tester, bank(chapters: 1, perChapter: 3));

    await tester.tap(find.text('Chapter 1 question 3?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chapter 1 question 1?'));
    await tester.pumpAndSettle();

    expect(find.text('2 selected'), findsOneWidget);
    expect(find.text('Q1'), findsOneWidget);
    expect(find.text('Q2'), findsOneWidget);

    // Q1 sits next to the first question, Q2 next to the third. Wiring the
    // numbers by tap order instead would put Q1 on the row tapped first.
    final firstRow = find.ancestor(
      of: find.text('Chapter 1 question 1?'),
      matching: find.byType(Container),
    );
    expect(
      find.descendant(of: firstRow.first, matching: find.text('Q1')),
      findsOneWidget,
    );
  });

  testWidgets('the search box narrows the list', (tester) async {
    await openPicker(tester, bank(chapters: 2, perChapter: 2));

    await tester.enterText(find.byType(TextField), 'Chapter 2');
    await tester.pumpAndSettle();

    expect(find.text('Chapter 2 question 1?'), findsOneWidget);
    expect(find.text('Chapter 1 question 1?'), findsNothing);
  });

  testWidgets('a chapter chip narrows the list to that chapter',
      (tester) async {
    await openPicker(tester, bank(chapters: 2, perChapter: 2));

    await tester.tap(find.text('অধ্যায় 2 · 2'));
    await tester.pumpAndSettle();

    expect(find.text('Chapter 2 question 1?'), findsOneWidget);
    expect(find.text('Chapter 1 question 1?'), findsNothing);
  });

  testWidgets(
      'Select shown takes the whole filtered list, Clear shown undoes it',
      (tester) async {
    await openPicker(tester, bank(chapters: 2, perChapter: 2));

    await tester.tap(find.text('অধ্যায় 1 · 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select shown'));
    await tester.pumpAndSettle();

    expect(find.text('2 selected'), findsOneWidget,
        reason: 'only the visible chapter, not the whole bank');

    await tester.tap(find.text('Clear shown'));
    await tester.pumpAndSettle();
    expect(find.text('0 selected'), findsOneWidget);
  });

  testWidgets('Clear all empties the selection', (tester) async {
    await openPicker(
      tester,
      bank(chapters: 1, perChapter: 3),
      initial: {'c1-q1', 'c1-q2'},
    );

    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();

    expect(find.text('0 selected'), findsOneWidget);
  });

  testWidgets('Picked only hides what is not ticked', (tester) async {
    await openPicker(
      tester,
      bank(chapters: 1, perChapter: 3),
      initial: {'c1-q2'},
    );

    await tester.tap(find.text('Picked only (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Chapter 1 question 2?'), findsOneWidget);
    expect(find.text('Chapter 1 question 1?'), findsNothing);
    expect(find.text('Chapter 1 question 3?'), findsNothing);
  });

  testWidgets('expanding a row shows the choices with the key ticked',
      (tester) async {
    await openPicker(tester, bank(chapters: 1, perChapter: 1));

    await tester.tap(find.byTooltip('Show choices'));
    await tester.pumpAndSettle();

    for (final option in ['৪', '৫', '৬', '৭']) {
      expect(find.text(option), findsOneWidget);
    }
    expect(find.byIcon(Icons.check_circle), findsOneWidget,
        reason: 'exactly one option is the key');
  });

  testWidgets('committing hands the picked set back', (tester) async {
    final result = await openPicker(tester, bank(chapters: 1, perChapter: 3));

    await tester.tap(find.text('Chapter 1 question 1?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chapter 1 question 3?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use 2'));
    await tester.pumpAndSettle();

    expect(result(), {'c1-q1', 'c1-q3'});
  });

  testWidgets('cancelling hands nothing back', (tester) async {
    final result = await openPicker(tester, bank(chapters: 1, perChapter: 3));

    await tester.tap(find.text('Chapter 1 question 1?'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();

    expect(result(), isNull, reason: 'the paper must be left as it was');
  });

  testWidgets('picking nothing can still be committed', (tester) async {
    // Otherwise there is no way to clear a selection: Clear all would disable
    // the only button that applies it.
    final result = await openPicker(
      tester,
      bank(chapters: 1, perChapter: 2),
      initial: {'c1-q1'},
    );

    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(result(), isEmpty);
  });
}

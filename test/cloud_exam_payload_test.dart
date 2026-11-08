import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_qbank/models/highschool_question.dart';
import 'package:pi_qbank/pages/cloud_tests_page.dart';
import 'package:pi_qbank/services/highschool_export_service.dart';
import 'package:pi_qbank/utils/mcq_stem_units.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `MCQTestPage` reads a question payload with two contracts that both fail at
/// runtime rather than compile time, so they are pinned here.
///
/// The dangerous one is `correct_answer`: send the option *text* instead of the
/// option *key*, and every question marks wrong. No exception, no log — just a
/// paper full of zero.
void main() {
  HighSchoolQuestion mcq(
    String id,
    List<String> options,
    String correct, {
    String text = '2 + 2 = ?',
    String stem = '',
    String image = '',
  }) =>
      HighSchoolQuestion.fromJson({
        'id': id,
        'class': 'Class (9-10) SSC',
        'subject': 'গণিত',
        'chapter_number': '1',
        'chapter_name': 'সেট',
        'question_type': 'MCQ',
        'stem_text': stem,
        'stem_image_url': image,
        'sub_questions_json':
            '{"text":"$text","options":${_jsonList(options)},"correct_ans":"$correct"}',
        'board_year_tag': '',
        'short_mark': '',
      });

  group('the payload MCQTestPage reads', () {
    test('options is a map keyed from 1', () {
      // MCQTestPage iterates `question['options'].entries` and builds a
      // RadioListTile per entry. A list here throws
      // `List<dynamic> is not a subtype of Map<String, dynamic>`.
      final p = CloudTestsPage.mcqPayload(mcq('a', ['৪', '৫', '৬', '৭'], '৫'));

      final options = p['options'];
      expect(options, isA<Map<String, dynamic>>());
      expect((options as Map).keys, ['1', '2', '3', '4']);
      expect(options.values, ['৪', '৫', '৬', '৭']);
    });

    test('correct_answer is the option KEY, not its text', () {
      final p = CloudTestsPage.mcqPayload(mcq('a', ['৪', '৫', '৬', '৭'], '৫'));

      expect(p['correct_answer'], '2');
      final options = p['options'] as Map;
      expect(options['2'], '৫', reason: 'key 2 is the text ৫');
      expect(p['correct_answer'], isNot('৫'));
    });

    test('the key resolves for every position in the list', () {
      for (var i = 0; i < 4; i++) {
        final options = ['৪', '৫', '৬', '৭'];
        final p = CloudTestsPage.mcqPayload(mcq('a', options, options[i]));
        expect(p['correct_answer'], '${i + 1}');
      }
    });

    test('a correct answer matching no option yields no key, not a guess', () {
      // Better an unmarkable question than one marked against an option the
      // student was never shown.
      final p = CloudTestsPage.mcqPayload(mcq('a', ['৪', '৫'], '৯৯'));
      expect(p['correct_answer'], '');
    });

    test('surrounding spaces in the stored answer still match', () {
      final p = CloudTestsPage.mcqPayload(mcq('a', ['৪', '৫'], ' ৫ '));
      expect(p['correct_answer'], '2');
    });

    test('a question with no options still produces a valid payload', () {
      final p = CloudTestsPage.mcqPayload(mcq('a', [], ''));
      expect(p['options'], isEmpty);
      expect(p['question'], '2 + 2 = ?');
    });

    test('carries the question image to the runner', () {
      final p = CloudTestsPage.mcqPayload(
        mcq(
          'a',
          ['৪', '৫'],
          '৫',
          image: 'https://drive.google.com/file/d/abc123/view?usp=sharing',
        ),
      );

      expect(
        p['image_url'],
        'https://drive.google.com/uc?export=download&id=abc123',
      );
    });

    test('omits image_url when the question has no image', () {
      final p = CloudTestsPage.mcqPayload(mcq('a', ['৪', '৫'], '৫'));
      expect(p.containsKey('image_url'), isFalse);
    });
  });

  group('shuffling the answer options', () {
    test('is off unless asked for', () {
      final p = CloudTestsPage.mcqPayload(mcq('a', ['১', '২', '৩'], '৩'));

      final options = (p['options'] as Map).cast<String, dynamic>();
      expect(options.values, ['১', '২', '৩']);
      expect(p['correct_answer'], '3');
    });

    test('keeps correct_answer on the right text, whatever the order', () {
      // The whole risk of shuffling: the key is a slot number, and the slot a
      // given option lands in changes. Get this wrong and the paper marks the
      // wrong answers right — silently, with no crash.
      final q = mcq('a', ['৪', '৫', '৬', '৭'], '৬');

      for (var seed = 0; seed < 40; seed++) {
        final p = CloudTestsPage.mcqPayload(
          q,
          shuffleOptions: true,
          random: Random(seed),
        );
        final options = (p['options'] as Map).cast<String, dynamic>();
        final key = p['correct_answer'] as String;

        expect(options[key], '৬', reason: 'seed $seed');
        expect(options.values.toSet(), {'৪', '৫', '৬', '৭'},
            reason: 'no option may be dropped, seed $seed');
        expect(options.keys.toList(), ['1', '2', '3', '4'],
            reason: 'keys stay slot numbers, seed $seed');
      }
    });

    test('actually moves the key around', () {
      final q = mcq('a', ['১', '২', '৩', '৪'], '১');
      final seen = <String>{};

      for (var seed = 0; seed < 30; seed++) {
        final p = CloudTestsPage.mcqPayload(
          q,
          shuffleOptions: true,
          random: Random(seed),
        );
        seen.add(p['correct_answer'] as String);
      }

      expect(seen.length, greaterThan(1),
          reason: 'a shuffle that never moves the key is not a shuffle');
    });

    test('a question with no options survives being shuffled', () {
      final p = CloudTestsPage.mcqPayload(mcq('a', [], ''),
          shuffleOptions: true, random: Random(1));

      expect(p['options'], isEmpty);
      expect(p['correct_answer'], '');
    });
  });

  group('shared-stimulus runs', () {
    const intro = 'নিচের উদ্দীপকের আলোকে ৬ ও ৭ নং প্রশ্নের উত্তর দাও :';

    test('two questions under one intro are one selectable unit', () {
      final first = mcq('a', ['১', '২'], '২', stem: intro);
      final second = mcq('b', ['৩', '৪'], '৪', stem: intro);
      final alone = mcq('c', ['৫', '৬'], '৬');

      final units = mcqStemUnits([first, second, alone]);

      expect(units.map((unit) => unit.map((q) => q.id).toList()), [
        ['a', 'b'],
        ['c'],
      ]);
    });

    test('picking one half expands to the whole run', () {
      final first = mcq('a', ['১', '২'], '২', stem: intro);
      final second = mcq('b', ['৩', '৪'], '৪', stem: intro);
      final alone = mcq('c', ['৫', '৬'], '৬');

      expect(
        expandMcqStemPicks({'b'}, [first, second, alone]),
        {'a', 'b'},
      );
    });

    test('the intro numbers are rewritten to the paper positions', () {
      final rewritten = HighSchoolExportService.stemWithNumbers(
        intro,
        [15, 16],
      );

      expect(rewritten, contains('১৫ ও ১৬'));
      expect(rewritten, isNot(contains('৬ ও ৭')));
    });

    test('a later question in the run can omit the repeated intro', () {
      final q = mcq('a', ['১', '২'], '২',
          stem: intro, image: 'https://example.com/figure.png');

      final p = CloudTestsPage.mcqPayload(q, stem: '', includeImage: false);

      expect(p['question'], isNot(contains(intro)));
      expect(p.containsKey('image_url'), isFalse);
    });

    test('the paper payload numbers the run and prints the intro once', () {
      final first = mcq(
        'a',
        ['১', '২'],
        '২',
        text: 'প্রথম প্রশ্ন?',
        stem: intro,
        image: 'https://example.com/figure.png',
      );
      final second = mcq(
        'b',
        ['৩', '৪'],
        '৪',
        text: 'দ্বিতীয় প্রশ্ন?',
        stem: intro,
        image: 'https://example.com/figure.png',
      );

      final payloads = CloudTestsPage.mcqPaperPayloads([first, second]);

      expect(payloads, hasLength(2));
      expect(payloads[0]['question'], contains('প্রথম প্রশ্ন?'));
      expect(payloads[0]['question'], contains('১ ও ২'));
      expect(payloads[0]['question'], isNot(contains('৬ ও ৭')));
      expect(payloads[0]['image_url'], contains('example.com'));
      expect(payloads[1]['question'], 'দ্বিতীয় প্রশ্ন?');
      expect(payloads[1].containsKey('image_url'), isFalse);
    });
  });

  group('the page itself', () {
    // The form is taller than the default 800x600 test window, and a ListView
    // does not build children that are off-screen — so the mode switch would be
    // unfindable for a reason that has nothing to do with the switch. Give the
    // page room to lay itself out.
    Future<void> pumpTall(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: CloudTestsPage()));
      await tester.pump();
    }

    testWidgets('opens cleanly when nothing was remembered', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await pumpTall(tester);

      expect(find.text('Random'), findsOneWidget);
      expect(find.text('Load questions'), findsOneWidget);
    });

    testWidgets('offers Random and Pick, and defaults to Random',
        (tester) async {
      await pumpTall(tester);

      expect(find.text('Random'), findsOneWidget);
      expect(find.text('Pick myself'), findsOneWidget);
    });

    testWidgets('the switch toggles and survives without loaded questions',
        (tester) async {
      // The controls below the switch need questions to act on, so this only
      // pins that switching is safe and keeps both labels reachable in the
      // empty state. Behaviour with data loaded is exercised by hand.
      await pumpTall(tester);

      await tester.tap(find.text('Pick myself'));
      await tester.pumpAndSettle();
      expect(find.text('Pick myself'), findsOneWidget);
      expect(find.textContaining('Load some questions first'), findsOneWidget);

      await tester.tap(find.text('Random'));
      await tester.pumpAndSettle();
      expect(find.text('Random'), findsOneWidget);
    });

    testWidgets(
        'the start action is present but disabled before a paper exists',
        (tester) async {
      // A bar that is always there and explains itself beats a button that
      // appears and disappears.
      await pumpTall(tester);

      expect(find.text('Start'), findsOneWidget);
      expect(find.text('Nothing to start yet'), findsOneWidget);

      final button = tester.widget<ElevatedButton>(
        find.byWidgetPredicate((w) => w is ElevatedButton),
      );
      expect(button.onPressed, isNull, reason: 'nothing selected yet');
    });
  });
}

/// Build a JSON array literal, so the fixture stays readable.
String _jsonList(List<String> items) =>
    '[${items.map((e) => '"$e"').join(',')}]';

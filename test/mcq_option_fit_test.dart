// The MCQ options of a full-width paper: all four on one line where the four
// fit, two rows of two where they do not, one per row where even two will not
// sit side by side. The PDF measures the text and the sheet measures the DOM,
// and both are held to the same rule here — a paper that lays its options out
// one way in the preview and another way on paper would be worse than either.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/models/highschool_question.dart';
import 'package:pi_qbank/services/highschool_export_service.dart';
import 'package:pi_qbank/utils/pdf_column_layout.dart';
import 'package:pi_qbank/utils/pdf_text_metrics.dart';

HighSchoolQuestion mcqWith(List<String> options) =>
    HighSchoolQuestion.fromJson({
      'id': 'mcq',
      'class': 'Class (9-10) SSC',
      'subject': 'গণিত',
      'chapter_number': '1',
      'chapter_name': 'অনুশীলনী',
      'question_type': 'MCQ',
      'stem_text': '',
      'stem_image_url': '',
      'sub_questions_json': {
        'text': 'নিচের কোনটি সঠিক?',
        'options': options,
        'correct_ans': options.first,
      },
      'board_year_tag': '',
    });

String sheetHtml({
  QuestionLayout mcqLayout = QuestionLayout.single,
  List<String> options = const ['৩', '৪', '৫', '৬'],
  McqAnswerSheetStyle answerSheet = McqAnswerSheetStyle.none,
}) =>
    HighSchoolExportService.generateHtml(
      schoolName: 'S',
      examName: 'E',
      subject: 'গণিত',
      className: 'C',
      time: 'T',
      totalMarks: '10',
      mcqLayout: mcqLayout,
      mcqAnswerSheetStyle: answerSheet,
      questions: [mcqWith(options)],
    );

/// The stylesheet of a generated paper.
String cssOf(String html) => html.split('<style>')[1].split('</style>')[0];

/// The declarations inside one CSS rule, by selector, exactly as written.
String rule(String css, String selector) {
  final match =
      RegExp('${RegExp.escape(selector)}\\s*\\{([^}]*)\\}').firstMatch(css);
  return match == null ? '' : match.group(1)!;
}

/// One declaration's value inside a rule body, or null when it is not set.
String? decl(String body, String property) {
  final match = RegExp('(?:^|;)\\s*${RegExp.escape(property)}\\s*:([^;]*)',
          multiLine: true)
      .firstMatch(body);
  return match?.group(1)?.trim();
}

void main() {
  late PdfTextMetrics m;

  setUpAll(() {
    m = PdfTextMetrics(
      banglaFontData: ByteData.sublistView(
          File('assets/fonts/SutonnyMJ Regular.ttf').readAsBytesSync()),
      symbolFontData: ByteData.sublistView(
          File('assets/fonts/MathSymbols.ttf').readAsBytesSync()),
    );
  });

  group('the PDF', () {
    // The three widths the rule turns on: what a quarter and a half of the
    // option line come to, with the gutters between the cells taken out.
    final room = PdfLayout.columnWidth(1) - PdfLayout.mcqOptionIndent;
    final quarter = (room - 3 * PdfLayout.mcqOptionGap) / 4;
    final half = (room - PdfLayout.mcqOptionGap) / 2;

    int perRow(
      List<String> options, {
      double? columnWidth,
    }) =>
        PdfLayout.mcqOptionsPerRow(
          options: options,
          columnWidth: columnWidth ?? PdfLayout.columnWidth(1),
          metrics: m,
        );

    /// How wide each option asks to be, letter and all.
    List<double> widths(List<String> options) => [
          for (var i = 0; i < options.length; i++)
            m.textWidth(PdfLayout.mcqOptionText(i, options[i]),
                fontSize: PdfLayout.bodyFontSize),
        ];

    test('the four share a line where the four of them fit', () {
      // One-word answers, which is most of what a paper asks.
      expect(perRow(const ['৩', '৪', '৫', '৬']), 4);
      expect(
          perRow(const [
            'বর্গক্ষেত্র',
            'আয়তক্ষেত্র',
            'সামান্তরিক',
            'ট্রাপিজিয়াম'
          ]),
          4);
    });

    test('an option past a quarter of the line takes two rows of two', () {
      const options = [
        'বর্গ ও আয়তক্ষেত্রের ক্ষেত্রফল',
        'রম্বস ও সামান্তরিকের ক্ষেত্রফল',
        'আয়ত ও ঘুড়ির ক্ষেত্রফল',
        'রম্বস ও ঘুড়ির ক্ষেত্রফল',
      ];

      // One of them wants more than a quarter of the line, so the four cannot
      // share it...
      expect(widths(options).reduce((a, b) => a > b ? a : b),
          greaterThan(quarter));
      // ...and every one of them fits inside half of it, so two rows of two do.
      expect(widths(options).every((w) => w <= half), isTrue);
      expect(perRow(options), 2);
    });

    test('an option past half the line takes a line of its own', () {
      const options = [
        'প্রথম উত্তরটি এতটাই লম্বা যে এক লাইনে দুটি অপশন পাশাপাশি বসতে পারবে না',
        'দ্বিতীয় উত্তরটিও প্রায় একই রকম লম্বা, তাই একা এক লাইন নেবে',
        'তৃতীয় উত্তরটি তৃতীয় অপশন হিসেবে ছোট, তবুও লাইন ভাগ করবে না',
        'চতুর্থ উত্তরটি সবচেয়ে ছোট হলেও একা এক লাইনেই ছাপা হবে',
      ];

      expect(
          widths(options).reduce((a, b) => a > b ? a : b), greaterThan(half));
      expect(perRow(options), 1);
    });

    test('a narrow column pairs up what a full-width line takes whole', () {
      // Four short words: all four fit a full-width line, but only two of them
      // fit half a page's column at a time, so the narrow block pairs them off.
      const words = [
        'বর্গক্ষেত্র',
        'আয়তক্ষেত্র',
        'সামান্তরিক',
        'ট্রাপিজিয়াম'
      ];
      expect(perRow(words), 4);
      expect(perRow(words, columnWidth: PdfLayout.columnWidth(2)), 2);

      // The answers that fit four to a line across the page — the one-word
      // options most papers use — fit four to a line in the narrow column too.
      expect(perRow(const ['৩', '৪', '৫', '৬']), 4);
      expect(
        perRow(const ['৩', '৪', '৫', '৬'],
            columnWidth: PdfLayout.columnWidth(2)),
        4,
      );

      // And answers too long for half a page still take a line each.
      expect(
        perRow(const [
          'প্রথম উত্তরটি এতটাই লম্বা যে এক লাইনে দুটি অপশন পাশাপাশি বসতে পারবে না',
          'দ্বিতীয় উত্তরটিও প্রায় একই রকম লম্বা, তাই একা এক লাইন নেবে',
          'তৃতীয় উত্তরটি তৃতীয় অপশন হিসেবে ছোট, তবুও লাইন ভাগ করবে না',
          'চতুর্থ উত্তরটি সবচেয়ে ছোট হলেও একা এক লাইনেই ছাপা হবে',
        ], columnWidth: PdfLayout.columnWidth(1)),
        1,
      );
    });

    test('the rows budgeted for are the rows the item prints', () {
      // The estimator and the item ask the same question of the same text, so
      // the number of option rows is the number of chunks either way.
      const words = [
        'বর্গক্ষেত্র',
        'আয়তক্ষেত্র',
        'সামান্তরিক',
        'ট্রাপিজিয়াম'
      ];
      int rows(List<String> options, int columns) => PdfLayout.mcqFragments(
            index: 1,
            question: mcqWith(options),
            columnWidth: PdfLayout.columnWidth(columns),
            metrics: m,
          ).length;

      // A full-width line takes the four short words whole: stem + one row.
      expect(
          rows(const [
            'বর্গক্ষেত্র',
            'আয়তক্ষেত্র',
            'সামান্তরিক',
            'ট্রাপিজিয়াম'
          ], 1),
          2);
      // The same four inside a half-page column: stem + two pairs.
      expect(rows(words, 2), 3);
      // One-word answers: stem + one row, however narrow the column.
      expect(rows(const ['৩', '৪', '৫', '৬'], 2), 2);
      // A question long enough to need a line each: the stem, then four.
      expect(
        rows(const [
          'প্রথম উত্তরটি এতটাই লম্বা যে এক লাইনে দুটি অপশন পাশাপাশি বসবে না',
          'দ্বিতীয় উত্তরটিও প্রায় একই রকম লম্বা, তাই একা এক লাইন নেবে',
          'তৃতীয় উত্তরটি তৃতীয় অপশন হিসেবে ছোট, তবুও লাইন ভাগ করবে না',
          'চতুর্থ উত্তরটি সবচেয়ে ছোট হলেও একা এক লাইনেই ছাপা হবে',
        ], 1),
        5,
      );
    });
  });

  group('the sheet', () {
    test('a full-width block asks the script to fit its options', () {
      final html = sheetHtml(mcqLayout: QuestionLayout.single);

      expect(html, contains('class="mcq-options" data-fit="1"'));
      // And the stylesheet's own answer, for a file opened with scripts off.
      expect(decl(rule(cssOf(html), '.mcq-options'), 'grid-template-columns'),
          '1fr 1fr');
    });

    test('a two-column block is fitted too, from its own narrow width', () {
      final html = sheetHtml(mcqLayout: QuestionLayout.doubleColumn);

      // The script measures whatever room the list actually has, so a block
      // inside a half-page column is fitted the same way — it is the stylesheet
      // fallback that differs, because one per row is all that is safe there
      // without measuring.
      expect(html, contains('class="mcq-options" data-fit="1"'));
      expect(decl(rule(cssOf(html), '.mcq-options'), 'grid-template-columns'),
          '1fr');
    });

    test('a three-column MCQ block is emitted for compact papers', () {
      final html = sheetHtml(mcqLayout: QuestionLayout.tripleColumn);

      expect(html, contains('column-count: 3'));
    });

    test('the script tries four, then two, then one', () {
      final script = sheetHtml(mcqLayout: QuestionLayout.single)
          .split('<script>')[1]
          .split('</script>')[0];

      expect(script, contains("'.mcq-options[data-fit]'"));
      expect(script, contains('var counts = [4, 2, 1]'));
      expect(script, contains("'repeat(' + count + ', 1fr)'"));
    });

    test('the options are fitted before the two-set heights are measured', () {
      final script = sheetHtml().split('<script>')[1].split('</script>')[0];

      // The fit decides how tall a set is, and the decision below measures that
      // height — the other way round and the pair would be split on a height
      // neither set has.
      expect(script.indexOf('fitOptions();'),
          lessThan(script.indexOf('decide();')));
    });

    test('the optional OMR answer sheet matches the selected style', () {
      final html = sheetHtml(answerSheet: McqAnswerSheetStyle.omr);

      expect(html, contains('class="mcq-answer-sheet"'));
      expect(html, contains('class="omr-bubble">ক</span>'));
      expect(html, contains('class="omr-bubble">ঘ</span>'));
      // Both variants ship so the preview can switch styles in place; only
      // the chosen one is visible on load.
      expect(html, contains('data-answer-style="omr" style=""'));
      expect(html,
          contains('data-answer-style="serialAnswer" style="display:none;"'));
    });

    test('the optional serial answer sheet uses repeated number-answer pairs',
        () {
      final html = sheetHtml(answerSheet: McqAnswerSheetStyle.serialAnswer);

      expect(html, contains('class="serial-answer-table"'));
      expect(
          html,
          contains(
              '<tr><th>1</th></tr><tr class="serial-answer-row"><td></td></tr>'));
      expect(html, contains('data-answer-style="serialAnswer" style=""'));
      expect(html, contains('data-answer-style="omr" style="display:none;"'));
    });

    test('a manual serial sheet is filled before the script runs', () {
      final html = HighSchoolExportService.generateHtml(
        schoolName: 'S',
        examName: 'E',
        subject: 'গণিত',
        className: 'C',
        time: 'T',
        totalMarks: '10',
        mcqAnswerSheetStyle: McqAnswerSheetStyle.serialAnswer,
        manualAnswerCount: 3,
        questions: const [],
      );

      expect(html, contains('data-manual-answer-sheet="true"'));
      expect(
        html,
        contains('<tr><th>1</th><th>2</th><th>3</th></tr>'
            '<tr class="serial-answer-row"><td></td><td></td><td></td></tr>'),
      );
      // The chosen variant is visible in the markup itself: the Android
      // preview and the exported file both open with the style pre-selected
      // and never fire the browser toolbar's change event.
      expect(html, contains('data-answer-style="serialAnswer" style=""'));
      expect(html, contains('data-answer-style="omr" style="display:none;"'));
    });
  });
}

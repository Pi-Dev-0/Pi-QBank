// Guards for the HTML export: a paper printed as two sets (ক / খ) must come out
// as two papers in one file, each carrying only its own questions, and the
// বাংলা letter a block is headed with must follow its position rather than its
// type.
import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/models/highschool_question.dart';
import 'package:pi_qbank/services/highschool_export_service.dart';

HighSchoolQuestion cqTest(String stem) => HighSchoolQuestion.fromJson({
      'id': stem,
      'class': 'Class (9-10) SSC',
      'subject': 'গণিত',
      'chapter_number': '1',
      'chapter_name': 'অনুশীলনী',
      'question_type': 'CQ',
      'stem_text': stem,
      'stem_image_url': '',
      'sub_questions_json': [
        {'label': 'ক', 'mark': 2, 'text': 'সমাধান করো।'},
      ],
      'board_year_tag': '',
    });

HighSchoolQuestion rqTest(String text) => HighSchoolQuestion.fromJson({
      'id': text,
      'class': 'Class (9-10) SSC',
      'subject': 'গণিত',
      'chapter_number': '1',
      'chapter_name': 'অনুশীলনী',
      'question_type': 'RQ',
      'stem_text': text,
      'stem_image_url': '',
      'sub_questions_json': <Object>[],
      'board_year_tag': '',
      'short_mark': 1,
    });

HighSchoolQuestion mcqTest(String text) => HighSchoolQuestion.fromJson({
      'id': text,
      'class': 'Class (9-10) SSC',
      'subject': 'গণিত',
      'chapter_number': '1',
      'chapter_name': 'অনুশীলনী',
      'question_type': 'MCQ',
      'stem_text': '',
      'stem_image_url': '',
      'sub_questions_json': {
        'text': text,
        'options': ['৪', '৫', '৬', '৭'],
        'correct_ans': '৫',
      },
      'board_year_tag': '',
    });

String generate(
  List<HighSchoolQuestion> questions, {
  List<String> setLabels = const [],
  List<PaperSection> sectionOrder = PaperSection.defaultOrder,
  QuestionLayout cqLayout = QuestionLayout.single,
  QuestionLayout rqLayout = QuestionLayout.single,
  QuestionLayout mcqLayout = QuestionLayout.doubleColumn,
}) =>
    HighSchoolExportService.generateHtml(
      schoolName: 'S',
      examName: 'E',
      subject: 'গণিত',
      className: 'C',
      time: 'T',
      totalMarks: '10',
      questions: questions,
      setLabels: setLabels,
      sectionOrder: sectionOrder,
      cqLayout: cqLayout,
      rqLayout: rqLayout,
      mcqLayout: mcqLayout,
    );

/// One entry per printed sheet, in the order they appear.
List<String> sheets(String html) =>
    html.split('<div class="paper-sheet">').skip(1).toList();

/// One entry per set inside the sheet, in the order they appear.
///
/// Every set is written into the one sheet; whether the sets stay together or
/// the second is moved onto a sheet of its own is decided in the browser, by
/// what fits on an A4 page. See the script the export writes.
List<String> sets(String html) =>
    html.split('<div class="paper-set">').skip(1).toList();

/// The section declarations of [sheet], top to bottom.
///
/// `in-flow` marks the ones laid out inside the block's own columns, so the
/// class has to be allowed for.
List<String> banners(String sheet) => RegExp(
      '<div class="section-banner[^"]*">([^<]*)</div>',
    ).allMatches(sheet).map((m) => m.group(1)!).toList();

/// The markup inside the merged CQ + short-question flow, or '' when the sheet
/// has no merged flow.
String flowOf(String sheet) {
  const marker = '<div class="flow-grid">';
  final at = sheet.indexOf(marker);
  if (at < 0) return '';
  final rest = sheet.substring(at + marker.length);
  final next = RegExp(r'\n\s*<div class="(cq|mcq|rq)-grid">').firstMatch(rest);
  return next == null ? rest : rest.substring(0, next.start);
}

int occurrences(String haystack, String needle) =>
    needle.allMatches(haystack).length;

/// The markup without the hover tooltips, which carry a question's id rather
/// than anything the paper prints.
///
/// These tests ask "how many times is this text on the paper?", so an id that
/// happens to read like the question must not be counted as a second copy.
String withoutTooltips(String html) =>
    html.replaceAll(RegExp(r'\s*title="[^"]*"'), '');

void main() {
  group('two sets', () {
    test('share one sheet, each with only its own questions', () {
      final a = cqTest('সেট-ক-এর প্রশ্ন')..setLabel = 'ক';
      final b = cqTest('সেট-খ-এর প্রশ্ন')..setLabel = 'খ';

      final html = generate([a, b], setLabels: const ['ক', 'খ']);

      // Both sets go into the one sheet in the markup, divided by a rule. The
      // browser splits them onto a page each when the pair does not fit.
      expect(sheets(html).length, 1);
      expect(html, contains('<div class="set-divider"></div>'));

      final printed = sets(html);
      expect(printed.length, 2);
      expect(printed[0], contains('সেট: ক'));
      expect(printed[0], contains('সেট-ক-এর প্রশ্ন'));
      expect(printed[0], isNot(contains('সেট-খ-এর প্রশ্ন')));
      expect(printed[1], contains('সেট: খ'));
      expect(printed[1], contains('সেট-খ-এর প্রশ্ন'));
      expect(printed[1], isNot(contains('সেট-ক-এর প্রশ্ন')));

      // The reported bug: one masthead and the questions of both sets merged
      // into a single paper, so each question appeared twice.
      expect(occurrences(withoutTooltips(html), 'সেট-ক-এর প্রশ্ন'), 1);
      expect(occurrences(withoutTooltips(html), 'সেট-খ-এর প্রশ্ন'), 1);
    });

    test('number each set from one', () {
      final questions = [
        cqTest('ক-এক')..setLabel = 'ক',
        cqTest('খ-এক')..setLabel = 'খ',
        cqTest('ক-দুই')..setLabel = 'ক',
      ];

      final printed = sets(generate(questions, setLabels: const ['ক', 'খ']));

      expect(printed[0], contains('<b>1.</b> ক-এক'));
      expect(printed[0], contains('<b>2.</b> ক-দুই'));
      expect(printed[1], contains('<b>1.</b> খ-এক'));
    });

    test('a question filed into no set is printed in both', () {
      final filed = cqTest('ক-এর প্রশ্ন')..setLabel = 'ক';
      final loose = cqTest('কোথাও নেই');

      final printed =
          sets(generate([filed, loose], setLabels: const ['ক', 'খ']));

      expect(printed[0], contains('কোথাও নেই'));
      expect(printed[1], contains('কোথাও নেই'));
    });

    test('a single-set paper stays one set with no set name and no divider',
        () {
      final html = generate([cqTest('একমাত্র প্রশ্ন')]);

      expect(sheets(html).length, 1);
      expect(sets(html).length, 1);
      expect(sets(html).single, isNot(contains('সেট:')));
      // The marker only exists between two sets: the script mentions the class,
      // the markup must not.
      expect(sheets(html).single.split('<script>').first,
          isNot(contains('set-divider')));
    });

    test('a blank set label counts as a single set', () {
      final html = generate([cqTest('প্রশ্ন')], setLabels: const ['']);

      expect(sheets(html).length, 1);
      expect(sets(html).length, 1);
      expect(sets(html).single, isNot(contains('সেট:')));
    });

    test('the split between sets is decided by what fits, not in the markup',
        () {
      final html = generate(
        [cqTest('ক')..setLabel = 'ক', cqTest('খ')..setLabel = 'খ'],
        setLabels: const ['ক', 'খ'],
      );

      // The script measures the pair against a page and moves the second set
      // out when it does not fit; the printer then page-breaks between sheets.
      expect(html, contains('297mm'));
      expect(html, contains("querySelectorAll(':scope > .paper-set')"));
      expect(html, contains('break-before: page'));

      // A pair that does fit keeps the page's leftover space between the sets,
      // so the second one ends at the foot of the page.
      expect(html, contains('divider.style.marginTop'));
      expect(html, contains('divider.style.marginBottom'));
    });
  });

  group('section letters', () {
    test('follow the reader order, not the question type', () {
      final html = generate(
        [cqTest('একটি CQ'), mcqTest('একটি MCQ'), rqTest('একটি SQ')],
        sectionOrder: const [
          PaperSection.mcq,
          PaperSection.cq,
          PaperSection.rq,
        ],
      );

      expect(banners(sheets(html).single), [
        'ক-বিভাগ: বহুনির্বাচনী প্রশ্ন (MCQ)',
        'খ-বিভাগ: সৃজনশীল প্রশ্ন (CQ)',
        'গ-বিভাগ: সংক্ষিপ্ত প্রশ্ন (SQ)',
      ]);
    });

    test('default to CQ, then the short questions, then MCQ', () {
      final html =
          generate([cqTest('একটি CQ'), mcqTest('একটি MCQ'), rqTest('একটি SQ')]);

      expect(banners(sheets(html).single), [
        'ক-বিভাগ: সৃজনশীল প্রশ্ন (CQ)',
        'খ-বিভাগ: সংক্ষিপ্ত প্রশ্ন (SQ)',
        'গ-বিভাগ: বহুনির্বাচনী প্রশ্ন (MCQ)',
      ]);
    });

    test('a block that is empty in one set keeps its letter in the other', () {
      final withMcq = cqTest('ক-এর CQ')..setLabel = 'ক';
      final onlyShort = rqTest('খ-এর SQ')..setLabel = 'খ';
      final alsoMcq = mcqTest('খ-এর MCQ')..setLabel = 'খ';
      final mcq = mcqTest('ক-এর MCQ')..setLabel = 'ক';

      final printed = sets(generate([withMcq, onlyShort, alsoMcq, mcq],
          setLabels: const ['ক', 'খ']));

      // ক has no short questions, so that block is skipped here — but the MCQ
      // block is still গ-বিভাগ, not খ: its letter comes from the paper's blocks,
      // not from what this one set happens to contain.
      expect(banners(printed[0]), [
        'ক-বিভাগ: সৃজনশীল প্রশ্ন (CQ)',
        'গ-বিভাগ: বহুনির্বাচনী প্রশ্ন (MCQ)',
      ]);
      // খ holds short questions and MCQs, so both are declared — and the MCQs
      // are গ-বিভাগ here too.
      expect(banners(printed[1]), [
        'খ-বিভাগ: সংক্ষিপ্ত প্রশ্ন (SQ)',
        'গ-বিভাগ: বহুনির্বাচনী প্রশ্ন (MCQ)',
      ]);
    });
  });

  group('two-column blocks', () {
    /// CQ and SQ in two columns, one question of each plus an MCQ.
    List<HighSchoolQuestion> mixed() =>
        [cqTest('একটি CQ'), rqTest('একটি SQ'), mcqTest('একটি MCQ')];

    test(
        'CQ and the short questions share one flow while they are next to '
        'each other', () {
      final sheet = sheets(generate(
        mixed(),
        cqLayout: QuestionLayout.doubleColumn,
        rqLayout: QuestionLayout.doubleColumn,
      )).single;

      final flow = flowOf(sheet);
      expect(flow, isNotEmpty);

      // Both declarations and both question types are inside the *one* flow, in
      // reading order: the short questions begin where the CQ run out.
      expect(flow.indexOf('সৃজনশীল প্রশ্ন (CQ)'),
          lessThan(flow.indexOf('cq-card')));
      expect(flow.indexOf('cq-card'),
          lessThan(flow.indexOf('সংক্ষিপ্ত প্রশ্ন (SQ)')));
      expect(flow.indexOf('সংক্ষিপ্ত প্রশ্ন (SQ)'),
          lessThan(flow.indexOf('rq-item')));

      // MCQ never joins the flow - it keeps a fresh pair of columns.
      expect(flow, isNot(contains('mcq-card')));
      expect(sheet, contains('<div class="mcq-grid">'));
    });

    test('the order inside the flow follows the reader', () {
      final sheet = sheets(generate(
        mixed(),
        cqLayout: QuestionLayout.doubleColumn,
        rqLayout: QuestionLayout.doubleColumn,
        sectionOrder: const [
          PaperSection.rq,
          PaperSection.cq,
          PaperSection.mcq,
        ],
      )).single;

      final flow = flowOf(sheet);
      // The short questions were put first, so they open the flow and the CQ
      // part begins where they end.
      expect(flow.indexOf('সংক্ষিপ্ত প্রশ্ন (SQ)'),
          lessThan(flow.indexOf('rq-item')));
      expect(flow.indexOf('rq-item'), lessThan(flow.indexOf('cq-card')));
    });

    test('a pair separated by another block does not merge', () {
      final sheet = sheets(generate(
        mixed(),
        cqLayout: QuestionLayout.doubleColumn,
        rqLayout: QuestionLayout.doubleColumn,
        sectionOrder: const [
          PaperSection.cq,
          PaperSection.mcq,
          PaperSection.rq,
        ],
      )).single;

      expect(flowOf(sheet), isEmpty);
      expect(sheet, contains('<div class="cq-grid">'));
      expect(sheet, contains('<div class="mcq-grid">'));
      expect(sheet, contains('<div class="rq-grid">'));
    });

    test('a single-column pair stays two blocks', () {
      final sheet = sheets(generate(mixed())).single;

      expect(flowOf(sheet), isEmpty);
      expect(sheet, contains('<div class="cq-grid">'));
      expect(sheet, contains('<div class="rq-grid">'));
    });

    test('a two-column block declares itself inside its first column', () {
      // Two blocks, so the sheet has something to declare — a sheet of one type
      // prints no declaration at all. The MCQ block is in its own columns too,
      // so neither bar sits across the page.
      final sheet = sheets(generate([cqTest('একটি CQ'), mcqTest('একটি MCQ')],
              cqLayout: QuestionLayout.doubleColumn))
          .single;

      // The declaration is the grid's own first child - one column wide - not a
      // bar across the page above it.
      expect(
          sheet,
          matches(RegExp('<div class="cq-grid">\\s*'
              '<div class="section-banner in-flow">ক-বিভাগ[^<]*</div>')));
      expect(sheet, isNot(contains('<div class="section-banner">')));
    });

    test('a single-column block declares itself across the page', () {
      // Two single-column blocks: each bar spans the page, above its own block.
      final sheet =
          sheets(generate([cqTest('একটি CQ'), rqTest('একটি SQ')])).single;

      expect(
          sheet,
          matches(RegExp('<div class="section-banner">ক-বিভাগ[^<]*</div>\\s*'
              '<div class="cq-grid">')));
      expect(sheet, isNot(contains('in-flow')));
    });

    test('MCQ declares itself inside its columns too, but starts a fresh pair',
        () {
      final sheet = sheets(generate(mixed())).single;

      expect(
          sheet,
          matches(RegExp('<div class="mcq-grid">\\s*'
              '<div class="section-banner in-flow">গ-বিভাগ[^<]*</div>')));
    });
  });
}

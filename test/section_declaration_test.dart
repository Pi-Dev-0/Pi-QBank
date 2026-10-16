// A sheet that holds one type of question has nothing to tell apart, so its lone
// declaration — «ক-বিভাগ: বহুনির্বাচনী প্রশ্ন (MCQ)» — is dropped and the
// questions print on their own. The instruction line under the bar stays: it is a
// directive, not a label. Every writer reads the rule off its own set, and so
// does the PDF, so a one-type paper looks the same in all five exports.
//
// The author's own line breaks are locked down here as well: a question typed
// over several lines prints over several lines in the browser and in Word, which
// is what the PDF has always done on its own.
import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/models/highschool_question.dart';
import 'package:pi_qbank/services/highschool_export_service.dart';
import 'package:pi_qbank/utils/pdf_mixed_text.dart';

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

String htmlOf(
  List<HighSchoolQuestion> questions, {
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
      cqLayout: cqLayout,
      rqLayout: rqLayout,
      mcqLayout: mcqLayout,
    );

String wordOf(List<HighSchoolQuestion> questions) =>
    HighSchoolExportService.generateWordDoc(
      schoolName: 'S',
      examName: 'E',
      subject: 'গণিত',
      className: 'C',
      time: 'T',
      totalMarks: '10',
      questions: questions,
    );

String textOf(List<HighSchoolQuestion> questions) =>
    HighSchoolExportService.generatePlainText(
      schoolName: 'S',
      examName: 'E',
      subject: 'গণিত',
      className: 'C',
      time: 'T',
      totalMarks: '10',
      questions: questions,
    );

String markdownOf(List<HighSchoolQuestion> questions) =>
    HighSchoolExportService.generateMarkdown(
      schoolName: 'S',
      examName: 'E',
      subject: 'গণিত',
      className: 'C',
      time: 'T',
      totalMarks: '10',
      questions: questions,
    );

/// The sheet, without the styles the head of the file carries.
String bodyOf(String html) => html.split('<body>').last;

/// One entry per printed sheet, in the order they appear.
List<String> sets(String html) =>
    html.split('<div class="paper-set">').skip(1).toList();

void main() {
  group('one type of question declares nothing', () {
    test('the MCQ bar is dropped in the browser', () {
      final body =
          bodyOf(htmlOf([mcqTest('প্রশ্ন এক'), mcqTest('প্রশ্ন দুই')]));

      // In the block's own columns the grid already carries the gap above it,
      // so the bar leaves nothing behind at all.
      expect(body, isNot(contains('section-banner')));
      expect(body, isNot(contains('বিভাগ')));

      // Full width there is no grid margin to carry that gap, so the bar's top
      // margin is left behind as a bare spacer: the block does not start flush
      // against the masthead.
      final oneColumn =
          htmlOf([mcqTest('প্রশ্ন এক')], mcqLayout: QuestionLayout.single);
      expect(bodyOf(oneColumn), isNot(contains('section-banner')));
      expect(bodyOf(oneColumn), isNot(contains('বিভাগ')));
      expect(bodyOf(oneColumn), contains('class="section-gap"'));
      // And the spacer is styled, so it really is the air the bar took.
      expect(oneColumn, contains('.section-gap'));
    });

    test('the same goes for a CQ-only and a short-question-only sheet', () {
      for (final questions in [
        [cqTest('প্রশ্ন এক')],
        [rqTest('প্রশ্ন এক'), rqTest('প্রশ্ন দুই')],
      ]) {
        expect(bodyOf(htmlOf(questions)), isNot(contains('বিভাগ')));
      }
    });

    test('Word drops it too, keeping the directive under it', () {
      final word = wordOf([mcqTest('প্রশ্ন এক')]);

      expect(word, isNot(contains('<div class="section-title">')));
      expect(word, isNot(contains('বিভাগ')));
      expect(word, contains('[সঠিক উত্তরের পাশে টিক (✓) চিহ্ন দাও]'));
    });

    test('the text and markdown exports drop it as well', () {
      final questions = [mcqTest('প্রশ্ন এক')];

      expect(textOf(questions), isNot(contains('বিভাগ')));
      expect(markdownOf(questions), isNot(contains('বিভাগ')));
      // A sheet holding two types still declares them, and a block still
      // separates itself from the one before it.
      expect(textOf([...questions, rqTest('সংক্ষিপ্ত')]), contains('বিভাগ'));
    });
  });

  group('more than one type still declares them', () {
    test('the browser keeps the bars and their letters', () {
      final body = bodyOf(htmlOf([mcqTest('প্রশ্ন'), rqTest('সংক্ষিপ্ত')]));

      // The letters come from the paper's blocks, in the reader's order: the
      // short questions are the first block the sheet prints, so they are ক,
      // and the MCQs under them are খ.
      expect(body, contains('ক-বিভাগ: সংক্ষিপ্ত প্রশ্ন (SQ)'));
      expect(body, contains('খ-বিভাগ: বহুনির্বাচনী প্রশ্ন (MCQ)'));
      expect(body, isNot(contains('class="section-gap"')));
    });

    test('the rule is read off each set, not off the paper', () {
      // Set ক holds two types and declares both; set খ holds nothing but MCQs
      // and declares nothing. The letters still come from the paper's blocks.
      final questions = [
        cqTest('ক-এর সৃজনশীল')..setLabel = 'ক',
        rqTest('ক-এর সংক্ষিপ্ত')..setLabel = 'ক',
        mcqTest('খ-এর বহুনির্বাচনী')..setLabel = 'খ',
      ];

      final printed = sets(HighSchoolExportService.generateHtml(
        schoolName: 'S',
        examName: 'E',
        subject: 'গণিত',
        className: 'C',
        time: 'T',
        totalMarks: '10',
        questions: questions,
        setLabels: const ['ক', 'খ'],
      ));

      expect(printed, hasLength(2));
      expect(printed[0], contains('ক-বিভাগ: সৃজনশীল প্রশ্ন (CQ)'));
      expect(printed[0], contains('খ-বিভাগ: সংক্ষিপ্ত প্রশ্ন (SQ)'));
      expect(printed[1], isNot(contains('section-banner')));
      expect(printed[1], isNot(contains('বিভাগ')));
    });
  });

  group('the author\'s own line breaks', () {
    const multiline = 'প্রতিষ্ঠানটির সাফল্য দেশে—\n'
        'i. অর্থনৈতিক উন্নয়ন হবে\n'
        'ii. জীববৈচিত্র্য সৃষ্টির পথ সুগম হবে\n'
        'নিচের কোনটি সঠিক?';

    test('the browser is given a <br> where the line was broken', () {
      final body = bodyOf(htmlOf([mcqTest(multiline)]));

      expect(body, contains('i. অর্থনৈতিক উন্নয়ন হবে<br>ii. জীববৈচিত্র্য'));
      expect(body, contains('সুগম হবে<br>নিচের কোনটি সঠিক?'));
      // The break is markup, never a visible escape or a lost space.
      expect(body, isNot(contains(r'\n')));
    });

    test('Word reads the same markup', () {
      expect(
          wordOf([mcqTest(multiline)]),
          contains(
              'i. অর্থনৈতিক উন্নয়ন হবে<br>ii. জীববৈচিত্র্য সৃষ্টির পথ সুগম হবে'));
    });

    test('a CQ stem and its sub-question break the same way', () {
      final q = HighSchoolQuestion.fromJson({
        'id': 'cq',
        'class': 'Class (9-10) SSC',
        'subject': 'গণিত',
        'chapter_number': '1',
        'chapter_name': 'অনুশীলনী',
        'question_type': 'CQ',
        'stem_text': 'উদ্দীপক প্রথম লাইন\nউদ্দীপক দ্বিতীয় লাইন',
        'stem_image_url': '',
        'sub_questions_json': [
          {'label': 'ক', 'mark': 2, 'text': 'প্রথম অংশ\nদ্বিতীয় অংশ'},
        ],
        'board_year_tag': '',
      });
      final body = bodyOf(htmlOf([q]));

      expect(body, contains('উদ্দীপক প্রথম লাইন<br>উদ্দীপক দ্বিতীয় লাইন'));
      expect(body, contains('প্রথম অংশ<br>দ্বিতীয় অংশ'));
    });

    test('a short question breaks the same way', () {
      final body = bodyOf(htmlOf([rqTest('প্রথম অংশ\nদ্বিতীয় অংশ')]));

      expect(body, contains('প্রথম অংশ<br>দ্বিতীয় অংশ'));
    });

    test('the text and markdown exports keep the breaks as they are', () {
      // Both are line-oriented already, so the newline is the break.
      expect(
          textOf([mcqTest(multiline)]), contains('i. অর্থনৈতিক উন্নয়ন হবে'));
      expect(textOf([mcqTest(multiline)]),
          contains('ii. জীববৈচিত্র্য সৃষ্টির পথ সুগম হবে'));
      expect(markdownOf([rqTest('প্রথম অংশ\nদ্বিতীয় অংশ')]),
          contains('প্রথম অংশ\nদ্বিতীয় অংশ'));
    });

    test('the PDF pipeline has always kept the break', () {
      // The pdf package breaks a span on '\n' by itself, which is why only the
      // HTML and Word writers needed the markup: the runs the renderer is handed
      // still carry the newline.
      final runs = splitPdfTextRuns(multiline);
      final joined = runs.map((r) => r.text).join();

      expect('\n'.allMatches(joined), hasLength(3));
    });
  });
}

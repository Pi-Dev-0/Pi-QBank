// Guards for the exports that are not the sheet or the PDF: Word, Markdown and
// plain text. All three print a two-set paper the way the PDF does — two papers
// in one file, each with only its own questions — and all three letter a block
// by its position in the paper rather than by its question type.
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

List<String> _labels(bool twoSets) => twoSets ? const ['ক', 'খ'] : const [];

String text(
  List<HighSchoolQuestion> questions, {
  bool twoSets = false,
  List<PaperSection> sectionOrder = PaperSection.defaultOrder,
}) =>
    HighSchoolExportService.generatePlainText(
      schoolName: 'S',
      examName: 'E',
      subject: 'গণিত',
      className: 'C',
      time: 'T',
      totalMarks: '10',
      questions: questions,
      setLabels: _labels(twoSets),
      sectionOrder: sectionOrder,
    );

String markdown(
  List<HighSchoolQuestion> questions, {
  bool twoSets = false,
  List<PaperSection> sectionOrder = PaperSection.defaultOrder,
}) =>
    HighSchoolExportService.generateMarkdown(
      schoolName: 'S',
      examName: 'E',
      subject: 'গণিত',
      className: 'C',
      time: 'T',
      totalMarks: '10',
      questions: questions,
      setLabels: _labels(twoSets),
      sectionOrder: sectionOrder,
    );

String word(
  List<HighSchoolQuestion> questions, {
  bool twoSets = false,
  List<PaperSection> sectionOrder = PaperSection.defaultOrder,
}) =>
    HighSchoolExportService.generateWordDoc(
      schoolName: 'S',
      examName: 'E',
      subject: 'গণিত',
      className: 'C',
      time: 'T',
      totalMarks: '10',
      questions: questions,
      setLabels: _labels(twoSets),
      sectionOrder: sectionOrder,
    );

int occurrences(String haystack, String needle) =>
    needle.allMatches(haystack).length;

void main() {
  group('a set with no questions of its own', () {
    test('prints the whole paper, with its MCQs in another order', () {
      // The "সব প্রশ্ন প্রথম সেটে" case: every question is filed into the first
      // set, so the second one would print a blank sheet. It prints the paper
      // instead — the same questions in the same order, with the MCQs moved so
      // the two papers do not have the answers in the same places.
      final questions = [
        cqTest('সি-এক')..setLabel = 'ক',
        cqTest('সি-দুই')..setLabel = 'ক',
        mcqTest('এম-এক')..setLabel = 'ক',
        mcqTest('এম-দুই')..setLabel = 'ক',
        mcqTest('এম-তিন')..setLabel = 'ক',
      ];

      List<HighSchoolQuestion> set(int i) =>
          HighSchoolExportService.questionsForSet(
              questions, const ['ক', 'খ'], i);

      final first = set(0);
      final second = set(1);

      expect(first.length, questions.length);
      expect(second.length, questions.length);
      expect(first.map((q) => q.id).toSet(), second.map((q) => q.id).toSet());

      // Everything but the MCQs keeps the order it was selected in.
      expect([
        for (final q in first)
          if (!q.isMcq) q.id
      ], [
        for (final q in second)
          if (!q.isMcq) q.id
      ]);

      expect(
        [
          for (final q in second)
            if (q.isMcq) q.id
        ],
        isNot([
          for (final q in first)
            if (q.isMcq) q.id
        ]),
      );
    });

    test('a set with questions of its own keeps only those', () {
      final questions = [
        cqTest('ক-এর')..setLabel = 'ক',
        cqTest('খ-এর')..setLabel = 'খ',
      ];

      expect(
        HighSchoolExportService.questionsForSet(questions, const ['ক', 'খ'], 1)
            .map((q) => q.id),
        ['খ-এর'],
      );
    });

    test('an unfiled question is still printed in both sets', () {
      final questions = [cqTest('সবার')];

      for (final i in [0, 1]) {
        expect(
          HighSchoolExportService.questionsForSet(
                  questions, const ['ক', 'খ'], i)
              .length,
          1,
        );
      }
    });
  });

  group('plain text', () {
    test('prints a paper per set, each with only its own questions', () {
      final questions = [
        cqTest('ক-এর প্রশ্ন')..setLabel = 'ক',
        cqTest('খ-এর প্রশ্ন')..setLabel = 'খ',
      ];

      final oneSet = text(questions);
      expect(occurrences(oneSet, 'সেট:'), 0);
      expect(occurrences(oneSet, 'ক-এর প্রশ্ন'), 1);
      expect(occurrences(oneSet, 'খ-এর প্রশ্ন'), 1);

      final twoSets = text(questions, twoSets: true);
      expect(twoSets, contains('সেট: ক'));
      expect(twoSets, contains('সেট: খ'));

      // Each paper carries its own question and not the other set's.
      final papers = twoSets.split('সেট: ');
      expect(papers.length, 3); // masthead + two papers
      expect(papers[1], contains('ক-এর প্রশ্ন'));
      expect(papers[1], isNot(contains('খ-এর প্রশ্ন')));
      expect(papers[2], contains('খ-এর প্রশ্ন'));
      expect(papers[2], isNot(contains('ক-এর প্রশ্ন')));
    });

    test('prints an unfiled question in both sets', () {
      final questions = [
        cqTest('ক-এর প্রশ্ন')..setLabel = 'ক',
        cqTest('খ-এর প্রশ্ন')..setLabel = 'খ',
        cqTest('কোথাও নেই'),
      ];

      expect(occurrences(text(questions, twoSets: true), 'কোথাও নেই'), 2);
    });

    test('letters a block by its position, not its type', () {
      final questions = [
        cqTest('সি-কিউ'),
        rqTest('এস-কিউ'),
        mcqTest('এম-সি-কিউ')
      ];

      final ordered = text(
        questions,
        sectionOrder: const [
          PaperSection.rq,
          PaperSection.cq,
          PaperSection.mcq
        ],
      );

      expect(ordered, contains('ক-বিভাগ: সংক্ষিপ্ত প্রশ্ন (SQ)'));
      expect(ordered, contains('খ-বিভাগ: সৃজনশীল প্রশ্ন (CQ)'));
      expect(ordered, contains('গ-বিভাগ: বহুনির্বাচনী প্রশ্ন (MCQ)'));

      // The short questions were dragged to the top, so they print first.
      expect(
        ordered.indexOf('ক-বিভাগ: সংক্ষিপ্ত প্রশ্ন (SQ)'),
        lessThan(ordered.indexOf('খ-বিভাগ: সৃজনশীল প্রশ্ন (CQ)')),
      );
    });
  });

  group('markdown', () {
    test('prints a paper per set, each with only its own questions', () {
      final questions = [
        cqTest('ক-এর প্রশ্ন')..setLabel = 'ক',
        cqTest('খ-এর প্রশ্ন')..setLabel = 'খ',
      ];

      final twoSets = markdown(questions, twoSets: true);
      expect(occurrences(twoSets, '# S'), 2);
      expect(twoSets, contains('**সেট:** ক'));
      expect(twoSets, contains('**সেট:** খ'));
      expect(occurrences(twoSets, 'ক-এর প্রশ্ন'), 1);
      expect(occurrences(twoSets, 'খ-এর প্রশ্ন'), 1);
    });

    test('letters a block by its position, not its type', () {
      final ordered = markdown(
        [cqTest('সি-কিউ'), rqTest('এস-কিউ')],
        sectionOrder: const [PaperSection.rq, PaperSection.cq],
      );

      expect(ordered, contains('### ক-বিভাগ: সংক্ষিপ্ত প্রশ্ন (SQ)'));
      expect(ordered, contains('### খ-বিভাগ: সৃজনশীল প্রশ্ন (CQ)'));
    });
  });

  group('word', () {
    test('starts each set on a page of its own', () {
      final questions = [
        cqTest('ক-এর প্রশ্ন')..setLabel = 'ক',
        cqTest('খ-এর প্রশ্ন')..setLabel = 'খ',
      ];

      final doc = word(questions, twoSets: true);
      expect(occurrences(doc, 'class="header-table"'), 2);
      expect(occurrences(doc, 'page-break-before:always'), 1);
      expect(doc, contains('সেট: ক'));
      expect(doc, contains('সেট: খ'));
      expect(occurrences(doc, 'ক-এর প্রশ্ন'), 1);
      expect(occurrences(doc, 'খ-এর প্রশ্ন'), 1);
    });

    test('letters a block by its position, not its type', () {
      final ordered = word(
        [cqTest('সি-কিউ'), rqTest('এস-কিউ')],
        sectionOrder: const [PaperSection.rq, PaperSection.cq],
      );

      expect(ordered, contains('ক-বিভাগ: সংক্ষিপ্ত প্রশ্ন (SQ)'));
      expect(ordered, contains('খ-বিভাগ: সৃজনশীল প্রশ্ন (CQ)'));
      expect(
        ordered.indexOf('ক-বিভাগ: সংক্ষিপ্ত প্রশ্ন (SQ)'),
        lessThan(ordered.indexOf('খ-বিভাগ: সৃজনশীল প্রশ্ন (CQ)')),
      );
    });
  });
}

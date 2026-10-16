// An MCQ that shares its উদ্দীপক with the question under it. The intro and its
// figure belong to the *pair*, not to either question — "নিচের তথ্য থেকে ২৬ ও ২৭
// নং প্রশ্নের উত্তর দাও" — so it prints once, over the first of them, in every
// export. The sheet says which questions belong together simply by repeating the
// intro on each row it covers.
//
// What is locked down here: the grouping rule itself, the fact that the intro is
// welded to the first question's chunk in the PDF (an intro stranded at the foot
// of a column with its questions overleaf belongs to whatever is beneath it),
// and that the two-set MCQ shuffle moves whole groups rather than questions.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/models/highschool_question.dart';
import 'package:pi_qbank/services/highschool_export_service.dart';
import 'package:pi_qbank/utils/pdf_column_layout.dart';
import 'package:pi_qbank/utils/pdf_text_metrics.dart';

const kSharedStem = 'নিচের তথ্য থেকে ২৬ ও ২৭ নং প্রশ্নের উত্তর দাও।';

HighSchoolQuestion mcq({
  required String id,
  String stem = '',
  String image = '',
  String text = 'নিচের কোনটি সঠিক?',
  List<String> options = const ['৩', '৪', '৫', '৬'],
  String boardYearTag = '',
}) =>
    HighSchoolQuestion.fromJson({
      'id': id,
      'class': 'Class (9-10) SSC',
      'subject': 'গণিত',
      'chapter_number': '1',
      'chapter_name': 'অনুশীলনী',
      'question_type': 'MCQ',
      'stem_text': stem,
      'stem_image_url': image,
      'sub_questions_json': {
        'text': text,
        'options': options,
        'correct_ans': options.first,
      },
      'board_year_tag': boardYearTag,
    });

String htmlOf(List<HighSchoolQuestion> questions,
        {List<String> setLabels = const []}) =>
    HighSchoolExportService.generateHtml(
      schoolName: 'S',
      examName: 'E',
      subject: 'গণিত',
      className: 'C',
      time: 'T',
      totalMarks: '10',
      questions: questions,
      setLabels: setLabels,
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

int countOf(String haystack, String needle) =>
    needle.allMatches(haystack).length;

void main() {
  group('the grouping rule', () {
    test('an MCQ with no intro opens no group', () {
      final q = mcq(id: 'a');
      expect(q.mcqStemText, isEmpty);
      expect(q.opensMcqStemGroup(null), isFalse);
      expect(q.opensMcqStemGroup(mcq(id: 'b', stem: kSharedStem)), isFalse);
    });

    test('only the first of a run over the same intro prints it', () {
      final first = mcq(id: 'a', stem: kSharedStem);
      final second = mcq(id: 'b', stem: kSharedStem);

      expect(first.opensMcqStemGroup(null), isTrue);
      expect(second.opensMcqStemGroup(first), isFalse);
      // And the other way round: the second one opens its own group when the
      // question before it carries nothing.
      expect(second.opensMcqStemGroup(mcq(id: 'c')), isTrue);
      expect(
          second.opensMcqStemGroup(mcq(id: 'c', stem: 'অন্য উদ্দীপক')), isTrue);
    });

    test('a source marker does not break a group in two', () {
      // A row whose intro carries a source marker prints the same intro as one
      // that does not, so the two belong to the same group.
      final marked = mcq(
          id: 'a',
          stem: '$kSharedStem [ঢাকা বোর্ড ২০১৯]',
          boardYearTag: 'ঢাকা বোর্ড ২০১৯');
      final plain = mcq(id: 'b', stem: kSharedStem);

      expect(marked.mcqStemText, kSharedStem);
      expect(marked.opensMcqStemGroup(null), isTrue);
      expect(plain.opensMcqStemGroup(marked), isFalse);
    });

    test('a stemless question shares nothing, whatever precedes it', () {
      // The mirror of the rule, and the one a shuffle has to obey: a question
      // with no intro of its own never joins the group before it.
      final plain = mcq(id: 'a');
      expect(plain.sharesMcqStemWith(null), isFalse);
      expect(plain.sharesMcqStemWith(mcq(id: 'b', stem: kSharedStem)), isFalse);

      final first = mcq(id: 'c', stem: kSharedStem);
      final second = mcq(id: 'd', stem: kSharedStem);
      expect(first.sharesMcqStemWith(null), isFalse);
      expect(second.sharesMcqStemWith(first), isTrue);
    });

    test('the intro is an MCQ idea: other types never carry one', () {
      final cq = HighSchoolQuestion.fromJson({
        'id': 'cq',
        'class': 'Class (9-10) SSC',
        'subject': 'গণিত',
        'chapter_number': '1',
        'chapter_name': 'অনুশীলনী',
        'question_type': 'CQ',
        'stem_text': kSharedStem,
        'sub_questions_json': [
          {'label': 'ক', 'mark': 1, 'text': 'প্রশ্ন'},
        ],
      });
      expect(cq.paperStemText, kSharedStem);
      expect(cq.mcqStemText, isEmpty);
      expect(cq.opensMcqStemGroup(null), isFalse);
    });
  });

  group('the PDF estimator', () {
    late PdfTextMetrics m;

    setUpAll(() {
      m = PdfTextMetrics(
        banglaFontData: ByteData.sublistView(
            File('assets/fonts/SutonnyMJ Regular.ttf').readAsBytesSync()),
        symbolFontData: ByteData.sublistView(
            File('assets/fonts/MathSymbols.ttf').readAsBytesSync()),
      );
    });

    double height({
      String stem = '',
      bool withStem = false,
      bool hasImage = false,
      StemImageSize imageSize = StemImageSize.medium,
    }) =>
        PdfLayout.mcqHeight(
          index: 1,
          question: mcq(id: 'a', stem: stem),
          columnWidth: PdfLayout.columnWidth(1),
          metrics: m,
          withStem: withStem,
          hasImage: hasImage,
          imageSize: imageSize,
        );

    test('the intro and its gap are budgeted for', () {
      final plain = height(stem: kSharedStem);
      final opening = height(stem: kSharedStem, withStem: true);

      final expected = m.blockHeight(kSharedStem,
              width: PdfLayout.columnWidth(1),
              fontSize: PdfLayout.bodyFontSize) +
          PdfLayout.mcqStemGap;
      expect(opening - plain, closeTo(expected, 0.01));
    });

    test('so is the figure, at the size asked for', () {
      final stemOnly = height(stem: kSharedStem, withStem: true);
      final withFigure =
          height(stem: kSharedStem, withStem: true, hasImage: true);

      expect(
        withFigure - stemOnly,
        closeTo(PdfLayout.cqImageGap + StemImageSize.medium.maxHeightPt, 0.01),
      );
    });

    test('a hidden figure is not budgeted for', () {
      expect(
        height(
            stem: kSharedStem,
            withStem: true,
            hasImage: true,
            imageSize: StemImageSize.hidden),
        closeTo(height(stem: kSharedStem, withStem: true), 0.01),
      );
    });

    test('the intro rides on the head chunk, not on one of its own', () {
      // An intro given a chunk of its own could be left at the foot of a column
      // with the questions it introduces overleaf. It travels with the head.
      final without = PdfLayout.mcqFragments(
        index: 1,
        question: mcq(id: 'a', stem: kSharedStem),
        columnWidth: PdfLayout.columnWidth(1),
        metrics: m,
      );
      final with_ = PdfLayout.mcqFragments(
        index: 1,
        question: mcq(id: 'a', stem: kSharedStem),
        columnWidth: PdfLayout.columnWidth(1),
        metrics: m,
        withStem: true,
      );

      expect(with_.length, without.length);
      expect(with_.first, greaterThan(without.first));
    });
  });

  group('the sheet', () {
    test('a pair under one intro prints the intro once, over the first', () {
      final html = htmlOf([
        mcq(id: 'a', stem: kSharedStem),
        mcq(id: 'b', stem: kSharedStem),
      ]);

      expect(countOf(html, 'class="mcq-stem"'), 1);
      expect(countOf(html, kSharedStem), 1);
      // It sits inside the first card and before that card's question line.
      final stemAt = html.indexOf('class="mcq-stem"');
      final firstCard = html.indexOf('class="mcq-card"');
      expect(stemAt, greaterThan(firstCard));
      expect(stemAt, lessThan(html.indexOf('<b>1.</b>')));
      expect(stemAt, lessThan(html.indexOf('<b>2.</b>')));
    });

    test('the intro carries no number of its own', () {
      final html = htmlOf([mcq(id: 'a', stem: kSharedStem)]);
      final stem = html
          .substring(html.indexOf('class="mcq-stem"'))
          .split('</div>')
          .first;

      expect(stem, isNot(contains('<b>')));
      expect(html, contains('<b>1.</b>'));
    });

    test('two different intros open two groups', () {
      final html = htmlOf([
        mcq(id: 'a', stem: kSharedStem),
        mcq(id: 'b', stem: 'অন্য উদ্দীপক থেকে উত্তর দাও।'),
      ]);

      expect(countOf(html, 'class="mcq-stem"'), 2);
    });

    test('a question with no intro is a card like any other', () {
      final html = htmlOf([mcq(id: 'a'), mcq(id: 'b', stem: kSharedStem)]);
      expect(countOf(html, 'class="mcq-stem"'), 1);
      expect(countOf(html, 'class="mcq-card"'), 2);
    });

    test('the intro and its question ride together, as they do in the PDF', () {
      // In the PDF the intro, its figure and the question line are one chunk
      // that is never split; the sheet says the same with a wrapper. An intro
      // left at the foot of a column while its question opens the next one
      // reads as belonging to whatever is beside it.
      final html = htmlOf([mcq(id: 'a', stem: kSharedStem)]);

      final head = html.substring(html.indexOf('class="mcq-head"'),
          html.indexOf('class="mcq-options"'));
      expect(head, contains('class="mcq-stem"'));
      expect(head, contains('<b>1.</b>'));
      expect(
          html, matches(RegExp(r'\.mcq-head\s*\{[^}]*break-inside:\s*avoid;')));
    });

    test('every question block reveals its id on hover', () {
      final html =
          htmlOf([mcq(id: 'id-a', stem: kSharedStem), mcq(id: 'id-b')]);

      expect(html, contains('title="আইডি: id-a"'));
      expect(html, contains('title="আইডি: id-b"'));
    });

    test('the id is a tooltip, never printed text', () {
      final html = htmlOf([mcq(id: 'id-a')]);
      final body = html.split('<body>').last;
      // The only mention of the id is inside the title attribute.
      expect(countOf(body, 'আইডি: id-a'), 1);
      expect(body, contains('title="আইডি: id-a"'));
    });
  });

  group('the other exports', () {
    final pair = [
      mcq(id: 'a', stem: kSharedStem),
      mcq(id: 'b', stem: kSharedStem),
    ];

    test('Word groups the same way', () {
      final word = wordOf(pair);
      expect(countOf(word, 'class="mcq-stem"'), 1);
      expect(countOf(word, kSharedStem), 1);
    });

    test('plain text groups the same way', () {
      final text = textOf(pair);
      expect(countOf(text, kSharedStem), 1);
    });

    test('Markdown groups the same way', () {
      final md = markdownOf(pair);
      expect(countOf(md, kSharedStem), 1);
    });
  });

  group('two sets', () {
    test('the shuffle moves whole groups, not questions', () {
      // Three groups of two; whichever order they are printed in, the members of
      // a group stay adjacent, so no question is ever printed without its intro.
      final questions = [
        for (var g = 0; g < 3; g++) ...[
          mcq(id: 'g$g-a', stem: 'উদ্দীপক $g', text: 'প্রশ্ন $g.১'),
          mcq(id: 'g$g-b', stem: 'উদ্দীপক $g', text: 'প্রশ্ন $g.২'),
        ],
      ];

      final html = htmlOf(questions, setLabels: const ['ক', 'খ']);
      final printed = HighSchoolExportService.questionsForSet(
        questions,
        const ['ক', 'খ'],
        1,
      ).where((q) => q.isMcq).toList();

      expect(printed.length, 6);
      for (var i = 0; i < printed.length; i += 2) {
        expect(printed[i].mcqStemText, isNotEmpty);
        expect(printed[i + 1].mcqStemText, printed[i].mcqStemText,
            reason: 'a group must travel together');
      }

      // And the sheet says the same thing: one intro per group, in both sets.
      expect(countOf(html, 'class="mcq-stem"'), 6);
    });
  });
}

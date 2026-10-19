// An MCQ that shares its উদ্দীপক with the question under it. The intro and its
// figure belong to the *pair*, not to either question — "নিচের তথ্য থেকে ২৬ ও ২৭
// নং প্রশ্নের উত্তর দাও" — so it prints once, over the first of them, in every
// export. The sheet says which questions belong together simply by repeating the
// intro on each row it covers.
//
// This fixture names no numbers on purpose: a number in an intro is rewritten
// to the paper's own numbering (see the "the numbers in an intro" group below),
// and these tests are about *which* questions share an intro, not about what its
// text happens to say.
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

const kSharedStem = 'নিচের তথ্য থেকে প্রশ্ন দুটির উত্তর দাও।';

HighSchoolQuestion mcq({
  required String id,
  String stem = '',
  String image = '',
  String group = '',
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
      'stem_group': group,
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

  group('the figure the intro carries', () {
    // The intro is the wording *and* the figure under it. Two questions under
    // one wording but two different figures are two intros; reading them as one
    // printed the first figure and dropped the second off the paper.

    test('the same wording over two figures opens two groups', () {
      final first = mcq(id: 'a', stem: kSharedStem, image: 'https://x/a.png');
      final same = mcq(id: 'b', stem: kSharedStem, image: 'https://x/a.png');
      final other = mcq(id: 'c', stem: kSharedStem, image: 'https://x/b.png');

      expect(same.opensMcqStemGroup(first), isFalse);
      expect(other.opensMcqStemGroup(first), isTrue);
      expect(other.sharesMcqStemWith(first), isFalse);
    });

    test('a question with no figure of its own follows on the wording', () {
      final opening = mcq(id: 'a', stem: kSharedStem, image: 'https://x/a.png');
      final bare = mcq(id: 'b', stem: kSharedStem);
      final textOnly = mcq(id: 'c', stem: kSharedStem);

      expect(bare.opensMcqStemGroup(opening), isFalse);
      expect(textOnly.opensMcqStemGroup(bare), isFalse);
    });

    test('a figure arriving under a figureless intro opens its own group', () {
      // The group cannot adopt a figure it never printed, so the question that
      // carries one starts a group of its own rather than losing the figure.
      final textOnly = mcq(id: 'a', stem: kSharedStem);
      final figured = mcq(id: 'b', stem: kSharedStem, image: 'https://x/a.png');

      expect(figured.opensMcqStemGroup(textOnly), isTrue);
    });

    test('other types never carry a figure with their intro', () {
      final cq = HighSchoolQuestion.fromJson({
        'id': 'cq',
        'class': 'Class (9-10) SSC',
        'subject': 'গণিত',
        'chapter_number': '1',
        'chapter_name': 'অনুশীলনী',
        'question_type': 'CQ',
        'stem_text': kSharedStem,
        'stem_image_url': 'https://x/a.png',
        'sub_questions_json': [
          {'label': 'ক', 'mark': 1, 'text': 'প্রশ্ন'},
        ],
      });
      expect(cq.mcqStemImageUrl, isEmpty);
    });

    test('the sheet prints two intros under two figures', () {
      final html = htmlOf([
        mcq(id: 'a', stem: kSharedStem, image: 'https://x/a.png'),
        mcq(id: 'b', stem: kSharedStem, image: 'https://x/b.png'),
      ]);

      expect(countOf(html, 'class="mcq-stem"'), 2);
      expect(countOf(html, kSharedStem), 2);
    });

    test('the sheet keeps one intro when only one figure is filed', () {
      final html = htmlOf([
        mcq(id: 'a', stem: kSharedStem, image: 'https://x/a.png'),
        mcq(id: 'b', stem: kSharedStem),
      ]);

      expect(countOf(html, 'class="mcq-stem"'), 1);
      expect(countOf(html, kSharedStem), 1);
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

  group('the run label the sheet carries', () {
    // The label is the explicit form of the rule. Instead of the writers working
    // out whether two rows print under one intro by comparing what they say, the
    // sheet says it in `stem_group`. The wording-and-figure fallback above stays
    // for rows filed without a label.

    test('two rows filed under different labels are two intros', () {
      // The case the label exists for: one generic wording over two different
      // stimuli. Read on the wording alone they were one run, and the second
      // intro never reached the paper.
      final first = mcq(id: 'a', stem: kSharedStem, group: 'উদ্দীপক-১');
      final second = mcq(id: 'b', stem: kSharedStem, group: 'উদ্দীপক-২');

      expect(second.sharesMcqStemWith(first), isFalse);
      expect(second.opensMcqStemGroup(first), isTrue);
    });

    test('rows sharing a label are one run whatever their figure says', () {
      // The figure is not compared once the sheet has spoken: a rewritten link
      // must not split a run in half.
      final first = mcq(
          id: 'a',
          stem: kSharedStem,
          group: 'উদ্দীপক-১',
          image: 'https://x/a.png');
      final second = mcq(
          id: 'b',
          stem: kSharedStem,
          group: 'উদ্দীপক-১',
          image: 'https://x/b.png');

      expect(second.sharesMcqStemWith(first), isTrue);
      expect(second.opensMcqStemGroup(first), isFalse);
    });

    test('a row of a run with no wording of its own prints none', () {
      final first = mcq(id: 'a', stem: kSharedStem, group: 'উদ্দীপক-১');
      final bare = mcq(id: 'b', group: 'উদ্দীপক-১');

      expect(bare.mcqStemText, isEmpty);
      expect(bare.opensMcqStemGroup(first), isFalse);
    });

    test('a wording the run has not printed yet opens its own intro', () {
      // A labelled row is never swallowed silently: the intro prints the way it
      // was written, so a different wording prints rather than disappearing.
      final first = mcq(id: 'a', stem: kSharedStem, group: 'উদ্দীপক-১');
      final other = mcq(
          id: 'b', stem: 'নিচের চিত্রটি দেখে উত্তর দাও।', group: 'উদ্দীপক-১');

      expect(other.opensMcqStemGroup(first), isTrue);
    });

    test('a row with no label beside a labelled one prints its own intro', () {
      // A label, once filed, is not second-guessed: the unlabelled row never
      // claimed the run, so it prints rather than being guessed into it. The
      // failure that leaves is a duplicate intro, which is visible — not a lost
      // one, which is not.
      final labelled = mcq(id: 'a', stem: kSharedStem, group: 'উদ্দীপক-১');
      final plain = mcq(id: 'b', stem: kSharedStem);

      expect(plain.opensMcqStemGroup(labelled), isTrue);
      // And the other way round.
      expect(labelled.opensMcqStemGroup(plain), isTrue);
    });

    test('with no label anywhere the wording and figure still decide', () {
      final first = mcq(id: 'a', stem: kSharedStem, image: 'https://x/a.png');
      final same = mcq(id: 'b', stem: kSharedStem, image: 'https://x/a.png');
      final other = mcq(id: 'c', stem: kSharedStem, image: 'https://x/b.png');

      expect(same.opensMcqStemGroup(first), isFalse);
      expect(other.opensMcqStemGroup(first), isTrue);
    });

    test('other types carry no label', () {
      final cq = HighSchoolQuestion.fromJson({
        'id': 'cq',
        'class': 'Class (9-10) SSC',
        'subject': 'গণিত',
        'chapter_number': '1',
        'chapter_name': 'অনুশীলনী',
        'question_type': 'CQ',
        'stem_text': kSharedStem,
        'stem_group': 'উদ্দীপক-১',
        'sub_questions_json': [
          {'label': 'ক', 'mark': 1, 'text': 'প্রশ্ন'},
        ],
      });
      expect(cq.mcqStemGroup, isEmpty);
    });

    test('the sheet prints one intro per label', () {
      final html = htmlOf([
        mcq(
            id: 'a',
            stem: kSharedStem,
            group: 'উদ্দীপক-১',
            image: 'https://x/a.png'),
        mcq(
            id: 'b',
            stem: kSharedStem,
            group: 'উদ্দীপক-১',
            image: 'https://x/b.png'),
        mcq(
            id: 'c',
            stem: kSharedStem,
            group: 'উদ্দীপক-২',
            image: 'https://x/c.png'),
      ]);

      expect(countOf(html, 'class="mcq-stem"'), 2);
      expect(countOf(html, kSharedStem), 2);
    });

    test('the row keeps its label across a fetch and an edit', () {
      final original = mcq(id: 'a', stem: kSharedStem, group: 'উদ্দীপক-১');
      final edited = HighSchoolQuestion.edited(
        original: original,
        chapterNumber: '1',
        chapterName: 'অনুশীলনী',
        text: 'সংশোধিত প্রশ্ন',
        stem: kSharedStem,
      );

      expect(edited.stemGroup, 'উদ্দীপক-১');
      expect(edited.toJson()['stem_group'], 'উদ্দীপক-১');
    });

    test('and the shuffle keeps each labelled run whole', () {
      final questions = [
        for (var g = 0; g < 3; g++) ...[
          mcq(id: 'g$g-a', stem: 'উদ্দীপক $g', group: 'উদ্দীপক-$g'),
          mcq(id: 'g$g-b', stem: 'উদ্দীপক $g', group: 'উদ্দীপক-$g'),
        ],
      ];

      final printed = HighSchoolExportService.questionsForSet(
        questions,
        const ['ক', 'খ'],
        1,
      ).where((q) => q.isMcq).toList();

      expect(printed.length, 6);
      for (var i = 0; i < printed.length; i += 2) {
        expect(printed[i + 1].mcqStemGroup, printed[i].mcqStemGroup,
            reason: 'a labelled run travels together');
      }
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

  group('the numbers in an intro', () {
    // The bank's intros are copied out of the board paper they came from, so
    // they name that paper's numbers. A generated paper prints the questions
    // wherever they were picked, so the reference has to be rewritten or it
    // introduces the wrong pair.
    const bracketed = 'নিচের তথ্যের আলোকে (১২ ও ১৩) নং প্রশ্নের উত্তর দাও:';
    const bare = 'নিচের তথ্য থেকে ২৬ ও ২৭ নং প্রশ্নের উত্তর দাও।';

    test('a bracketed reference becomes the numbers the paper prints', () {
      expect(
          HighSchoolExportService.stemWithNumbers(bracketed, [1, 2]),
          'নিচের তথ্যের আলোকে (১ ও ২) নং প্রশ্নের উত্তর দাও:');
    });

    test('a bare reference is rewritten the same way', () {
      expect(HighSchoolExportService.stemWithNumbers(bare, [1, 2]),
          'নিচের তথ্য থেকে ১ ও ২ নং প্রশ্নের উত্তর দাও।');
    });

    test('a range joined by a dash is rewritten too', () {
      // The form the upload tool's own example uses.
      const dashed = 'নিচের তথ্য থেকে ২৬ - ২৭ নং প্রশ্নের উত্তর দাও ।';
      expect(HighSchoolExportService.stemWithNumbers(dashed, [5, 6]),
          'নিচের তথ্য থেকে ৫ ও ৬ নং প্রশ্নের উত্তর দাও ।');
    });

    test('three questions read as a list, not a pair', () {
      expect(
          HighSchoolExportService.stemWithNumbers(bracketed, [3, 4, 5]),
          'নিচের তথ্যের আলোকে (৩, ৪ ও ৫) নং প্রশ্নের উত্তর দাও:');
    });

    test('a question on its own names only itself', () {
      expect(
          HighSchoolExportService.stemWithNumbers(bracketed, [7]),
          'নিচের তথ্যের আলোকে (৭) নং প্রশ্নের উত্তর দাও:');
    });

    test('an intro written in ASCII digits keeps them', () {
      expect(HighSchoolExportService.stemWithNumbers('answer 12 and 13 নং', [4, 5]),
          'answer 4 and 5 নং');
    });

    test('a placeholder is filled even with no reference to rewrite', () {
      expect(
          HighSchoolExportService.stemWithNumbers(
              'নিচের তথ্যের আলোকে (${HighSchoolExportService.stemNumbersPlaceholder}) নং প্রশ্নের উত্তর দাও:',
              [2, 3]),
          'নিচের তথ্যের আলোকে (২ ও ৩) নং প্রশ্নের উত্তর দাও:');
    });

    test('text that only looks like a reference is left alone', () {
      // The other form the phrase takes in a real paper: letters, not numbers.
      const letters = 'নিচের উদ্দীপকটি পড়ে (ক) ও (খ) নং প্রশ্নের উত্তর দাও।';
      expect(HighSchoolExportService.stemWithNumbers(letters, [1, 2]), letters);
      // A year in brackets is not a question reference.
      const year = '২০২৩ সালের (৩) পরীক্ষার নং প্রশ্ন দাও।';
      expect(HighSchoolExportService.stemWithNumbers(year, [1, 2]), year);
      // An intro that names no questions at all.
      const plain = 'নিচের উদ্দীপকটি দেখে উত্তর দাও।';
      expect(HighSchoolExportService.stemWithNumbers(plain, [1, 2]), plain);
    });

    test('the run is the questions that share the intro', () {
      final pair = [
        mcq(id: 'a', stem: bare),
        mcq(id: 'b', stem: bare),
      ];
      final trio = [
        mcq(id: 'c', stem: bare),
        mcq(id: 'd', stem: bare),
        mcq(id: 'e', stem: bare),
      ];
      expect(HighSchoolExportService.mcqStemRunNumbers(pair, 0), [1, 2]);
      expect(HighSchoolExportService.mcqStemRunNumbers(trio, 0), [1, 2, 3]);
      // Out of range rather than a wrong number.
      expect(HighSchoolExportService.mcqStemRunNumbers(pair, 5), isEmpty);
      expect(HighSchoolExportService.mcqStemRunNumbers(const [], 0), isEmpty);
    });

    test('two groups in a row each get their own numbers', () {
      // This is the case from the bank: two shared rows of (১২ ও ১৩) and
      // (১২৩ ও ১২৪), picked as questions 1-4.
      final questions = [
        mcq(id: 'a', stem: bracketed),
        mcq(id: 'b', stem: bracketed),
        mcq(id: 'c', stem: 'নিচের তথ্যের আলোকে (১২৩ ও ১২৪) নং প্রশ্নের উত্তর দাও:'),
        mcq(id: 'd', stem: 'নিচের তথ্যের আলোকে (১২৩ ও ১২৪) নং প্রশ্নের উত্তর দাও:'),
      ];
      final html = htmlOf(questions);

      expect(html, contains('(১ ও ২) নং'));
      expect(html, contains('(৩ ও ৪) নং'));
      expect(html, isNot(contains('(১২ ও ১৩) নং')));
      expect(html, isNot(contains('(১২৩ ও ১২৪) নং')));
      // Still one intro per group, and the questions under them keep their own
      // printed numbers.
      expect(countOf(html, 'class="mcq-stem"'), 2);
      expect(html, contains('<b>1.</b>'));
      expect(html, contains('<b>4.</b>'));
    });

    test('ASCII digits in the question body do not change the hand', () {
      // A real row from the bank: the set is written with ASCII digits, the
      // question numbers with Bengali ones. The reference has to keep its own
      // hand rather than borrow the body's.
      const withSet = 'নিচের তথ্যের আলোকে (১২ ও ১৩) নং প্রশ্নের উত্তর দাও:\n'
          'U = {1, 2, 3, 4, 5, 6}, A = {2, 4}, B = {3, 4, 5}';
      final questions = [
        mcq(id: 'a', stem: withSet),
        mcq(id: 'b', stem: withSet),
      ];
      final html = htmlOf(questions);

      expect(html, contains('(১ ও ২) নং'));
      expect(html, isNot(contains('(1 and 2) নং')));
      // And the line break in the intro is still a line break.
      expect(html, contains('<br>U = {1, 2, 3, 4, 5, 6}'));
    });

    test('every export gets the same rewritten intro', () {
      final questions = [
        mcq(id: 'a', stem: bracketed),
        mcq(id: 'b', stem: bracketed),
      ];

      expect(htmlOf(questions), contains('(১ ও ২) নং'));
      expect(wordOf(questions), contains('(১ ও ২) নং'));
      expect(textOf(questions), contains('(১ ও ২) নং'));
      expect(markdownOf(questions), contains('(১ ও ২) নং'));
    });

    test('the estimator measures the intro the card actually draws', () {
      // A longer number can push the intro onto another line. Booking the room
      // from the bank's text and drawing the rewritten one would overflow it.
      final m = PdfTextMetrics(
        banglaFontData: ByteData.sublistView(
            File('assets/fonts/SutonnyMJ Regular.ttf').readAsBytesSync()),
        symbolFontData: ByteData.sublistView(
            File('assets/fonts/MathSymbols.ttf').readAsBytesSync()),
      );
      final question = mcq(id: 'a', stem: bracketed);
      final drawn = HighSchoolExportService.stemWithNumbers(
          question.mcqStemText, [98, 99]);
      double height(String stem) => PdfLayout.mcqFragments(
            index: 1,
            question: question,
            columnWidth: PdfLayout.columnWidth(1),
            metrics: m,
            withStem: true,
            stemText: stem,
          ).first;

      expect(height(drawn), greaterThan(0));
      expect(height(drawn),
          closeTo(height(question.mcqStemText), 0.01),
          reason: 'the override must be the text that is measured');
    });
  });
}

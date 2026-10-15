// The paper's font-size control moves every text size in the paper by one point
// per step — the same step in the PDF and in the HTML sheet.
//
// Two things have to hold. The sheet must move *every* size, including the ones
// it leaves to be inherited (an MCQ stem), or a paper grows unevenly as the step
// is turned up. And the step has to reach the layout's height estimators as well
// as the styles it draws with: an estimator that keeps budgeting room for 11pt
// text while 13pt text is drawn under-estimates the paper, and a column overflows
// the allowance the flow gave it. Hence one guard per estimator.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/models/highschool_question.dart';
import 'package:pi_qbank/services/highschool_export_service.dart';
import 'package:pi_qbank/utils/pdf_column_layout.dart';
import 'package:pi_qbank/utils/pdf_text_metrics.dart';

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

/// A paper with one block of each kind, generated at [fontStep].
String generate(double fontStep) => HighSchoolExportService.generateHtml(
      schoolName: 'S',
      examName: 'E',
      subject: 'গণিত',
      className: 'C',
      time: 'T',
      totalMarks: '10',
      questions: [
        cqTest('উদ্দীপক পাঠ করে নিচের প্রশ্নগুলোর উত্তর দাও।'),
        mcqTest('নিচের কোনটি সঠিক?'),
        rqTest('সংক্ষেপে উত্তর দাও।'),
      ],
      fontStep: fontStep,
    );

/// The stylesheet of a generated paper.
String cssOf(String html) => html.split('<style>')[1].split('</style>')[0];

/// The declarations inside one CSS rule, by selector, exactly as written.
String rule(String css, String selector) {
  final match =
      RegExp('${RegExp.escape(selector)}\\s*\\{([^}]*)\\}', multiLine: true)
          .firstMatch(css);
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
  group('the HTML sheet', () {
    test('prints the tuned size when nothing is stepped', () {
      final css = cssOf(generate(0));

      // No `calc()` at 0: a paper that has never been stepped has to come out
      // exactly as it did before the control existed.
      expect(decl(rule(css, '.cq-stem'), 'font-size'), '15px');
      expect(decl(rule(css, '.rq-item'), 'font-size'), '15px');
      expect(decl(rule(css, '.school-title'), 'font-size'), '24px');
      expect(decl(rule(css, '.paper-sheet'), 'font-size'), '16px');
    });

    test('moves every size by the step, in points', () {
      final css = cssOf(generate(2));

      // Points, not pixels: the PDF moves its own sizes by one point a step, so
      // the sheet has to grow by a point too or the two exports drift apart.
      const expected = {
        '.school-title': 'calc(24px + 2pt)',
        '.exam-title': 'calc(18px + 2pt)',
        '.meta-bar': 'calc(15px + 2pt)',
        '.section-banner': 'calc(14px + 2pt)',
        '.cq-stem': 'calc(15px + 2pt)',
        '.cq-sub-item': 'calc(14px + 2pt)',
        '.mcq-options': 'calc(14px + 2pt)',
        '.rq-item': 'calc(15px + 2pt)',
        // The sheet's own size: what an MCQ stem, which sets no size of its
        // own, inherits.
        '.paper-sheet': 'calc(16px + 2pt)',
      };

      for (final entry in expected.entries) {
        expect(decl(rule(css, entry.key), 'font-size'), entry.value,
            reason: entry.key);
      }
    });

    test('a negative step subtracts instead of adding a signed value', () {
      final css = cssOf(generate(-2));

      expect(decl(rule(css, '.cq-stem'), 'font-size'), 'calc(15px - 2pt)');
      expect(decl(rule(css, '.paper-sheet'), 'font-size'), 'calc(16px - 2pt)');
    });

    test('the canvas and the text column stay put', () {
      final small = rule(cssOf(generate(-3)), '.paper-sheet');
      final big = rule(cssOf(generate(6)), '.paper-sheet');

      // Text grows into the same A4 page: only the sizes move, never the page or
      // the margins, which is what keeps a line wrapping in the same place as in
      // the PDF.
      for (final sheet in [small, big]) {
        expect(decl(sheet, 'width'), '210mm');
        expect(decl(sheet, 'min-height'), '297mm');
        expect(decl(sheet, 'padding'), '18pt 40pt 18px');
      }
    });
  });

  group('the PDF layout', () {
    late PdfTextMetrics metrics;

    setUpAll(() {
      metrics = PdfTextMetrics(
        banglaFontData: ByteData.sublistView(
            File('assets/fonts/SutonnyMJ Regular.ttf').readAsBytesSync()),
        symbolFontData: ByteData.sublistView(
            File('assets/fonts/MathSymbols.ttf').readAsBytesSync()),
      );
    });

    test('every height estimator grows with the step', () {
      final cq = cqTest('উদ্দীপক পাঠ করে নিচের প্রশ্নগুলোর উত্তর দাও।');
      final rq = rqTest('সংক্ষেপে উত্তর দাও।');
      final mcq = mcqTest('নিচের কোনটি সঠিক?');

      double rqHeight({double fontStep = 0}) => PdfLayout.rqHeight(
          index: 1,
          question: rq,
          columnWidth: 260,
          metrics: metrics,
          fontStep: fontStep);
      double cqHeight({double fontStep = 0}) => PdfLayout.cqHeight(
            index: 1,
            question: cq,
            columnWidth: 260,
            metrics: metrics,
            hasImage: false,
            imageSize: StemImageSize.medium,
            fontStep: fontStep,
          );
      double mcqHeight({double fontStep = 0}) => PdfLayout.mcqHeight(
            index: 1,
            question: mcq,
            columnWidth: 260,
            metrics: metrics,
            stackOptions: true,
            fontStep: fontStep,
          );

      final grew = {
        'rqHeight': rqHeight(fontStep: 4) > rqHeight(),
        'cqHeight': cqHeight(fontStep: 4) > cqHeight(),
        'mcqHeight': mcqHeight(fontStep: 4) > mcqHeight(),
        'headerHeight': PdfLayout.headerHeight(
              metrics: metrics,
              schoolName: 'S',
              examName: 'E',
              subject: 'গণিত',
              className: 'C',
              time: 'T',
              totalMarks: '10',
              fontStep: 4,
            ) >
            PdfLayout.headerHeight(
              metrics: metrics,
              schoolName: 'S',
              examName: 'E',
              subject: 'গণিত',
              className: 'C',
              time: 'T',
              totalMarks: '10',
            ),
        'sectionBannerHeight':
            PdfLayout.sectionBannerHeight(metrics, fontStep: 4) >
                PdfLayout.sectionBannerHeight(metrics),
      };

      for (final entry in grew.entries) {
        expect(entry.value, isTrue,
            reason: '${entry.key} ignores the font step');
      }
    });

    test('a stepped row grows by more when it wraps', () {
      // A narrow column forces the same text onto more lines as it grows, so the
      // estimator has to follow the metrics rather than just add the step: this
      // catches a `fontSize + fontStep` that never reached the line estimate.
      final rq = rqTest('সংক্ষেপে উত্তর দাও এবং যুক্তি দাও।');
      final base = PdfLayout.rqHeight(
          index: 1, question: rq, columnWidth: 90, metrics: metrics);
      final up = PdfLayout.rqHeight(
          index: 1,
          question: rq,
          columnWidth: 90,
          metrics: metrics,
          fontStep: 6);

      expect(up, greaterThan(base));
      expect(up - base, greaterThan(PdfLayout.rqGap));
    });
  });
}

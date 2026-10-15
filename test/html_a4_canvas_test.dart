// The HTML export is a print preview, so its canvas has to be the *same* A4
// page the PDF export writes — same width, same margins, same text column. If
// the two drift, a line that wraps in one export wraps somewhere else in the
// other and the paper stops matching the PDF.
import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/models/highschool_question.dart';
import 'package:pi_qbank/services/highschool_export_service.dart';
import 'package:pi_qbank/utils/pdf_column_layout.dart';

String sampleHtml({
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
      cqLayout: cqLayout,
      rqLayout: rqLayout,
      mcqLayout: mcqLayout,
      questions: [
        HighSchoolQuestion.fromJson({
          'id': 'q',
          'class': 'Class (9-10) SSC',
          'subject': 'গণিত',
          'chapter_number': '1',
          'chapter_name': 'অনুশীলনী',
          'question_type': 'RQ',
          'stem_text': 'সংক্ষিপ্ত প্রশ্ন',
          'stem_image_url': '',
          'sub_questions_json': <Object>[],
          'board_year_tag': '',
          'short_mark': 1,
        }),
      ],
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
///
/// Line-aware: a rule may carry a comment, and a comment may carry a semicolon,
/// which a flat `;`-or-start scan would mistake for the end of a declaration.
String? decl(String body, String property) {
  final match = RegExp('(?:^|;)\\s*${RegExp.escape(property)}\\s*:([^;]*)',
          multiLine: true)
      .firstMatch(body);
  return match?.group(1)?.trim();
}

/// A CSS length in points (1in = 25.4mm = 72pt = 96px).
double points(String value) {
  final match = RegExp(r'^([\d.]+)\s*(mm|pt|px)?$').firstMatch(value.trim())!;
  final n = double.parse(match.group(1)!);
  switch (match.group(2)) {
    case 'mm':
      return n / 25.4 * 72;
    case 'px':
      return n * 72 / 96;
    default:
      return n;
  }
}

/// The four sides of a padding shorthand, in points.
List<double> paddingSides(String value) =>
    value.split(RegExp(r'\s+')).map(points).toList();

void main() {
  final css = sampleHtml().split('<style>')[1].split('</style>')[0];

  test('the sheet is an A4 canvas', () {
    final sheet = rule(css, '.paper-sheet');

    expect(decl(sheet, 'width'), '210mm');
    // A short paper still shows a full page rather than a stub.
    expect(decl(sheet, 'min-height'), '297mm');

    expect(points('210mm'), closeTo(PdfLayout.a4Width, 0.01));
    expect(points('297mm'), closeTo(PdfLayout.a4Height, 0.05));
  });

  test('the canvas keeps the PDF page margins', () {
    final sides = paddingSides(decl(rule(css, '.paper-sheet'), 'padding')!);

    // padding: top right bottom — left follows the right.
    expect(sides[0], PdfLayout.pageMarginTop);
    expect(sides[1], PdfLayout.pageMarginH);
    // The foot is a shade deeper than the PDF's own: the last line of a full
    // page ends clear of the paper's edge instead of on it.
    expect(sides[2], closeTo(points('18px'), 0.01));
  });

  test('the text column is exactly as wide as the PDF page', () {
    final sides = paddingSides(decl(rule(css, '.paper-sheet'), 'padding')!);

    expect(
        points('210mm') - sides[1] * 2, closeTo(PdfLayout.contentWidth, 0.01));
  });

  test('print lays out A4 and lets the sheet carry the margins', () {
    expect(decl(rule(css, '@page'), 'size'), 'A4');
    expect(decl(rule(css, '@page'), 'margin'), '0');

    final printed = css.split('@media print')[1];

    // Same margins as on screen, so a printed page breaks where the PDF's does.
    expect(paddingSides(decl(rule(printed, '.paper-sheet'), 'padding')!), [
      PdfLayout.pageMarginTop,
      PdfLayout.pageMarginH,
      points('18px'),
    ]);
    // min-height is a screen-only conceit: on paper it would add a blank page.
    expect(points(decl(rule(printed, '.paper-sheet'), 'min-height')!), 0);
    // The second set starts a fresh sheet.
    expect(rule(printed, '.paper-sheet + .paper-sheet'),
        contains('break-before: page'));
  });

  test('section spacing is the PDF\'s own', () {
    final margin = decl(rule(css, '.section-banner'), 'margin')!
        .split(RegExp(r'\s+'))
        .map(points)
        .toList();

    // margin: top right bottom — the same two numbers the page charges its
    // widget tree, so a section sits the same distance apart here as on paper.
    expect(margin[0], PdfLayout.sectionGap);
    expect(margin[2], PdfLayout.sectionBannerGap);

    // The masthead adds no band of its own: the first banner's sectionGap *is*
    // the gap under the meta row.
    expect(points(decl(rule(css, '.meta-bar'), 'margin-bottom') ?? '0'), 0);

    // The bar is a caption, not a heading: 14px on 3px 6px of padding.
    expect(decl(rule(css, '.section-banner'), 'font-size'), '14px');
    expect(decl(rule(css, '.section-banner'), 'padding'), '3px 6px');
  });

  test('a two-column block starts both columns level', () {
    final twoColumn = cssOf(sampleHtml(
      cqLayout: QuestionLayout.doubleColumn,
      rqLayout: QuestionLayout.doubleColumn,
    ));

    // The declaration inside the block gives up the gap above itself: a margin
    // on the first child of the flow would push the left column down and leave
    // the right column's first question above the heading beside it. The gap
    // moves out to the container, which both columns share. Below itself the
    // bar sits a shade closer to its questions than the full-width one does.
    final inFlow = decl(rule(twoColumn, '.section-banner.in-flow'), 'margin')!
        .split(RegExp(r'\s+'))
        .map(points)
        .toList();
    expect(inFlow[0], 0);
    expect(inFlow[2], closeTo(points('6px'), 0.01));
    expect(points(decl(rule(twoColumn, '.cq-grid'), 'margin-top')!),
        PdfLayout.sectionGap);

    // A single-column block keeps its bar above the content, gap and all.
    final oneColumn = cssOf(sampleHtml());
    expect(decl(rule(oneColumn, '.cq-grid'), 'margin-top'), isNull);
    expect(
        points(decl(rule(oneColumn, '.section-banner'), 'margin')!
            .split(RegExp(r'\s+'))
            .first),
        PdfLayout.sectionGap);
  });

  test('the two sides are divided by a vertical rule, not by boxes', () {
    final twoColumn = cssOf(sampleHtml(
      cqLayout: QuestionLayout.doubleColumn,
      rqLayout: QuestionLayout.doubleColumn,
    ));

    for (final grid in ['.cq-grid', '.flow-grid', '.mcq-grid', '.rq-grid']) {
      expect(decl(rule(twoColumn, grid), 'column-rule'), contains('solid'),
          reason: '$grid should draw the rule down the gutter');
    }
    // The rule replaces the frame each question used to carry.
    expect(decl(rule(twoColumn, '.cq-card'), 'border'), anyOf(isNull, 'none'));
    expect(decl(rule(twoColumn, '.cq-card'), 'border-radius'),
        anyOf(isNull, 'none'));
  });

  test('a question may break across the column so the two sides finish level',
      () {
    final css = cssOf(sampleHtml(
      cqLayout: QuestionLayout.doubleColumn,
      rqLayout: QuestionLayout.doubleColumn,
    ));

    // Keeping every card whole is what left the columns lopsided.
    expect(decl(rule(css, '.cq-card'), 'break-inside'), anyOf(isNull, 'auto'));
    expect(decl(rule(css, '.cq-card'), 'page-break-inside'),
        anyOf(isNull, 'auto'));
    expect(decl(rule(css, '.mcq-card'), 'break-inside'), anyOf(isNull, 'auto'));
  });

  test('short questions sit close together, with no rule between them', () {
    final item = rule(css, '.rq-item');

    expect(decl(item, 'border-bottom'), anyOf(isNull, 'none'));
    expect(decl(item, 'margin-bottom'), anyOf(isNull, '0'));

    // No padding and no gap of its own: the line box *is* the row, so the
    // questions sit flush against each other.
    expect(decl(item, 'padding'), anyOf(isNull, '0'));
    expect(decl(item, 'gap'), anyOf(isNull, '0'));

    // The dashed rule belongs to the MCQs, where the PDF draws it too.
    expect(rule(css, '.mcq-card'), contains('dashed'));
  });

  test('the page is black on white, with the marks a touch grey', () {
    // The PDF writes its text in pure black and its marks in grey; the page
    // follows, so the two exports read the same.
    expect(decl(rule(css, ':root'), '--text'), '#000000');
    expect(rule(css, '.cq-mark'), contains('var(--muted)'));
    expect(rule(css, '.rq-mark'), contains('var(--muted)'));

    // Marks are annotations, not content: the PDF draws them at normal weight,
    // so a bold `[2]` here would make one export shout where the other does not.
    expect(decl(rule(css, '.cq-mark'), 'font-weight'), '400');
    expect(decl(rule(css, '.rq-mark'), 'font-weight'), '400');
  });
}

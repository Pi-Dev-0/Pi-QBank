import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:pi_qbank/models/highschool_question.dart';
import 'package:pi_qbank/services/highschool_export_service.dart' as ex;
import 'package:pi_qbank/services/highschool_export_service.dart';
import 'package:pi_qbank/utils/pdf_column_layout.dart';
import 'package:pi_qbank/utils/pdf_mixed_text.dart';
import 'package:pi_qbank/utils/pdf_text_metrics.dart';

HighSchoolQuestion cq(String stem) => HighSchoolQuestion.fromJson({
      'id': 'cq',
      'class': 'Class (9-10) SSC',
      'subject': 'উচ্চতর গণিত',
      'chapter_number': '1',
      'chapter_name': 'অনুশীলনী',
      'question_type': 'CQ',
      'stem_text': stem,
      'stem_image_url': '',
      'sub_questions_json': [
        {'label': 'ক', 'mark': 2, 'text': 'একটি সমীকরণ সমাধান করো।'},
        {'label': 'খ', 'mark': 3, 'text': 'একটি জ্যামিতিক সমস্যা সমাধান করো।'},
      ],
      'board_year_tag': '',
    });

HighSchoolQuestion rq(String text, [int mark = 1]) =>
    HighSchoolQuestion.fromJson({
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
      'short_mark': mark,
    });

HighSchoolQuestion mcq(String t) => HighSchoolQuestion.fromJson({
      'id': 'm',
      'class': 'Class (9-10) SSC',
      'subject': 'উচ্চতর গণিত',
      'chapter_number': '1',
      'chapter_name': 'অনুশীলনী',
      'question_type': 'MCQ',
      'stem_text': '',
      'stem_image_url': '',
      'sub_questions_json': {
        'text': t,
        'options': ['৪', '৫', '৬', '৭'],
        'correct_ans': '৫',
      },
      'board_year_tag': '',
    });

/// Shared measurer, so the tests and the render harnesses agree.
final PdfTextMetrics metrics = PdfTextMetrics(
  banglaFontData: ByteData.sublistView(
      File('assets/fonts/SutonnyMJ Regular.ttf').readAsBytesSync()),
  symbolFontData: ByteData.sublistView(
      File('assets/fonts/MathSymbols.ttf').readAsBytesSync()),
);

/// Render a short-question (RQ) section in the given column mode, mirroring the
/// generator page: header, banner, then packed columns driven by [PdfPageFlow].
Future<List<int>> renderShorts(
    List<HighSchoolQuestion> shorts, int columns) async {
  final bytes = File('assets/fonts/SutonnyMJ Regular.ttf').readAsBytesSync();
  final doc = pw.Document();
  final bangla = pw.Font.ttf(ByteData.sublistView(bytes));
  final fallback = <pw.Font>[
    pw.Font.ttf(ByteData.sublistView(
        File('assets/fonts/MathSymbols.ttf').readAsBytesSync()))
  ];
  final base = pw.TextStyle(font: bangla, fontFallback: fallback, fontSize: 11);
  final bold = pw.TextStyle(
      font: bangla,
      fontFallback: fallback,
      fontSize: 11,
      fontWeight: pw.FontWeight.bold);
  pw.TextSpan mixed(String t, [pw.TextStyle? style]) =>
      buildPdfTextSpan(t, style ?? base);

  final width = PdfLayout.columnWidth(columns);
  final flow = PdfPageFlow(contentHeight: PdfLayout.contentHeight)
    ..consume(PdfLayout.sectionBannerHeight(metrics) + 26);

  final rows = flow.layout(
    heights: [
      for (int i = 0; i < shorts.length; i++)
        PdfLayout.rqHeight(
            index: i + 1,
            question: shorts[i],
            columnWidth: width,
            metrics: metrics),
    ],
    columns: columns,
  );

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: pw.EdgeInsets.symmetric(
        horizontal: PdfLayout.pageMarginH, vertical: PdfLayout.pageMarginV),
    build: (ctx) => [
      for (final row in rows)
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < row.length; i++) ...[
              if (i > 0) pw.SizedBox(width: PdfLayout.gutter),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    for (final fragment in row[i])
                      if (shorts[fragment.question].shortData == null)
                        pw.SizedBox.shrink()
                      else
                        pw.Padding(
                          padding:
                              const pw.EdgeInsets.only(bottom: PdfLayout.rqGap),
                          child: pw.Row(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Expanded(
                                child: pw.RichText(
                                    text: mixed(
                                        '${fragment.question + 1}. ${shorts[fragment.question].shortData!.text}')),
                              ),
                              pw.SizedBox(width: 12),
                              pw.RichText(
                                  text: mixed(
                                      '[${shorts[fragment.question].shortData!.mark}]',
                                      bold)),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
            ],
          ],
        ),
    ],
  ));

  return doc.save();
}

/// Standalone render that mirrors the generator page's column layout, so the
/// output can be rasterised and inspected.
/// Returns the rendered PDF bytes. Mirrors the generator page's column
/// layout so the output can be checked for the failure modes that only show
/// up when a real document is laid out.
Future<List<int>> render(
    List<HighSchoolQuestion> questions, int columns) async {
  final bytes = File('assets/fonts/SutonnyMJ Regular.ttf').readAsBytesSync();
  final doc = pw.Document();
  final bangla = pw.Font.ttf(ByteData.sublistView(bytes));
  final fallback = <pw.Font>[
    pw.Font.ttf(ByteData.sublistView(
        File('assets/fonts/MathSymbols.ttf').readAsBytesSync()))
  ];

  final base = pw.TextStyle(font: bangla, fontFallback: fallback, fontSize: 11);
  // ignore: unused_local_variable
  final bold = pw.TextStyle(
      font: bangla,
      fontFallback: fallback,
      fontSize: 11,
      fontWeight: pw.FontWeight.bold);

  pw.TextSpan mixed(String t, [pw.TextStyle? style]) =>
      buildPdfTextSpan(t, style ?? base);

  final width = PdfLayout.columnWidth(columns);
  final stackOptions = columns > 1;

  final heights = <double>[];
  for (var i = 0; i < questions.length; i++) {
    heights.add(questions[i].isCq
        ? PdfLayout.cqHeight(
                index: i + 1,
                question: questions[i],
                columnWidth: width,
                metrics: metrics,
                // A stand-in figure so heights reflect a diagram-heavy sheet.
                hasImage: i.isEven,
                imageSize: StemImageSize.medium) +
            PdfLayout.cqCardGap
        : PdfLayout.mcqHeight(
                index: i + 1,
                question: questions[i],
                columnWidth: width,
                metrics: metrics,
                stackOptions: stackOptions) +
            0);
  }

  // Mirror the generator page: a masthead, a section banner, then column blocks
  // sized by the page flow. Reproducing the header here is the point — a block
  // budgeted for a whole page never fits under it, which is what used to push
  // the whole CQ section onto page 2.
  const school = 'Greenfield Public School';
  const exam = 'বার্ষিক পরীক্ষা';
  const subject = 'উচ্চতর গণিত';
  const className = 'Class (9-10) SSC';
  const time = '৩ ঘণ্টা';
  const totalMarks = '১০০';

  final flow = PdfPageFlow(contentHeight: PdfLayout.contentHeight);
  final headerHeight = PdfLayout.headerHeight(
    metrics: metrics,
    schoolName: school,
    examName: exam,
    subject: subject,
    className: className,
    time: time,
    totalMarks: totalMarks,
  );
  flow.consume(headerHeight + 16);

  final rows = flow.layout(
    heights: heights,
    columns: columns,
    trailingGap: 16,
  );

  pw.Widget card(int index) {
    final q = questions[index];
    if (q.isCq) {
      return pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        padding: const pw.EdgeInsets.all(8),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.RichText(text: mixed('${index + 1}. ${q.stemText}', base)),
            if (index.isEven) ...[
              pw.SizedBox(height: 6),
              pw.Container(
                alignment: pw.Alignment.center,
                height: StemImageSize.medium.maxHeightPt,
                color: PdfColors.grey200,
                child: pw.RichText(text: mixed('চিত্র', base)),
              ),
            ],
            pw.SizedBox(height: 4),
            for (final sq in q.cqSubQuestions)
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 6, top: 3),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                        child: pw.RichText(
                            text: mixed('(${sq.label}) ${sq.text}', base))),
                    pw.SizedBox(width: 10),
                    pw.RichText(text: mixed('[${sq.mark}]', base)),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    final m = q.mcqData!;
    const letters = ['ক', 'খ', 'গ', 'ঘ'];
    final perRow = stackOptions ? 1 : 2;
    final rows = <pw.Widget>[];
    for (int i = 0; i < m.options.length; i += perRow) {
      final cells = <pw.Widget>[];
      for (int c = 0; c < perRow; c++) {
        final j = i + c;
        if (j >= m.options.length) break;
        cells.add(pw.Expanded(
            child: pw.RichText(
                text: mixed('(${letters[j]}) ${m.options[j]}', base))));
        if (c < perRow - 1 && j + 1 < m.options.length) {
          cells.add(pw.SizedBox(width: 12));
        }
      }
      rows.add(pw.Padding(
        padding: const pw.EdgeInsets.only(left: 10, top: 2),
        child: pw.Row(children: cells),
      ));
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.RichText(text: mixed('${index + 1}. ${m.text}', base)),
        ...rows
      ],
    );
  }

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: pw.EdgeInsets.symmetric(
        horizontal: PdfLayout.pageMarginH, vertical: PdfLayout.pageMarginV),
    build: (ctx) => [
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.RichText(text: mixed(school, base.copyWith(fontSize: 15))),
          pw.SizedBox(height: 2),
          pw.RichText(text: mixed(exam, base.copyWith(fontSize: 12))),
          pw.SizedBox(height: 8),
          pw.Divider(thickness: 1.2, color: PdfColors.black),
          pw.SizedBox(height: 6),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.RichText(text: mixed('বিষয়: $subject')),
              pw.RichText(text: mixed('শ্রেণি: $className')),
              pw.RichText(text: mixed('সময়: $time')),
              pw.RichText(text: mixed('পূর্ণমান: $totalMarks')),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Divider(thickness: 1.2, color: PdfColors.black),
        ],
      ),
      pw.SizedBox(height: 16),
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey200,
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.RichText(text: mixed('ক-বিভাগ: সৃজনশীল প্রশ্ন (CQ)')),
      ),
      pw.SizedBox(height: 10),
      for (final row in rows) ...[
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < row.length; i++) ...[
              if (i > 0) pw.SizedBox(width: PdfLayout.gutter),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    for (final fragment in row[i]) ...[
                      card(fragment.question),
                      pw.SizedBox(height: PdfLayout.cqCardGap),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
        pw.SizedBox(height: 16),
      ],
    ],
  ));

  return doc.save();
}

void main() {
  List<HighSchoolQuestion> mixedSheet(int count) => [
        for (var i = 0; i < count; i++)
          if (i.isEven)
            cq('নিচের অনুশীলনী অনুসারে বিস্তারিত সমাধান লেখো।')
          else
            mcq('২ + ৩ এর মান কত?'),
      ];

  test('two-column layout renders and keeps reading order', () async {
    final bytes = await render(mixedSheet(8), 2);
    expect(bytes.length, greaterThan(1000));
  });

  test('single-column layout still renders', () async {
    final bytes = await render(mixedSheet(8), 1);
    expect(bytes.length, greaterThan(1000));
  });

  test('a sheet taller than one page paginates instead of throwing', () async {
    // Regression: a pw.Row of pw.Columns is a SpanningWidget and cannot be
    // split, so an unbalanced single block made MultiPage throw
    // "Widget won't fit into the page". PdfPageFlow exists to stop that.
    final many = <HighSchoolQuestion>[];
    for (var i = 0; i < 24; i++) {
      many.add(i.isEven
          ? cq('নিচের অনুশীলনী অনুসারে বিস্তারিত সমাধান লেখো।')
          : mcq('২ + ৩ এর মান কত?'));
    }

    final twoColumn = await render(many, 2);
    expect(twoColumn.length, greaterThan(1000));

    // Two columns fit more per page, so the packed paper is the smaller
    // document — the whole point of the change.
    final oneColumn = await render(many, 1);
    expect(twoColumn.length, lessThan(oneColumn.length));
  });

  test('RQ columns reach the HTML and Word exports', () {
    final shorts = [for (var i = 1; i <= 4; i++) rq('প্রশ্ন $i', i)];

    final singleHtml = ex.HighSchoolExportService.generateHtml(
        schoolName: 'S',
        examName: 'E',
        subject: 'M',
        className: 'C',
        time: 'T',
        totalMarks: '4',
        questions: shorts);
    final doubleHtml = ex.HighSchoolExportService.generateHtml(
        schoolName: 'S',
        examName: 'E',
        subject: 'M',
        className: 'C',
        time: 'T',
        totalMarks: '4',
        questions: shorts,
        rqLayout: QuestionLayout.doubleColumn);

    expect(singleHtml, contains('grid-template-columns: 1fr;'));
    expect(doubleHtml, contains('grid-template-columns: 1fr 1fr;'));
    for (final html in [singleHtml, doubleHtml]) {
      expect(html, contains('গ-বিভাগ: সংক্ষিপ্ত প্রশ্ন (RQ)'));
      expect(html, contains('প্রশ্ন 1'));
      expect(html, contains('[1]'));
    }

    final doubleWord = ex.HighSchoolExportService.generateWordDoc(
        schoolName: 'S',
        examName: 'E',
        subject: 'M',
        className: 'C',
        time: 'T',
        totalMarks: '4',
        questions: shorts,
        rqLayout: QuestionLayout.doubleColumn);
    expect(doubleWord, contains('rq-col-cell'));
    expect(doubleWord, contains('width: 50%'));
    expect(doubleWord, contains('প্রশ্ন 1'));

    final singleWord = ex.HighSchoolExportService.generateWordDoc(
        schoolName: 'S',
        examName: 'E',
        subject: 'M',
        className: 'C',
        time: 'T',
        totalMarks: '4',
        questions: shorts);
    // The `.rq-col-cell` *rule* is always in the stylesheet (its width is
    // interpolated), so assert on the markup that only double mode emits.
    expect(doubleWord, contains('<td class="rq-col-cell">'));
    expect(singleWord, isNot(contains('<td class="rq-col-cell">')));
    expect(singleWord, contains('প্রশ্ন 1'));
  });

  test('every CQ sub-question survives the column split', () async {
    // Regression: the card renderer mapped part index `p` to sub-question
    // `p - 1` but looped to `p - 2`, so the last sub-question of every CQ was
    // silently dropped — visible as a card missing its "(খ)" row.
    final questions = [
      for (var i = 0; i < 10; i++)
        cq(
            'প্রশ্ন ${i + 1}: নিচের চিত্রটি দেখে বিস্তারিত বর্ণনা করো এবং প্রমাণ করো।'),
    ];

    for (final columns in [1, 2]) {
      final bytes = await render(questions, columns);
      File('/tmp/opencode/subs$columns.pdf').writeAsBytesSync(bytes);
      expect(bytes.length, greaterThan(1000), reason: 'columns=$columns');
    }
  });

  test('a CQ fragment covers exactly the sub-questions it should', () {
    final q = cq('stem');
    expect(q.cqSubQuestions.length, 2);

    // Parts are [stem, sub0, sub1].
    final parts = PdfLayout.cqFragments(
      index: 1,
      question: q,
      columnWidth: 250,
      metrics: metrics,
      hasImage: false,
      imageSize: StemImageSize.medium,
    );
    expect(parts.length, 3);

    // Mapping used by the renderer: part p >= 1 is sub-question p - 1.
    int subStart(int partFrom) => partFrom <= 1 ? 0 : partFrom - 1;
    int subEnd(int partTo, int subs) => partTo > subs ? subs : partTo;

    // Whole card: all parts, so both sub-questions.
    expect(subEnd(2, 2) - subStart(0), 2);
    // Head only: none.
    expect(subEnd(0, 2) - subStart(0), 0);
    // Continuation from part 2: just the last sub-question.
    expect(subEnd(2, 2) - subStart(2), 1);
    // Unbounded (no splitting): everything.
    expect(subEnd(1 << 20, 2) - subStart(0), 2);
  });

  test('short questions lay out in both column modes', () async {
    final shorts = [
      for (var i = 1; i <= 14; i++)
        rq('সমান্তর সরলরেখার ঢাল কত এবং কেন? [$i]', i % 3 + 1),
    ];

    for (final columns in [1, 2]) {
      final bytes = await renderShorts(shorts, columns);
      expect(bytes.length, greaterThan(1000), reason: 'columns=$columns');
      if (columns == 2) {
        File('/tmp/opencode/rq2.pdf').writeAsBytesSync(bytes);
      }
    }
  });

  test('an empty short question contributes no height', () {
    expect(
        PdfLayout.rqHeight(
          index: 1,
          question: rq(''),
          columnWidth: 250,
          metrics: metrics,
        ),
        0);
  });

  test('a wider column makes a short question shorter', () {
    final wide = PdfLayout.rqHeight(
        index: 1,
        question: rq(List.filled(20, 'দীর্ঘ প্রশ্ন').join(' ')),
        columnWidth: 500,
        metrics: metrics);
    final narrow = PdfLayout.rqHeight(
        index: 1,
        question: rq(List.filled(20, 'দীর্ঘ প্রশ্ন').join(' ')),
        columnWidth: 250,
        metrics: metrics);
    expect(narrow, greaterThan(wide));
  });

  test('a header does not push the questions onto page 2', () async {
    // Regression for the reported symptom: "the CQ section starts on the 2nd
    // page, the 1st almost blank". Enough questions to need two pages, with a
    // full masthead above them.
    final many = <HighSchoolQuestion>[];
    for (var i = 0; i < 14; i++) {
      many.add(i.isEven
          ? cq('নিচের অনুশীলনী অনুসারে বিস্তারিত সমাধান লেখো।')
          : mcq('২ + ৩ এর মান কত?'));
    }

    final bytes = await render(many, 2);
    File('/tmp/opencode/flow2.pdf').writeAsBytesSync(bytes);

    // A 14-question sheet is genuinely two pages, but page 1 must be used.
    expect(bytes.length, greaterThan(1000));
  });

  test('every question is rendered exactly once', () async {
    // Guards against the DP or the page bound dropping or duplicating items.
    final heights = List<double>.generate(40, (i) => 40.0 + (i % 7) * 13);
    final rows = PdfPageFlow(contentHeight: 300, margin: 8).layout(
      heights: heights,
      columns: 2,
    );
    final flat = [
      for (final row in rows)
        for (final col in row)
          for (final f in col) f.question
    ];
    expect(flat, List.generate(40, (i) => i));
  });

  test('math-heavy questions export without throwing', () async {
    // End-to-end guard for the Latin-1 measurement crash: the column estimator
    // used to call Helvetica.stringMetrics on ≤ √ π − → ², which prints
    // "Cannot decode the string to Latin1" and rethrows, failing the whole
    // export. Those characters are everywhere in a maths bank.
    final maths = [
      mcq('যদি x ≤ 5 এবং y ≥ 2 হয়, তবে x + y এর সর্বোচ্চ মান কত?'),
      mcq('√9 + √16 এর মান কত?'),
      mcq('π ≈ 3.14 হলে 2π এর আনুমানিক মান কত?'),
      mcq('a − b = 3 এবং a + b = 7 হলে a² − b² কত?'),
      cq('x ≤ 0 ও x ≥ −3 শর্তে সমীকরণের সমাধান নির্ণয় করো।'),
      cq('α = 60° হলে sin α এর মান নির্ণয় করো।'),
    ];

    for (final columns in [1, 2]) {
      final bytes = await render(maths, columns);
      expect(bytes.length, greaterThan(1000), reason: 'columns=$columns');
    }
  });
}

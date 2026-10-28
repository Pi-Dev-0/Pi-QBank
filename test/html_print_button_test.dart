// Printing a sheet.
//
// The exported .html file is meant to be opened in a browser, so the sheet
// carries its own print button: it prints the page as it stands, live edits and
// all. Inside the app the preview page also offers a print action in its app
// bar; this file only locks down the sheet half, because the two ends live in
// different layers and the browser fallback must keep working even when no app
// host is involved.
import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/models/highschool_question.dart';
import 'package:pi_qbank/services/highschool_export_service.dart';

HighSchoolQuestion rq() => HighSchoolQuestion.fromJson({
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
    });

String sheetHtml({PaperPrintSettings printSettings = const PaperPrintSettings()}) =>
    HighSchoolExportService.generateHtml(
      schoolName: 'S',
      examName: 'E',
      subject: 'গণিত',
      className: 'C',
      time: 'T',
      totalMarks: '10',
      questions: [rq()],
      printSettings: printSettings,
    );

void main() {
  group('the sheet print button', () {
    test('is present and labelled', () {
      final html = sheetHtml();

      expect(html, contains('id="printBtn"'));
      expect(html, contains('প্রিন্ট করুন'));
    });

    test('prints the page it is on', () {
      final html = sheetHtml();

      // The handler is wired rather than inlined, so the click prints the
      // current document instead of reloading or exporting a stale copy.
      expect(html, contains("printBtn.addEventListener('click'"));
      expect(html, contains('window.print()'));
    });

    test('belongs to the screen-only toolbar', () {
      final html = sheetHtml();

      expect(html, contains('.no-print-toolbar'));
      expect(html, contains('class="no-print-toolbar"'));
    });

    test('survives every print setting', () {
      final html = sheetHtml(
        printSettings: const PaperPrintSettings(
          paperSize: PaperSize.legal,
          pageNumbers: true,
          editingMode: true,
          showWatermark: true,
          watermarkText: 'DRAFT',
        ),
      );

      expect(html, contains('id="printBtn"'));
      expect(html, contains('window.print()'));
    });
  });
}

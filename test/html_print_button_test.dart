// Printing a sheet from inside the app.
//
// The sheet prints itself in a browser — the page as it stands, live edits and
// all. Inside the app's preview it cannot: an Android WebView has no print
// support at all, so `window.print()` does nothing and the button looked broken
// on a phone. The button now asks the host over a JavaScript channel when one
// exists, and the host prints the paper through the app's own PDF path.
//
// What is locked down here: the browser fallback still works (the exported file
// is meant to be printed from a browser), the sheet asks for the print rather
// than doing it when a host is listening, and the channel name the sheet posts
// to is the one the preview page registers — the two are in different files and
// silently drifting apart would put the dead button back.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/models/highschool_question.dart';
import 'package:pi_qbank/pages/question_paper_preview_page.dart';
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

String sheetHtml() => HighSchoolExportService.generateHtml(
      schoolName: 'S',
      examName: 'E',
      subject: 'গণিত',
      className: 'C',
      time: 'T',
      totalMarks: '10',
      questions: [rq()],
    );

Widget preview({Future<void> Function()? onPrint}) => MaterialApp(
      home: QuestionPaperPreviewPage(
        schoolName: 'S',
        examName: 'E',
        subject: 'গণিত',
        className: 'C',
        time: 'T',
        totalMarks: '10',
        questions: [rq()],
        onPrint: onPrint,
      ),
    );

void main() {
  group('the sheet', () {
    test('the print button no longer prints by itself', () {
      final html = sheetHtml();

      expect(html, contains('id="printBtn"'));
      expect(html, isNot(contains('onclick="window.print()"')));
    });

    test('it asks the host when there is one, and prints itself when not', () {
      final html = sheetHtml();

      expect(html,
          contains("if (window.${QuestionPaperPreviewPage.printChannel})"));
      expect(html, contains('postMessage'));
      // The browser fallback has to stay: an exported file is opened in a
      // browser, where no host is listening and printing is the browser's job.
      expect(html, contains('else window.print()'));
    });

    test('the channel the sheet calls is the one the app answers', () {
      // The two ends live in different files; a rename on one side alone would
      // put the dead button back on Android.
      expect(QuestionPaperPreviewPage.printChannel, 'PiQBankPrint');
      expect(sheetHtml(), contains(QuestionPaperPreviewPage.printChannel));
    });
  });

  group('the preview page', () {
    testWidgets('offers the app print when a host hands it one', (tester) async {
      await tester.pumpWidget(preview(onPrint: () async {}));
      await tester.pumpAndSettle();

      expect(find.byTooltip('প্রিন্ট / PDF সংরক্ষণ'), findsOneWidget);
    });

    testWidgets('keeps its own hand off printing when no host is there',
        (tester) async {
      // A sheet rendered without a host prints itself; the page must not offer
      // a print it cannot do.
      await tester.pumpWidget(preview());
      await tester.pumpAndSettle();

      expect(find.byTooltip('প্রিন্ট / PDF সংরক্ষণ'), findsNothing);
      expect(find.byTooltip('প্রিভিউ রিফ্রেশ করুন'), findsOneWidget);
    });
  });
}

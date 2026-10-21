// The CQ instruction — "যেকোনো ৫ টি প্রশ্নের উত্তর দাও" — is written once in
// the app and has to reach the paper. The sheet's masthead is the one band
// that states what the paper wants, so the instruction rides there, on a line
// of its own between the two rules.
//
// A blank instruction leaves the paper as it was: the band carries the meta
// line and nothing else.
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

String htmlOf(List<HighSchoolQuestion> questions, {String cqInstruction = ''}) =>
    HighSchoolExportService.generateHtml(
      schoolName: 'S',
      examName: 'E',
      subject: 'গণিত',
      className: 'C',
      time: 'T',
      totalMarks: '10',
      questions: questions,
      cqInstruction: cqInstruction,
    );

void main() {
  final questions = [cqTest('প্রশ্ন এক')];

  test('the instruction rides in the masthead, between the rules', () {
    final html = htmlOf(questions, cqInstruction: 'যেকোনো ৫ টি প্রশ্নের উত্তর দাও');

    expect(html, contains('যেকোনো ৫ টি প্রশ্নের উত্তর দাও'));
    // It sits inside the bar, on a line of its own.
    expect(html, contains('class="meta-note"'));

    final barAt = html.indexOf('class="meta-bar"');
    final noteAt = html.indexOf('class="meta-note"');
    expect(noteAt, greaterThan(barAt));
    // The note is the last thing in the bar, so the bar closes right after
    // it — the instruction rides inside the band, not after it.
    final noteEnd = html.indexOf('</div>', noteAt);
    final barEnd = html.indexOf('</div>', noteEnd + 6);
    expect(html.substring(noteEnd + 6, barEnd).trim(), isEmpty);
  });

  test('a blank instruction leaves the band as it was', () {
    final html = htmlOf(questions);

    expect(html, isNot(contains('class="meta-note"')));
    // The meta line itself is untouched.
    expect(html, contains('বিষয়: গণিত'));
    expect(html, contains('পূর্ণমান: 10'));
  });

  test('every set in a two-set paper carries the instruction', () {
    final html = HighSchoolExportService.generateHtml(
      schoolName: 'S',
      examName: 'E',
      subject: 'গণিত',
      className: 'C',
      time: 'T',
      totalMarks: '10',
      questions: questions,
      setLabels: const ['ক', 'খ'],
      cqInstruction: 'যেকোনো ২ টি প্রশ্নের উত্তর দাও',
    );

    expect(
      'class="meta-note"'.allMatches(html).length,
      2,
      reason: 'both sets of the paper say the same thing',
    );
  });
}

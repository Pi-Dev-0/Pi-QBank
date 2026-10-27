// The desktop print-settings panel writes its choices into the same HTML the
// export and the preview use. These tests hold the writer to the panel's
// promises: the paper stock changes the canvas, the header switches remove
// their lines, and the branding/helper options reach the sheet.
import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/models/highschool_question.dart';
import 'package:pi_qbank/services/highschool_export_service.dart';

HighSchoolQuestion mcq({bool important = false}) =>
    HighSchoolQuestion.fromJson({
      'id': 'mcq',
      'class': 'Class (9-10) SSC',
      'subject': 'গণিত',
      'chapter_number': '1',
      'chapter_name': 'অনুশীলনী',
      'question_type': 'MCQ',
      'stem_text': '',
      'stem_image_url': '',
      'sub_questions_json': {
        'text': 'নিচের কোনটি সঠিক?',
        'options': const ['৩', '৪', '৫', '৬'],
        'correct_ans': '৩',
      },
      'board_year_tag': 'বোর্ড ২০২৩',
    })
      ..isImportant = important;

String sheet(PaperPrintSettings settings) =>
    HighSchoolExportService.generateHtml(
      schoolName: 'স্কুল',
      examName: 'পরীক্ষা',
      subject: 'গণিত',
      className: 'দশম',
      time: '২ ঘণ্টা',
      totalMarks: '১০০',
      questions: [mcq()],
      printSettings: settings,
    );

/// The body of the generated file, without the stylesheet and scripts.
String bodyOf(String html) => html.split('</style>').last.split('<script>').first;

void main() {
  test('paper size changes the canvas and the page box', () {
    final html = sheet(const PaperPrintSettings(paperSize: PaperSize.a5));
    expect(html, contains('width: 148mm'));
    expect(html, contains('min-height: 210mm'));
    expect(html, contains('@page { size: A5;'));
  });

  test('header switches remove their masthead lines', () {
    final html = bodyOf(sheet(const PaperPrintSettings(
      showSchool: false,
      showExam: false,
      showSubject: false,
      showClass: false,
      showSet: false,
      showInstructions: false,
    )));
    expect(html, isNot(contains('<div class="school-title">')));
    expect(html, isNot(contains('<div class="exam-title">')));
    expect(html, isNot(contains('>বিষয়:')));
    expect(html, isNot(contains('>শ্রেণি:')));
    expect(html, isNot(contains('>সেট:')));
  });

  test('the header switches keep the lines they are set to keep', () {
    final html = bodyOf(sheet(const PaperPrintSettings(
      showSubject: true,
      showClass: true,
      showExam: true,
    )));
    expect(html, contains('>বিষয়:'));
    expect(html, contains('>শ্রেণি:'));
    expect(html, contains('<div class="exam-title">'));
  });

  test('branding, student info, subject code and obtained marks', () {
    final html = bodyOf(sheet(const PaperPrintSettings(
      showHeader: true,
      showFooter: true,
      showWatermark: true,
      showAddress: true,
      showStudentInfo: true,
      showObtainedMarks: true,
      showSubjectCode: true,
      showChapter: true,
      showQuestionInfo: true,
      address: 'ঢাকা',
      watermarkText: 'নমুনা',
      subjectCode: '১০১',
      chapter: 'অনুশীলনী',
    )));
    expect(html, contains('<div class="brand-header">'));
    expect(html, contains('<div class="brand-footer">'));
    expect(html, contains('<div class="watermark">নমুনা</div>'));
    expect(html, contains('ঢাকা'));
    expect(html, contains('<div class="student-info">'));
    expect(html, contains('<div class="obtained-marks">'));
    expect(html, contains('বিষয় কোড: ১০১'));
    expect(html, contains('অধ্যায়: অনুশীলনী'));
    expect(html, contains('<div class="question-info">'));
  });

  test('option style and the column divider reach the CSS and options', () {
    final html = sheet(const PaperPrintSettings(
      optionStyle: McqOptionStyle.dot,
      columnDivider: false,
      columnGap: 12,
    ));
    expect(html, contains('ক. ৩'));
    expect(html, contains('column-rule: none'));
    expect(html, contains('column-gap: 12px'));
  });

  test('page numbers and editing mode', () {
    final html = sheet(const PaperPrintSettings(
      pageNumbers: true,
      editingMode: true,
    ));
    expect(html, contains('@bottom-center'));
    expect(html, contains('counter(page, bengali)'));
    expect(html, contains('contenteditable="true"'));
  });

  test('important questions print a star only while the switch is on', () {
    String htmlFor(PaperPrintSettings settings) =>
        HighSchoolExportService.generateHtml(
          schoolName: 'S',
          examName: 'E',
          subject: 'S',
          className: 'C',
          time: 'T',
          totalMarks: '10',
          questions: [mcq(important: true)],
          printSettings: settings,
        );

    expect(htmlFor(const PaperPrintSettings(showImportant: true)),
        contains('<span class="important-star">'));
    expect(htmlFor(const PaperPrintSettings()),
        isNot(contains('<span class="important-star">')));
  });

  test('the question-info switch adds the chapter and board line', () {
    final withInfo = bodyOf(sheet(const PaperPrintSettings(
      showQuestionInfo: true,
    )));
    final without = bodyOf(sheet(const PaperPrintSettings()));
    expect(withInfo, contains('অধ্যায়: অনুশীলনী'));
    expect(withInfo, contains('বোর্ড ২০২৩'));
    expect(without, isNot(contains('<div class="question-info">')));
  });

  test('the A button line reaches the masthead', () {
    final html = bodyOf(sheet(const PaperPrintSettings(
      headerNote: 'শিক্ষা সপ্তাহ ২০২৬',
    )));
    expect(html, contains('<div class="header-note">শিক্ষা সপ্তাহ ২০২৬</div>'));
  });

  test('the student-info and obtained-marks switches are independent', () {
    final onlyStudent = bodyOf(sheet(const PaperPrintSettings(
      showStudentInfo: true,
    )));
    expect(onlyStudent, contains('<div class="student-info">'));
    expect(onlyStudent, isNot(contains('<div class="obtained-marks">')));
  });

  test('a logo is embedded as a data URI in the header band', () {
    final html = bodyOf(sheet(const PaperPrintSettings(
      showHeader: true,
      showLogo: true,
      logoDataUri: 'data:image/png;base64,AAAA',
    )));
    expect(html, contains('class="brand-logo"'));
    expect(html, contains('data:image/png;base64,AAAA'));
  });
}

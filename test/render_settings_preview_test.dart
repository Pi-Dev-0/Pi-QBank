// Writes a full settings-on sheet to /tmp so the layout can be eyeballed in a
// browser. Not a behavioural test: it always passes and is skipped unless
// RENDER_SETTINGS_PREVIEW=1 is set.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/models/highschool_question.dart';
import 'package:pi_qbank/services/highschool_export_service.dart';

HighSchoolQuestion cq() => HighSchoolQuestion.fromJson({
      'id': 'cq1',
      'class': 'Class (9-10) SSC',
      'subject': 'গণিত',
      'chapter_number': '11',
      'chapter_name': 'পরিসংখ্যান',
      'question_type': 'CQ',
      'stem_text': 'একটি শ্রেণিতে ৪০ জন শিক্ষার্থীর গণিতে প্রাপ্ত নম্বরের তালিকা নিচে দেওয়া আছে।',
      'stem_image_url': 'https://upload.wikimedia.org/wikipedia/commons/thumb/4/47/PNG_transparency_demonstration_1.png/280px-PNG_transparency_demonstration_1.png',
      'sub_questions_json': [
        {'label': 'ক', 'mark': 2, 'text': 'উপাত্তগুলো বিন্যস্ত করো।'},
        {'label': 'খ', 'mark': 4, 'text': 'প্রচুরক নির্ণয় করো।'},
        {'label': 'গ', 'mark': 4, 'text': 'গড় নির্ণয় করো।'},
      ],
      'board_year_tag': 'বোর্ড ২০২৩',
    })
      ..isImportant = true;

HighSchoolQuestion mcq(String id, String text) => HighSchoolQuestion.fromJson({
      'id': id,
      'class': 'Class (9-10) SSC',
      'subject': 'গণিত',
      'chapter_number': '11',
      'chapter_name': 'পরিসংখ্যান',
      'question_type': 'MCQ',
      'stem_text': '',
      'stem_image_url': '',
      'sub_questions_json': {
        'text': text,
        'options': const ['৪', '৫', '৬', '৭'],
        'correct_ans': '৫',
      },
      'board_year_tag': 'বোর্ড ২০২২',
    })
      ..isImportant = true;

HighSchoolQuestion rq(String id, String text) => HighSchoolQuestion.fromJson({
      'id': id,
      'class': 'Class (9-10) SSC',
      'subject': 'গণিত',
      'chapter_number': '11',
      'chapter_name': 'পরিসংখ্যান',
      'question_type': 'RQ',
      'stem_text': text,
      'stem_image_url': '',
      'sub_questions_json': <Object>[],
      'board_year_tag': '',
      'short_mark': 1,
    });

void main() {
  test('render settings preview', () {
    if (Platform.environment['RENDER_SETTINGS_PREVIEW'] != '1') return;
    final html = HighSchoolExportService.generateHtml(
      schoolName: 'শহীদ স্মৃতি উচ্চ বিদ্যালয়',
      examName: 'বার্ষিক পরীক্ষা ২০২৬',
      subject: 'সাধারণ গণিত',
      className: 'অষ্টম',
      time: '২ ঘণ্টা ৩০ মিনিট',
      totalMarks: '১০০',
      questions: [
        cq(),
        mcq('m1', 'নিচের কোনটি পরিসংখ্যানের পরিমাপ?'),
        mcq('m2', 'উপাত্তের সর্বোচ্চ মানকে কী বলে?'),
        rq('r1', 'গড় কী?'),
        rq('r2', 'প্রচুরক কাকে বলে?'),
      ],
      cqInstruction: 'যেকোনো ২টি প্রশ্নের উত্তর দাও।',
      printSettings: const PaperPrintSettings(
        paperSize: PaperSize.a4,
        textAlign: PaperTextAlign.justify,
        pageNumbers: true,
        optionStyle: McqOptionStyle.parentheses,
        columnDivider: true,
        questionGap: 6,
        columnGap: 15,
        showHeader: true,
        showFooter: true,
        showWatermark: true,
        showAddress: true,
        showStudentInfo: true,
        showObtainedMarks: true,
        showSubjectCode: true,
        showChapter: true,
        showQuestionInfo: true,
        showImportant: true,
        editingMode: true,
        address: '১২৩ শিক্ষা সড়ক, ঢাকা',
        watermarkText: 'নমুনা',
        subjectCode: '১০১',
        chapter: 'পরিসংখ্যান',
      ),
      desktopMode: true,
    );
    File('/tmp/opencode/settings_preview.html').writeAsStringSync(html);
  });
}

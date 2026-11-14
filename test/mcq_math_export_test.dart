import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/models/highschool_question.dart';
import 'package:pi_qbank/services/highschool_export_service.dart';

HighSchoolQuestion radicalMcq() => HighSchoolQuestion.fromJson({
      'id': 'm1',
      'class': 'Class (9-10) SSC',
      'subject': 'গণিত',
      'chapter_number': '1',
      'chapter_name': 'অনুশীলনী',
      'question_type': 'MCQ',
      'stem_text': '',
      'stem_image_url': '',
      'sub_questions_json': {
        'text':
            r'3(x^2 + y^2) এবং \sqrt{2}, 7\sqrt{2} বিশিষ্ট সংখ্যাগুলো কোন ধরনের?',
        'options': const ['১ম', '২য়', '৩য়', '৪র্থ'],
        'correct_ans': '১ম',
      },
      'board_year_tag': '',
    });

void main() {
  test('an MCQ question is typeset in both the HTML and Word sheets', () {
    final html = HighSchoolExportService.generateHtml(
      schoolName: 'S',
      examName: 'E',
      subject: 'গণিত',
      className: 'C',
      time: 'T',
      totalMarks: '10',
      questions: [radicalMcq()],
    );
    final word = HighSchoolExportService.generateWordDoc(
      schoolName: 'S',
      examName: 'E',
      subject: 'গণিত',
      className: 'C',
      time: 'T',
      totalMarks: '10',
      questions: [radicalMcq()],
    );

    for (final sheet in [html, word]) {
      expect(sheet, contains('<sup>2</sup>'));
      expect(sheet, contains('<span class="radical'));
      expect(sheet, contains('<span class="radical-body">2</span>'));
      expect(sheet, isNot(contains(r'\sqrt')));
    }
  });
}

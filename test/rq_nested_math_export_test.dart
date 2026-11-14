import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/models/highschool_question.dart';
import 'package:pi_qbank/services/highschool_export_service.dart';

HighSchoolQuestion nestedFractionRq() => HighSchoolQuestion.fromJson({
      'id': 'rq1',
      'class': 'Class 8',
      'subject': 'সাধারণ গণিত',
      'chapter_number': '6',
      'chapter_name': 'সরল সহসমীকরণ',
      'question_type': 'RQ',
      'stem_text':
          r'x + \frac{3x}{\frac{a}{b}} = 2 হলে, \frac{12x}{x^5 + 4x + 3} এর মান কত?',
      'stem_image_url': '',
      'sub_questions_json': '',
      'short_mark': 2,
      'board_year_tag': '',
    });

void main() {
  test('nested fractions and powers are typeset in an RQ export', () {
    final html = HighSchoolExportService.generateHtml(
      schoolName: 'S',
      examName: 'E',
      subject: 'সাধারণ গণিত',
      className: 'Class 8',
      time: 'T',
      totalMarks: '10',
      questions: [nestedFractionRq()],
    );
    final word = HighSchoolExportService.generateWordDoc(
      schoolName: 'S',
      examName: 'E',
      subject: 'সাধারণ গণিত',
      className: 'Class 8',
      time: 'T',
      totalMarks: '10',
      questions: [nestedFractionRq()],
    );

    for (final sheet in [html, word]) {
      expect(sheet, contains('<span class="frac-num">3x</span>'));
      expect(
          sheet,
          contains('<span class="frac-den"><span class="frac">'
              '<span class="frac-num">a</span>'));
      expect(sheet, contains('x<sup>5</sup> + 4x + 3'));
      expect(sheet, isNot(contains(r'\frac')));
      expect(sheet, isNot(contains('x^5')));
    }
  });
}

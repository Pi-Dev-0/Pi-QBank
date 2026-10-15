import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/models/highschool_question.dart';
import 'package:pi_qbank/services/highschool_export_service.dart';

void main() {
  test('set sharing preview', () {
    final raw = jsonDecode(
        File('/tmp/opencode/payloads/Class_(11-12)_HSC__তথ্য_ও_যোগাযোগ_প্রযুক্তি.json')
            .readAsStringSync());
    final rows = (raw['data'] as List).cast<Map<String, dynamic>>();
    final all = rows.map(HighSchoolQuestion.fromJson).toList();

    List<HighSchoolQuestion> take(bool Function(HighSchoolQuestion) f, int n) =>
        all.where(f).take(n).toList();

    String html(List<HighSchoolQuestion> picked) {
      for (var i = 0; i < picked.length; i++) {
        picked[i].setLabel = i.isEven ? 'ক' : 'খ';
      }
      return HighSchoolExportService.generateHtml(
        schoolName: 'গ্রীনফিল্ড পাবলিক স্কুল, ঢাকা',
        examName: 'বার্ষিক পরীক্ষা - ২০২৬',
        subject: 'তথ্য ও যোগাযোগ প্রযুক্তি',
        className: 'Class (11-12) HSC',
        time: '২ ঘন্টা ৩০ মিনিট',
        totalMarks: '১০০',
        questions: picked,
        setLabels: const ['ক', 'খ'],
        imageSize: StemImageSize.small,
        cqLayout: QuestionLayout.doubleColumn,
        rqLayout: QuestionLayout.doubleColumn,
        mcqLayout: QuestionLayout.doubleColumn,
      );
    }

    Directory('/tmp/opencode/html_preview').createSync(recursive: true);

    // A long pair: 4 CQ + 6 MCQ + 12 SQ across two sets.
    final big = [
      ...take((q) => q.isCq, 4),
      ...take((q) => q.isMcq, 6),
      ...take((q) => q.isShort, 12),
    ];
    File('/tmp/opencode/html_preview/twoset.html')
        .writeAsStringSync(html(big));

    // A short pair: one CQ a side, which should share a single page.
    final small = take((q) => q.isCq, 2);
    File('/tmp/opencode/html_preview/twoset_small.html')
        .writeAsStringSync(html(small));
  });
}

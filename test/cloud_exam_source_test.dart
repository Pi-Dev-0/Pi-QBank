import 'package:flutter_test/flutter_test.dart';
import 'package:pi_qbank/models/highschool_question.dart';
import 'package:pi_qbank/pages/cloud_tests_page.dart';
import 'package:pi_qbank/services/highschool_qbank_service.dart';

/// The page reads the question bank, so these cover the two contracts it
/// depends on: the shape the script actually returns, and that the app cannot
/// silently point at the wrong deployment.
void main() {
  group('a row from HighSchool_QBank', () {
    Map<String, dynamic> mcqRow() => {
          'id': 'm1',
          'class': 'Class (9-10) SSC',
          'subject': 'উচ্চতর গণিত',
          'chapter_number': '1',
          'chapter_name': 'সেট ও ফাংশন',
          'question_type': 'MCQ',
          'stem_text': '',
          'stem_image_url': '',
          'sub_questions_json':
              '{"text":"A নির্ণয় করো","options":["1","2"],"correct_ans":"2"}',
          'board_year_tag': '',
          'short_mark': '',
        };

    test('becomes an MCQ the exam can mark', () {
      final q = HighSchoolQuestion.fromJson(mcqRow());
      expect(q.isMcq, isTrue);
      expect(q.mcqData, isNotNull);
      expect(q.mcqData!.options, ['1', '2']);
      expect(q.mcqData!.correctAns, '2',
          reason: 'the script writes correct_ans; a wrong key here would '
              'mark every answer incorrect');
    });

    test('a CQ carries its sub-questions and their marks', () {
      final q = HighSchoolQuestion.fromJson({
        ...mcqRow(),
        'id': 'c1',
        'question_type': 'CQ',
        'stem_text': 'A ও B দেওয়া আছে',
        'sub_questions_json':
            '[{"label":"ক","mark":2,"text":"A∩B"},{"label":"খ","mark":3,"text":"A∪B"}]',
      });
      expect(q.isCq, isTrue);
      expect(q.cqSubQuestions, hasLength(2));
      expect(q.totalMarks, 5, reason: 'marks decide the exam duration');
    });

    test('a short question keeps its text and its own mark', () {
      final q = HighSchoolQuestion.fromJson({
        ...mcqRow(),
        'id': 's1',
        'question_type': 'RQ',
        'stem_text': 'ঢাল কত?',
        'sub_questions_json': '[]',
        'short_mark': '2',
      });
      expect(q.isShort, isTrue);
      expect(q.shortData?.text, 'ঢাল কত?');
      expect(q.totalMarks, 2);
    });

    test('unparseable sub-questions do not throw', () {
      // One bad row must not take the whole exam down. The model reads it as
      // "no MCQ payload" rather than guessing at a broken one.
      final q = HighSchoolQuestion.fromJson({
        ...mcqRow(),
        'sub_questions_json': '{not json',
      });
      expect(q.mcqData, isNull);
      expect(q.isMcq, isTrue, reason: 'the type still identifies it');
    });
  });

  group('the endpoint', () {
    test('is the question-bank deployment, not the old cloud-tests script', () {
      // The page used to point at a getTests endpoint that this sheet has
      // never served, which is why it could not load anything.
      expect(CloudTestsPage.scriptUrl, contains('/exec'));
      expect(CloudTestsPage.scriptUrl, contains('script.google.com/macros/s/'));
    });

    test('builds a valid request URI with class and subject', () {
      const service =
          HighSchoolQBankService(scriptUrl: CloudTestsPage.scriptUrl);
      final uri = service.buildRequestUriForTest({
        'action': 'getQuestions',
        'class': 'Class (9-10) SSC',
        'subject': 'উচ্চতর গণিত',
        'chapters': '1,3',
      });
      expect(uri.host, 'script.google.com');
      expect(uri.queryParameters['action'], 'getQuestions');
      expect(uri.queryParameters['class'], 'Class (9-10) SSC');
      expect(uri.queryParameters['chapters'], '1,3',
          reason: 'the script splits chapters on a comma');
    });

    test('refuses to build a URI from an empty URL', () {
      const service = HighSchoolQBankService(scriptUrl: '');
      expect(
        () => service.buildRequestUriForTest({'action': 'getChapters'}),
        throwsA(isA<QBankNotConfiguredException>()),
      );
    });
  });
}

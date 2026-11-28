// Question numbers follow the language of the question, not the app's own
// locale. A Bengali question prints ১, ২, ৩; an English question — or the
// English version of a Bengali subject — prints 1, 2, 3. The bank has no
// language column, so the row's subject and wording decide.
import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/models/highschool_question.dart';
import 'package:pi_qbank/services/highschool_export_service.dart';

HighSchoolQuestion cq({
  required String id,
  required String subject,
  required String stem,
  String subText = 'ব্যাখ্যা করো।',
}) =>
    HighSchoolQuestion.fromJson({
      'id': id,
      'class': 'Class (9-10) SSC',
      'subject': subject,
      'chapter_number': '1',
      'chapter_name': 'অনুশীলনী',
      'question_type': 'CQ',
      'stem_text': stem,
      'stem_image_url': '',
      'sub_questions_json': [
        {'label': 'ক', 'mark': 1, 'text': subText},
      ],
      'board_year_tag': '',
    });

HighSchoolQuestion mcq({
  required String id,
  required String subject,
  required String text,
  String stem = '',
  List<String> options = const ['ক', 'খ', 'গ', 'ঘ'],
}) =>
    HighSchoolQuestion.fromJson({
      'id': id,
      'class': 'Class (9-10) SSC',
      'subject': subject,
      'chapter_number': '1',
      'chapter_name': 'অনুশীলনী',
      'question_type': 'MCQ',
      'stem_text': stem,
      'stem_image_url': '',
      'sub_questions_json': {
        'text': text,
        'options': options,
        'correct_ans': options.first,
      },
      'board_year_tag': '',
    });

String htmlOf(List<HighSchoolQuestion> questions) =>
    HighSchoolExportService.generateHtml(
      schoolName: 'S',
      examName: 'E',
      subject: 'বিষয়',
      className: 'C',
      time: 'T',
      totalMarks: '10',
      questions: questions,
    );

String textOf(List<HighSchoolQuestion> questions) =>
    HighSchoolExportService.generatePlainText(
      schoolName: 'S',
      examName: 'E',
      subject: 'বিষয়',
      className: 'C',
      time: 'T',
      totalMarks: '10',
      questions: questions,
    );

String wordOf(List<HighSchoolQuestion> questions) =>
    HighSchoolExportService.generateWordDoc(
      schoolName: 'S',
      examName: 'E',
      subject: 'বিষয়',
      className: 'C',
      time: 'T',
      totalMarks: '10',
      questions: questions,
    );

String markdownOf(List<HighSchoolQuestion> questions) =>
    HighSchoolExportService.generateMarkdown(
      schoolName: 'S',
      examName: 'E',
      subject: 'বিষয়',
      className: 'C',
      time: 'T',
      totalMarks: '10',
      questions: questions,
    );

void main() {
  group('a Bengali question', () {
    test('prints Bengali question numbers in every export', () {
      final questions = [
        cq(id: 'a', subject: 'গণিত', stem: 'সমীকরণটি সমাধান করো।'),
        cq(id: 'b', subject: 'গণিত', stem: 'মান নির্ণয় করো।'),
      ];

      expect(questions.first.isEnglishQuestion, isFalse);
      expect(questions.first.questionNumber(12), '১২');

      final html = htmlOf(questions);
      expect(html, contains('<b>১.</b>'));
      expect(html, contains('<b>২.</b>'));

      final text = textOf(questions);
      expect(text, contains('১. '));
      expect(text, contains('২. '));

      final word = wordOf(questions);
      expect(word, contains('<b>১.</b>'));
      expect(word, contains('<b>২.</b>'));

      final markdown = markdownOf(questions);
      expect(markdown, contains('**১.**'));
      expect(markdown, contains('**২.**'));
    });
  });

  group('an English question', () {
    test('prints Latin question numbers in every export', () {
      final questions = [
        cq(
          id: 'a',
          subject: 'Mathematics',
          stem: 'Solve the equation.',
          subText: 'Explain your answer.',
        ),
        cq(
          id: 'b',
          subject: 'Mathematics',
          stem: 'Find the value.',
          subText: 'Show your work.',
        ),
      ];

      expect(questions.first.isEnglishQuestion, isTrue);
      expect(questions.first.questionNumber(12), '12');

      final html = htmlOf(questions);
      expect(html, contains('<b>1.</b>'));
      expect(html, contains('<b>2.</b>'));
      expect(html, isNot(contains('<b>১.</b>')));

      final text = textOf(questions);
      expect(text, contains('1. '));
      expect(text, contains('2. '));

      final word = wordOf(questions);
      expect(word, contains('<b>1.</b>'));
      expect(word, contains('<b>2.</b>'));

      final markdown = markdownOf(questions);
      expect(markdown, contains('**1.**'));
      expect(markdown, contains('**2.**'));
    });

    test('an English subject keeps Latin numbers even beside Bengali text', () {
      final q = cq(id: 'a', subject: 'English', stem: 'সমীকরণটি সমাধান করো।');

      expect(q.isEnglishQuestion, isTrue);
      expect(q.questionNumber(3), '3');
    });

    test('a Bengali subject with English wording is an English version', () {
      final q = mcq(
        id: 'a',
        subject: 'উচ্চতর গণিত',
        text: 'Which one is correct?',
        stem: 'Read the following information.',
        options: const ['A', 'B', 'C', 'D'],
      );

      expect(q.isEnglishQuestion, isTrue);
      expect(q.questionNumber(3), '3');
    });
  });

  test('a shared intro takes the question language when it has no reference',
      () {
    expect(
      HighSchoolExportService.stemWithNumbers('Answer ({}) নং', [1, 2],
          bengali: false),
      'Answer (1 and 2) নং',
    );
    expect(
      HighSchoolExportService.stemWithNumbers('Answer ({}) নং', [1, 2],
          bengali: true),
      'Answer (১ ও ২) নং',
    );
  });
}

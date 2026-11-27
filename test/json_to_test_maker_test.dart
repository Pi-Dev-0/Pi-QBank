import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pi_qbank/services/test_share_service.dart';
import 'package:pi_qbank/utils/ai_test_prompt.dart';
import 'package:pi_qbank/utils/test_json.dart';
import 'package:pi_qbank/utils/test_samples.dart';

void main() {
  group('cleanAiJson', () {
    test('strips markdown fences and surrounding prose', () {
      const raw = '''
Here is the JSON:
```json
{"topic":"Fractions","questions":[{"question":"1/2 + 1/2?","answer":"1"}]}
```
Thanks!''';

      expect(
        cleanAiJson(raw),
        '{"topic":"Fractions","questions":[{"question":"1/2 + 1/2?","answer":"1"}]}',
      );
    });

    test('keeps braces inside strings', () {
      const raw = '{"question":"What is {x}?","answer":"y"}';
      expect(cleanAiJson(raw), raw);
    });

    test('rejects an incomplete object', () {
      expect(
        () => cleanAiJson('{"questions":[{"question":"x"}'),
        throwsA(isA<TestFormatException>()),
      );
    });

    test('rejects text without an object', () {
      expect(
        () => cleanAiJson('Sorry, I could not answer that.'),
        throwsA(isA<TestFormatException>()),
      );
    });
  });

  group('normalizeMcqQuestion', () {
    test('converts A-D keys and a letter answer to numeric keys', () {
      final q = normalizeMcqQuestion({
        'question': 'Capital of Bangladesh?',
        'options': {
          'A': 'Dhaka',
          'B': 'Chattogram',
          'C': 'Khulna',
          'D': 'Rajshahi',
        },
        'correct_answer': 'A',
      });

      expect(q['options'], {
        '1': 'Dhaka',
        '2': 'Chattogram',
        '3': 'Khulna',
        '4': 'Rajshahi',
      });
      expect(q['correct_answer'], '1');
    });

    test('maps Bengali option letters to numeric keys', () {
      final q = normalizeMcqQuestion({
        'question': 'বাংলাদেশের রাজধানী কোনটি?',
        'options': {
          'ক': 'ঢাকা',
          'খ': 'চট্টগ্রাম',
          'গ': 'খুলনা',
          'ঘ': 'রাজশাহী',
        },
        'correct_answer': 'গ',
      });

      expect(q['options'], {
        '1': 'ঢাকা',
        '2': 'চট্টগ্রাম',
        '3': 'খুলনা',
        '4': 'রাজশাহী',
      });
      expect(q['correct_answer'], '3');
    });

    test('accepts a list of options', () {
      final q = normalizeMcqQuestion({
        'question': '2 + 2?',
        'options': ['3', '4', '5', '6'],
        'correct_answer': 'B',
      });

      expect(q['options'], {
        '1': '3',
        '2': '4',
        '3': '5',
        '4': '6',
      });
      expect(q['correct_answer'], '2');
    });

    test('accepts the correct answer stored as option text', () {
      final q = normalizeMcqQuestion({
        'question': '2 + 2?',
        'options': {'1': '3', '2': '4', '3': '5', '4': '6'},
        'correct_answer': '5',
      });

      expect(q['correct_answer'], '3');
    });

    test('leaves numeric keys untouched', () {
      final q = normalizeMcqQuestion({
        'question': '2 + 2?',
        'options': {'1': '3', '2': '4', '3': '5', '4': '6'},
        'correct_answer': '2',
      });

      expect(q['options'], {'1': '3', '2': '4', '3': '5', '4': '6'});
      expect(q['correct_answer'], '2');
    });
  });

  group('TestType', () {
    test('accepts both share labels and saved-test labels', () {
      expect(TestType.tryFromLabel('MCQ'), TestType.mcq);
      expect(TestType.tryFromLabel('MCQ Test'), TestType.mcq);
      expect(TestType.tryFromLabel('Short Question'), TestType.short);
      expect(TestType.tryFromLabel('Creative Question'), TestType.creative);
      expect(TestType.tryFromLabel('Unknown'), isNull);
    });
  });

  group('parseTest', () {
    test('parses a valid MCQ test and normalizes its options', () {
      const raw = '''
{
  "topic": "Algebra",
  "questions": [
    {
      "question": "Solve x + 2 = 4.",
      "options": {"A": "1", "B": "2", "C": "3", "D": "4"},
      "correct_answer": "B"
    }
  ]
}''';

      final test = parseTest(raw, TestType.mcq);

      expect(test.topic, 'Algebra');
      expect(test.questions, hasLength(1));
      expect(test.questions.first['options'], {
        '1': '1',
        '2': '2',
        '3': '3',
        '4': '4',
      });
      expect(test.questions.first['correct_answer'], '2');
    });

    test('rejects an MCQ without options', () {
      const raw = '''
{"topic":"Algebra","questions":[{"question":"Solve x + 2 = 4.","correct_answer":"1"}]}''';

      expect(
        () => parseTest(raw, TestType.mcq),
        throwsA(isA<TestFormatException>()),
      );
    });

    test('rejects an MCQ whose correct answer matches no option', () {
      const raw = '''
{"topic":"Algebra","questions":[{"question":"Solve x + 2 = 4.","options":{"1":"1","2":"2","3":"3","4":"4"},"correct_answer":"9"}]}''';

      expect(
        () => parseTest(raw, TestType.mcq),
        throwsA(isA<TestFormatException>()),
      );
    });

    test('parses short questions', () {
      const raw = '''
{"topic":"Bangladesh","questions":[{"question":"What is the capital?","answer":"Dhaka"}]}''';

      final test = parseTest(raw, TestType.short);

      expect(test.topic, 'Bangladesh');
      expect(test.questions.first['answer'], 'Dhaka');
    });

    test('rejects a short question with an empty answer', () {
      const raw = '''
{"topic":"Bangladesh","questions":[{"question":"What is the capital?","answer":""}]}''';

      expect(
        () => parseTest(raw, TestType.short),
        throwsA(isA<TestFormatException>()),
      );
    });

    test('parses creative questions', () {
      const raw = '''
{
  "topic": "Photosynthesis",
  "questions": [
    {
      "question_number": 1,
      "stem": "A plant is kept in sunlight.",
      "sub_questions": [
        {"label": "ক", "text": "What is photosynthesis?", "marks": 1},
        {"label": "খ", "text": "Why is sunlight needed?", "marks": 2}
      ]
    }
  ]
}''';

      final test = parseTest(raw, TestType.creative);

      expect(test.topic, 'Photosynthesis');
      expect(test.questions.first['sub_questions'], hasLength(2));
    });

    test('rejects a creative question with no sub-questions', () {
      const raw = '''
{"topic":"Photosynthesis","questions":[{"question_number":1,"stem":"A plant is kept in sunlight.","sub_questions":[]}]}''';

      expect(
        () => parseTest(raw, TestType.creative),
        throwsA(isA<TestFormatException>()),
      );
    });

    test('uses a fallback topic when the AI omits it', () {
      const raw = '''
{"questions":[{"question":"2 + 2?","answer":"4"}]}''';

      final test = parseTest(raw, TestType.short);
      expect(test.topic, 'Generated Test');
    });
  });

  group('formatShortQuestions', () {
    test('uses the Bengali answer label', () {
      final text = formatShortQuestions(
        [
          {'question': 'রাজধানীর নাম কী?', 'answer': 'ঢাকা'},
        ],
        'বাংলা',
      );

      expect(text, contains('1. রাজধানীর নাম কী?'));
      expect(text, contains('উত্তর: ঢাকা'));
    });

    test('uses the English answer label', () {
      final text = formatShortQuestions(
        [
          {'question': 'What is the capital?', 'answer': 'Dhaka'},
        ],
        'English',
      );

      expect(text, contains('Answer: Dhaka'));
      expect(text, isNot(contains('null')));
    });

    test('collapses newlines so the runner keeps one question per block', () {
      final text = formatShortQuestions(
        [
          {'question': 'Line one\nline two', 'answer': 'First\nSecond'},
        ],
        'English',
      );

      expect(text, contains('1. Line one line two'));
      expect(text, contains('Answer: First Second'));
    });
  });

  group('buildTestInstruction', () {
    test('MCQ prompt uses numeric option keys', () {
      final prompt = buildTestInstruction(
        type: TestType.mcq,
        language: 'English',
        count: 5,
      );

      expect(prompt, contains('exactly 5 questions'));
      expect(prompt, contains('"1": "Option 1"'));
      expect(prompt, contains('"correct_answer": "1"'));
      expect(prompt, contains('Return ONLY one valid JSON object'));
    });

    test('creative prompt follows the selected language labels', () {
      final bangla = buildTestInstruction(
        type: TestType.creative,
        language: 'বাংলা',
        count: 1,
      );
      final english = buildTestInstruction(
        type: TestType.creative,
        language: 'English',
        count: 1,
      );

      expect(bangla, contains('"label": "ক"'));
      expect(english, contains('"label": "a"'));
    });
  });

  group('sampleTestJson', () {
    for (final type in TestType.values) {
      for (final language in ['বাংলা', 'English']) {
        test('${type.label} sample parses in $language', () {
          final raw = sampleTestJson(type, language);
          final test = parseTest(raw, type);

          expect(test.questions, isNotEmpty);
          expect(test.topic, isNotEmpty);
        });
      }
    }
  });

  group('TestShareService', () {
    test('returns a numeric test id as a string', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'success': true, 'testId': 123456}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = TestShareService(client: client);

      final code = await service.publish(
        url: 'https://example.test/exec',
        testType: 'MCQ',
        language: 'বাংলা',
        duration: 10,
        jsonData: '{"questions":[]}',
      );

      expect(code, '123456');
      service.dispose();
    });

    test('accepts string success values', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'success': 'true', 'testId': 'ABC123'}),
          200,
        );
      });
      final service = TestShareService(client: client);

      final code = await service.publish(
        url: 'https://example.test/exec',
        testType: 'MCQ',
        language: 'English',
        duration: 10,
        jsonData: '{}',
      );

      expect(code, 'ABC123');
      service.dispose();
    });

    test('throws when the server omits the share code', () async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode({'success': true}), 200);
      });
      final service = TestShareService(client: client);

      expect(
        () => service.publish(
          url: 'https://example.test/exec',
          testType: 'MCQ',
          language: 'English',
          duration: 10,
          jsonData: '{}',
        ),
        throwsA(isA<TestShareException>()),
      );
      service.dispose();
    });

    test('throws a friendly error on a server error status', () async {
      final client = MockClient((request) async {
        return http.Response('server exploded', 500);
      });
      final service = TestShareService(client: client);

      expect(
        () => service.publish(
          url: 'https://example.test/exec',
          testType: 'MCQ',
          language: 'English',
          duration: 10,
          jsonData: '{}',
        ),
        throwsA(isA<TestShareException>()),
      );
      service.dispose();
    });

    test('decodes UTF-8 error messages from the server', () async {
      final client = MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'success': false,
              'error': 'কোডটি পাওয়া যায়নি',
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final service = TestShareService(client: client);

      await expectLater(
        service.publish(
          url: 'https://example.test/exec',
          testType: 'MCQ',
          language: 'বাংলা',
          duration: 10,
          jsonData: '{}',
        ),
        throwsA(
          isA<TestShareException>().having(
            (error) => error.message,
            'message',
            contains('কোডটি'),
          ),
        ),
      );
      service.dispose();
    });

    test('sends the configured content type', () async {
      String? sentContentType;
      final client = MockClient((request) async {
        for (final entry in request.headers.entries) {
          if (entry.key.toLowerCase() == 'content-type') {
            sentContentType = entry.value;
          }
        }
        return http.Response(
          jsonEncode({'success': true, 'testId': 'X'}),
          200,
        );
      });
      final service = TestShareService(
        client: client,
        contentType: 'text/plain;charset=utf-8',
      );

      await service.publish(
        url: 'https://example.test/exec',
        testType: 'MCQ',
        language: 'English',
        duration: 10,
        jsonData: '{}',
      );

      expect(sentContentType, 'text/plain;charset=utf-8');
      service.dispose();
    });
  });
}

import 'dart:convert';

import 'test_json.dart';

/// A small, valid example for the selected test type and language.
///
/// This lets a user try the full flow without an AI response and shows the
/// exact JSON shape the parser accepts.
String sampleTestJson(TestType type, String language) {
  final isBangla = language == 'বাংলা';

  final Map<String, dynamic> data;
  switch (type) {
    case TestType.mcq:
      data = isBangla
          ? {
              'topic': 'সাধারণ গণিত',
              'questions': [
                {
                  'question': '২ + ২ = কত?',
                  'options': {
                    '1': '৩',
                    '2': '৪',
                    '3': '৫',
                    '4': '৬',
                  },
                  'correct_answer': '2',
                },
                {
                  'question': 'বাংলাদেশের রাজধানীর নাম কী?',
                  'options': {
                    '1': 'ঢাকা',
                    '2': 'চট্টগ্রাম',
                    '3': 'খুলনা',
                    '4': 'রাজশাহী',
                  },
                  'correct_answer': '1',
                },
              ],
            }
          : {
              'topic': 'General Knowledge',
              'questions': [
                {
                  'question': 'What is 2 + 2?',
                  'options': {
                    '1': '3',
                    '2': '4',
                    '3': '5',
                    '4': '6',
                  },
                  'correct_answer': '2',
                },
                {
                  'question': 'What is the capital of Bangladesh?',
                  'options': {
                    '1': 'Dhaka',
                    '2': 'Chattogram',
                    '3': 'Khulna',
                    '4': 'Rajshahi',
                  },
                  'correct_answer': '1',
                },
              ],
            };
      break;

    case TestType.short:
      data = isBangla
          ? {
              'topic': 'বাংলাদেশ',
              'questions': [
                {
                  'question': 'বাংলাদেশের রাজধানীর নাম কী?',
                  'answer': 'ঢাকা',
                },
                {
                  'question': 'বাংলাদেশের জাতীয় ফুল কী?',
                  'answer': 'শাপলা',
                },
              ],
            }
          : {
              'topic': 'General Knowledge',
              'questions': [
                {
                  'question': 'What is the capital of Bangladesh?',
                  'answer': 'Dhaka',
                },
                {
                  'question': 'What is the national flower of Bangladesh?',
                  'answer': 'Water lily',
                },
              ],
            };
      break;

    case TestType.creative:
      data = isBangla
          ? {
              'topic': 'উদ্ভিদের খাদ্য তৈরি',
              'questions': [
                {
                  'question_number': 1,
                  'stem': 'সালোকসংশ্লেষণ প্রক্রিয়ায় সবুজ উদ্ভিদ সূর্যের আলোর '
                      'উপস্থিতিতে কার্বন ডাই-অক্সাইড ও পানি থেকে খাদ্য তৈরি করে।',
                  'sub_questions': [
                    {
                      'label': 'ক',
                      'text': 'সালোকসংশ্লেষণ কী?',
                      'marks': 1,
                    },
                    {
                      'label': 'খ',
                      'text': 'সালোকসংশ্লেষণের জন্য সূর্যের আলো কেন প্রয়োজন?',
                      'marks': 2,
                    },
                    {
                      'label': 'গ',
                      'text':
                          'সালোকসংশ্লেষণের সময় উদ্ভিদ কোন গ্যাস গ্রহণ করে?',
                      'marks': 3,
                    },
                    {
                      'label': 'ঘ',
                      'text': 'সালোকসংশ্লেষণ প্রক্রিয়ার গুরুত্ব ব্যাখ্যা করো।',
                      'marks': 4,
                    },
                  ],
                },
              ],
            }
          : {
              'topic': 'Photosynthesis',
              'questions': [
                {
                  'question_number': 1,
                  'stem': 'Green plants use sunlight to make food from carbon '
                      'dioxide and water during photosynthesis.',
                  'sub_questions': [
                    {
                      'label': 'a',
                      'text': 'What is photosynthesis?',
                      'marks': 1,
                    },
                    {
                      'label': 'b',
                      'text': 'Why is sunlight needed for photosynthesis?',
                      'marks': 2,
                    },
                    {
                      'label': 'c',
                      'text':
                          'Which gas do plants take in during photosynthesis?',
                      'marks': 3,
                    },
                    {
                      'label': 'd',
                      'text': 'Explain the importance of photosynthesis.',
                      'marks': 4,
                    },
                  ],
                },
              ],
            };
      break;
  }

  return const JsonEncoder.withIndent('  ').convert(data);
}

import 'test_json.dart';

/// Build the instruction copied to an external AI app.
///
/// The prompt is deliberately strict about the JSON contract because the app
/// validates it and the MCQ runner expects numeric option keys.
String buildTestInstruction({
  required TestType type,
  required String language,
  required int count,
}) {
  final safeCount = count.clamp(1, 100);
  final isBangla = language == 'বাংলা';
  final creativeLabels = isBangla ? 'ক, খ, গ, ঘ' : 'a, b, c, d';
  final marksLabel = isBangla ? 'নম্বর' : 'marks';

  final base =
      '''You are an exam question writer. Analyze the core educational content in the provided image or text and generate exactly $safeCount questions.

CRITICAL RULES:
1. NEVER mention the image, file name, screenshot, or use phrases like "In the image", "According to the picture", etc.
2. IGNORE all device UI elements, battery percentages, app interfaces, timestamps, and irrelevant background details.
3. Focus PURELY on the academic subject matter, text, or main concept.
4. Make every question standalone and understandable to a student who has never seen the original image.
5. Return ONLY one valid JSON object. No markdown fences, no commentary, no trailing commas, and no text before or after the JSON.
6. Do not repeat or paraphrase the same question.
7. Write all content in $language using standard Unicode characters. For math, use plain text or LaTeX delimited with \$...\$; do not use unsupported symbols.
8. Generate a short 1-3 word topic name that describes the subject matter.
9. Before returning, self-check that every required field is present and that every answer is consistent with the options.''';

  if (type == TestType.mcq) {
    return '''$base

Language: $language
Format:
{
  "topic": "Short Topic Name",
  "questions": [
    {
      "question": "Question text?",
      "options": {
        "1": "Option 1",
        "2": "Option 2",
        "3": "Option 3",
        "4": "Option 4"
      },
      "correct_answer": "1"
    }
  ]
}

MCQ RULES:
- Each question MUST have exactly four options keyed "1", "2", "3", "4".
- "correct_answer" MUST be one of "1", "2", "3", "4".
- Exactly one option is correct; the other three must be plausible distractors.
- Distribute correct answers across all four positions; do not make every answer "1".
- Do NOT use "All of the above" or "None of the above".
- Self-check that every correct_answer matches an option key.''';
  }

  if (type == TestType.short) {
    return '''$base

Language: $language
Format:
{
  "topic": "Short Topic Name",
  "questions": [
    {
      "question": "Question text?",
      "answer": "Concise correct answer"
    }
  ]
}

SHORT QUESTION RULES:
- Each answer must be a complete, concise answer, usually 1-5 words.
- Never leave an answer empty.
- Do not include multiple alternative answers separated by slashes unless they are genuinely equivalent.''';
  }

  return '''$base

Language: $language
Format:
{
  "topic": "Short Topic Name",
  "questions": [
    {
      "question_number": 1,
      "stem": "Stem text or passage...",
      "sub_questions": [
        {"label": "${isBangla ? 'ক' : 'a'}", "text": "Knowledge based question", "marks": 1},
        {"label": "${isBangla ? 'খ' : 'b'}", "text": "Comprehension based question", "marks": 2},
        {"label": "${isBangla ? 'গ' : 'c'}", "text": "Application based question", "marks": 3},
        {"label": "${isBangla ? 'ঘ' : 'd'}", "text": "Higher order thinking question", "marks": 4}
      ]
    }
  ]
}

CREATIVE QUESTION RULES:
- Use the labels $creativeLabels in this order.
- Marks must be 1, 2, 3, 4 and the sub-questions must progress from knowledge to higher-order thinking.
- Each stem must be a self-contained passage, scenario, or stimulus.
- Every sub-question must be answerable from its stem.
- Include the marks field as a number, not a string, and label it as $marksLabel in the content.''';
}

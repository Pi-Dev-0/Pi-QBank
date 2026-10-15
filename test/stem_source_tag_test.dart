import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/models/highschool_question.dart';

/// The sheet stores a question's source twice: in `board_year_tag`, and again
/// pasted onto the end of `stem_text` in brackets.
///
/// The paper prints neither, and it was the second copy that left
/// "মাদ্রাসা বোর্ড ২০১৮" sitting at the end of a printed CQ stem.
/// [HighSchoolQuestion.paperStemText] trims that copy off; [stemText] keeps it,
/// because it is what the row actually says and what an upload sends back.
HighSchoolQuestion cq(String stem, String tag) => HighSchoolQuestion.fromJson({
      'id': 'cq',
      'class': 'Class (11-12) HSC',
      'subject': 'তথ্য ও যোগাযোগ প্রযুক্তি',
      'chapter_number': '1',
      'chapter_name': 'অনুশীলনী',
      'question_type': 'CQ',
      'stem_text': stem,
      'stem_image_url': '',
      'sub_questions_json': [
        {'label': 'ক', 'mark': 1, 'text': 'প্রশ্ন?'},
      ],
      'board_year_tag': tag,
    });

HighSchoolQuestion mcq(String question, String stem, String tag) =>
    HighSchoolQuestion.fromJson({
      'id': 'mcq',
      'class': 'Class (11-12) HSC',
      'subject': 'তথ্য ও যোগাযোগ প্রযুক্তি',
      'chapter_number': '1',
      'chapter_name': 'অনুশীলনী',
      'question_type': 'MCQ',
      'stem_text': stem,
      'stem_image_url': '',
      'sub_questions_json': {
        'text': question,
        'options': ['এক', 'দুই', 'তিন', 'চার'],
        'correct_ans': 'এক',
      },
      'board_year_tag': tag,
    });

void main() {
  group('paperStemText', () {
    test('drops a spelled-out source that the row also stores on its own', () {
      final q = cq(
        'উদ্দীপক পড়ে উত্তর দাও। [মাদ্রাসা বোর্ড ২০১৮]',
        'মাদ্রাসা বোর্ড ২০১৮',
      );

      expect(q.paperStemText, 'উদ্দীপক পড়ে উত্তর দাও।');
    });

    test('drops an abbreviated source that never equals the tag column', () {
      // Real shape: the tag column spells the board out in full, the stem
      // abbreviates it, so an equality test on its own misses this one.
      final q = cq("প্রশ্ন? [দি.বো.'১৭]", 'দিনাজপুর বোর্ড ২০১৭');

      expect(q.paperStemText, 'প্রশ্ন?');
    });

    test('drops several abbreviations in one marker', () {
      final q = cq(
        "প্রশ্ন? [ঢা.বো.'২৩; সি.বো.'২৩; ম.বো.'২৩]",
        'ঢাকা বোর্ড ২০২৩; সিলেট বোর্ড ২০২৩; ময়মনসিংহ বোর্ড ২০২৩',
      );

      expect(q.paperStemText, 'প্রশ্ন?');
    });

    test('drops a college source', () {
      final q = cq('প্রশ্ন? [ঢাকা সিটি কলেজ, ঢাকা]', 'ঢাকা সিটি কলেজ, ঢাকা');

      expect(q.paperStemText, 'প্রশ্ন?');
    });

    test('a stem that is only a marker comes back empty, not as brackets', () {
      final q = mcq('কোনটি ভার্চুয়াল রিয়েলিটিতে ব্যবহৃত হয়?', "[দি.বো.'১৭]",
          'দিনাজপুর বোর্ড ২০১৭');

      expect(q.paperStemText, '');
    });

    test('has no trailing space left behind', () {
      final q = cq('উদ্দীপক।   [ঢাকা বোর্ড ২০১৭]', 'ঢাকা বোর্ড ২০১৭');

      expect(q.paperStemText, 'উদ্দীপক।');
    });

    test('leaves the raw stem alone so uploads round-trip', () {
      final q = cq('উদ্দীপক। [ঢাকা বোর্ড ২০১৭]', 'ঢাকা বোর্ড ২০১৭');

      expect(q.stemText, 'উদ্দীপক। [ঢাকা বোর্ড ২০১৭]');
      expect(q.toJson()['stem_text'], 'উদ্দীপক। [ঢাকা বোর্ড ২০১৭]');
    });

    test('keeps a bracket that belongs to the question', () {
      // Real shape from Class 8: the bracket is the figure caption.
      const stem =
          'দৃশ্যকল্প: [ভেন চিত্রে সার্বিক সেট U এবং তিনটি উপসেট চিত্রিত আছে]';
      final q = cq(stem, '');

      expect(q.paperStemText, stem);
    });

    test('keeps the bracket when no tag column is set', () {
      // No source on the row, so there is nothing to trim.
      final q = cq('উদ্দীপক। [ঢাকা বোর্ড ২০১৭]', '');

      expect(q.paperStemText, 'উদ্দীপক। [ঢাকা বোর্ড ২০১৭]');
    });

    test('keeps a source-looking bracket that is really a sentence', () {
      final q = cq('উদ্দীপক। [কলেজে ছাত্র সংখ্যা কত?]', 'ঢাকা বোর্ড ২০১৭');

      expect(q.paperStemText, 'উদ্দীপক। [কলেজে ছাত্র সংখ্যা কত?]');
    });

    test('keeps a bracket that merely ends the text', () {
      final q = cq('উদ্দীপক [অন্য সূত্র]', 'ঢাকা বোর্ড ২০১৭');

      expect(q.paperStemText, 'উদ্দীপক [অন্য সূত্র]');
    });

    test('keeps a long bracketed aside even if it names a school', () {
      final q = cq(
        'উদ্দীপক। [উক্ত কলেজের ছাত্রছাত্রীদের মধ্যে যারা নিয়মিত '
            'ক্লাসে অংশগ্রহণ করে তাদের ফলাফল তুলনামূলকভাবে ভালো হয়]',
        'ঢাকা বোর্ড ২০১৭',
      );

      expect(
          q.paperStemText,
          'উদ্দীপক। [উক্ত কলেজের ছাত্রছাত্রীদের মধ্যে যারা নিয়মিত '
          'ক্লাসে অংশগ্রহণ করে তাদের ফলাফল তুলনামূলকভাবে ভালো হয়]');
    });
  });

  group('paperQuestionText', () {
    test('drops a source marker riding on the MCQ question line', () {
      final q =
          mcq("প্রশ্ন? [দি.বো.'১৭]", "[দি.বো.'১৭]", 'দিনাজপুর বোর্ড ২০১৭');

      expect(q.paperQuestionText, 'প্রশ্ন?');
    });

    test('leaves an ordinary MCQ question untouched', () {
      final q = mcq('কোনটি ভার্চুয়াল রিয়েলিটিতে ব্যবহৃত হয়?', '',
          'দিনাজপুর বোর্ড ২০১৭');

      expect(q.paperQuestionText, 'কোনটি ভার্চুয়াল রিয়েলিটিতে ব্যবহৃত হয়?');
    });

    test('is empty for a row with no MCQ payload', () {
      final q = cq('উদ্দীপক।', 'ঢাকা বোর্ড ২০১৭');

      expect(q.paperQuestionText, '');
    });
  });
}

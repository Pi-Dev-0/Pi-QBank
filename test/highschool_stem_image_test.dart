import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pi_qbank/models/highschool_question.dart';
import 'package:pi_qbank/services/highschool_export_service.dart' as ex;

HighSchoolQuestion cq({
  String stemImageUrl = '',
  String id = 'q1',
}) {
  return HighSchoolQuestion.fromJson({
    'id': id,
    'class': 'Class (9-10) SSC',
    'subject': 'উচ্চতর গণিত',
    'chapter_number': '1',
    'chapter_name': 'সেট',
    'question_type': 'CQ',
    'stem_text': 'A = {1, 2, 3}',
    'stem_image_url': stemImageUrl,
    'sub_questions_json': [
      {'label': 'ক', 'mark': 1, 'text': 'লেখো'}
    ],
    'board_year_tag': '2023',
  });
}

/// Smallest possible valid PNG (8x8 solid red), inlined so the test needs no
/// fixture files on disk.
final Uint8List _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEklEQVR4nGP4z8CAFWEXHbQSACj/'
  'P8Fu7N9hAAAAAElFTkSuQmCC',
);

void main() {
  group('resolveImageUrl', () {
    test('converts Drive share links to direct download', () {
      expect(
        ex.HighSchoolExportService.resolveImageUrl(
            'https://drive.google.com/file/d/1AbC_dEf-123/view?usp=sharing'),
        'https://drive.google.com/uc?export=download&id=1AbC_dEf-123',
      );
      expect(
        ex.HighSchoolExportService.resolveImageUrl(
            'https://drive.google.com/open?id=1AbC_dEf-123'),
        'https://drive.google.com/uc?export=download&id=1AbC_dEf-123',
      );
    });

    test('leaves normal image URLs untouched', () {
      const url = 'https://example.com/stem/fig1.png';
      expect(ex.HighSchoolExportService.resolveImageUrl(url), url);
    });

    test('handles empty input', () {
      expect(ex.HighSchoolExportService.resolveImageUrl('   '), '');
    });
  });

  group('exports include the stem image', () {
    final url = 'https://drive.google.com/file/d/FILEID123/view';
    final qs = [cq(stemImageUrl: url)];

    test('html has an <img> pointing at the resolved URL', () {
      final html = ex.HighSchoolExportService.generateHtml(
        schoolName: 'S', examName: 'E', subject: 'M',
        className: 'C', time: 'T', totalMarks: '10',
        questions: qs,
      );
      expect(html, contains('<img'));
      expect(html, contains('uc?export=download&amp;id=FILEID123'));
    });

    test('markdown has an image link', () {
      final md = ex.HighSchoolExportService.generateMarkdown(
        schoolName: 'S', examName: 'E', subject: 'M',
        className: 'C', time: 'T', totalMarks: '10',
        questions: qs,
      );
      expect(md, contains('![উদ্দীপক চিত্র](https://drive.google.com/uc?export=download&id=FILEID123)'));
    });

    test('plain text surfaces the URL', () {
      final txt = ex.HighSchoolExportService.generatePlainText(
        schoolName: 'S', examName: 'E', subject: 'M',
        className: 'C', time: 'T', totalMarks: '10',
        questions: qs,
      );
      expect(txt, contains('uc?export=download&id=FILEID123'));
    });

    test('sniffs the real image format instead of assuming png', () {
      expect(ex.HighSchoolExportService.sniffImageMime(_tinyPng), 'image/png');
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0]);
      expect(ex.HighSchoolExportService.sniffImageMime(jpeg), 'image/jpeg');
      final webp = Uint8List.fromList([
        0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0,
        0x57, 0x45, 0x42, 0x50, 0, 0, 0, 0,
      ]);
      expect(ex.HighSchoolExportService.sniffImageMime(webp), 'image/webp');
    });

    test('word embeds bytes as a data URI when available', () {
      final bytes = _tinyPng;
      final doc = ex.HighSchoolExportService.generateWordDoc(
        schoolName: 'S', examName: 'E', subject: 'M',
        className: 'C', time: 'T', totalMarks: '10',
        questions: qs,
        imageBytes: {
          'https://drive.google.com/uc?export=download&id=FILEID123': bytes,
        },
      );
      expect(doc, contains('data:image/png;base64,'));
      expect(doc, isNot(contains('src="https://drive.google.com/uc')));
    });

    test('word falls back to a URL when bytes are unavailable', () {
      final doc = ex.HighSchoolExportService.generateWordDoc(
        schoolName: 'S', examName: 'E', subject: 'M',
        className: 'C', time: 'T', totalMarks: '10',
        questions: qs,
      );
      expect(doc, contains('<img'));
      expect(doc, contains('uc?export=download&amp;id=FILEID123'));
    });

    test('questions without an image are unaffected', () {
      final html = ex.HighSchoolExportService.generateHtml(
        schoolName: 'S', examName: 'E', subject: 'M',
        className: 'C', time: 'T', totalMarks: '10',
        questions: [cq()],
      );
      expect(html, isNot(contains('<img')));
    });

    test('json keeps the raw url for round-tripping', () {
      final json = ex.HighSchoolExportService.generateJson(
        schoolName: 'S', examName: 'E', subject: 'M',
        className: 'C', time: 'T', totalMarks: '10',
        questions: qs,
      );
      expect(json, contains('FILEID123'));
    });
  });

  test('pw.MemoryImage accepts fetched png bytes', () async {
    final bytes = _tinyPng;
    final doc = pw.Document();
    doc.addPage(pw.Page(build: (_) => pw.Image(pw.MemoryImage(bytes), height: 150)));
    final out = await doc.save();
    expect(out.length, greaterThan(500));
  });
}
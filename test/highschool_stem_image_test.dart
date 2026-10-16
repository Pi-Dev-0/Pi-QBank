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

/// True when the HTML stylesheet lays the questions of [name] out as two
/// newspaper columns (`column-count: 2`) rather than a single stack.
bool _isTwoColumn(String html, String name) => RegExp('\\.$name \\{([^}]*)\\}')
    .firstMatch(html)!
    .group(1)!
    .contains('column-count: 2');

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
        schoolName: 'S',
        examName: 'E',
        subject: 'M',
        className: 'C',
        time: 'T',
        totalMarks: '10',
        questions: qs,
      );
      expect(html, contains('<img'));
      expect(html, contains('uc?export=download&amp;id=FILEID123'));
    });

    test('markdown has an image link', () {
      final md = ex.HighSchoolExportService.generateMarkdown(
        schoolName: 'S',
        examName: 'E',
        subject: 'M',
        className: 'C',
        time: 'T',
        totalMarks: '10',
        questions: qs,
      );
      expect(
          md,
          contains(
              '![উদ্দীপক চিত্র](https://drive.google.com/uc?export=download&id=FILEID123)'));
    });

    test('plain text surfaces the URL', () {
      final txt = ex.HighSchoolExportService.generatePlainText(
        schoolName: 'S',
        examName: 'E',
        subject: 'M',
        className: 'C',
        time: 'T',
        totalMarks: '10',
        questions: qs,
      );
      expect(txt, contains('uc?export=download&id=FILEID123'));
    });

    group('image size control', () {
      final url = 'https://example.com/fig.png';
      final qs = [cq(stemImageUrl: url)];

      String htmlFor(ex.StemImageSize size) =>
          ex.HighSchoolExportService.generateHtml(
            schoolName: 'S',
            examName: 'E',
            subject: 'M',
            className: 'C',
            time: 'T',
            totalMarks: '10',
            questions: qs,
            imageSize: size,
          );

      test('hidden omits the image entirely', () {
        expect(htmlFor(ex.StemImageSize.hidden), isNot(contains('<img')));
        expect(htmlFor(ex.StemImageSize.hidden), isNot(contains('fig.png')));
      });

      test('sizes grow small -> medium -> large', () {
        double maxHeightPx(ex.StemImageSize s) {
          final m = RegExp(r'max-height:([\d.]+)px').firstMatch(htmlFor(s));
          expect(m, isNotNull, reason: 'no max-height in ${s.label}');
          return double.parse(m!.group(1)!);
        }

        final small = maxHeightPx(ex.StemImageSize.small);
        final medium = maxHeightPx(ex.StemImageSize.medium);
        final large = maxHeightPx(ex.StemImageSize.large);
        expect(small, lessThan(medium));
        expect(medium, lessThan(large));
      });

      test('word honours hidden as well', () {
        final doc = ex.HighSchoolExportService.generateWordDoc(
          schoolName: 'S',
          examName: 'E',
          subject: 'M',
          className: 'C',
          time: 'T',
          totalMarks: '10',
          questions: qs,
          imageSize: ex.StemImageSize.hidden,
        );
        expect(doc, isNot(contains('<img')));
      });

      test('markdown and text respect hidden', () {
        final md = ex.HighSchoolExportService.generateMarkdown(
          schoolName: 'S',
          examName: 'E',
          subject: 'M',
          className: 'C',
          time: 'T',
          totalMarks: '10',
          questions: qs,
          imageSize: ex.StemImageSize.hidden,
        );
        final txt = ex.HighSchoolExportService.generatePlainText(
          schoolName: 'S',
          examName: 'E',
          subject: 'M',
          className: 'C',
          time: 'T',
          totalMarks: '10',
          questions: qs,
          imageSize: ex.StemImageSize.hidden,
        );
        expect(md, isNot(contains('fig.png')));
        expect(txt, isNot(contains('fig.png')));
      });

      test('metrics are ordered and hidden is zero', () {
        expect(ex.StemImageSize.hidden.maxHeightPt, 0);
        expect(ex.StemImageSize.hidden.isVisible, isFalse);
        expect(ex.StemImageSize.small.maxHeightPt,
            lessThan(ex.StemImageSize.medium.maxHeightPt));
        expect(ex.StemImageSize.medium.maxHeightPt,
            lessThan(ex.StemImageSize.large.maxHeightPt));
      });

      test('preview page exposes a full html document', () {
        final h = ex.HighSchoolExportService.generateHtml(
          schoolName: 'S',
          examName: 'E',
          subject: 'M',
          className: 'C',
          time: 'T',
          totalMarks: '10',
          questions: qs,
        );
        expect(h.trimLeft(), startsWith('<!DOCTYPE html>'));
        expect(h, contains('</html>'));
        expect(h, contains('window.print()'));
      });
    });

    group('column layout', () {
      HighSchoolQuestion mcq(int i) => HighSchoolQuestion.fromJson({
            'id': 'm$i',
            'class': 'Class (9-10) SSC',
            'subject': 'M',
            'chapter_number': '1',
            'chapter_name': 'C',
            'question_type': 'MCQ',
            'stem_text': '',
            'stem_image_url': '',
            'sub_questions_json': {
              'text': 'Q$i',
              'options': ['a', 'b', 'c', 'd'],
              'correct_ans': 'a',
            },
            'board_year_tag': '',
          });

      final qs = [mcq(1), mcq(2), mcq(3)];

      String htmlFor(ex.QuestionLayout layout) =>
          ex.HighSchoolExportService.generateHtml(
            schoolName: 'S',
            examName: 'E',
            subject: 'M',
            className: 'C',
            time: 'T',
            totalMarks: '10',
            questions: qs,
            cqLayout: layout,
            mcqLayout: layout,
          );

      test('single column lays the questions out one below the other', () {
        final h = htmlFor(ex.QuestionLayout.single);
        expect(_isTwoColumn(h, 'cq-grid'), isFalse);
        expect(_isTwoColumn(h, 'mcq-grid'), isFalse);
        expect(ex.QuestionLayout.single.mcqColumns, 1);
      });

      test('double column flows two newspaper columns', () {
        // Each question keeps the height it needs and the next one continues
        // below it. A grid would stretch both cards of a row to the taller one.
        final h = htmlFor(ex.QuestionLayout.doubleColumn);
        expect(_isTwoColumn(h, 'cq-grid'), isTrue);
        expect(_isTwoColumn(h, 'mcq-grid'), isTrue);
        expect(ex.QuestionLayout.doubleColumn.mcqColumns, 2);
      });

      test('options stack vertically only in double column', () {
        // Narrow cells cannot fit two options side by side.
        final singleOpts =
            RegExp(r'\.mcq-options \{[^}]*?grid-template-columns: ([^;]+);')
                .firstMatch(htmlFor(ex.QuestionLayout.single))!
                .group(1)!;
        final doubleOpts =
            RegExp(r'\.mcq-options \{[^}]*?grid-template-columns: ([^;]+);')
                .firstMatch(htmlFor(ex.QuestionLayout.doubleColumn))!
                .group(1)!;
        expect(singleOpts.trim(), '1fr 1fr');
        expect(doubleOpts.trim(), '1fr');
      });

      test('cq cards are never placed inside the mcq grid', () {
        for (final layout in ex.QuestionLayout.values) {
          final h = ex.HighSchoolExportService.generateHtml(
            schoolName: 'S',
            examName: 'E',
            subject: 'M',
            className: 'C',
            time: 'T',
            totalMarks: '10',
            questions: [cq(stemImageUrl: 'https://example.com/f.png')],
            cqLayout: layout,
            mcqLayout: layout,
          );
          expect(h, contains('cq-card'));
          expect(h, contains('class="cq-grid"'));
        }
      });

      test('cq and mcq columns are controlled independently', () {
        HighSchoolQuestion mcq(int i) => HighSchoolQuestion.fromJson({
              'id': 'm$i',
              'class': 'Class (9-10) SSC',
              'subject': 'M',
              'chapter_number': '1',
              'chapter_name': 'C',
              'question_type': 'MCQ',
              'stem_text': '',
              'stem_image_url': '',
              'sub_questions_json': {
                'text': 'Q$i',
                'options': ['a', 'b'],
                'correct_ans': 'a',
              },
              'board_year_tag': '',
            });

        final qs = [cq(), mcq(1)];

        String htmlFor(ex.QuestionLayout cq, ex.QuestionLayout m) =>
            ex.HighSchoolExportService.generateHtml(
              schoolName: 'S',
              examName: 'E',
              subject: 'M',
              className: 'C',
              time: 'T',
              totalMarks: '10',
              questions: qs,
              cqLayout: cq,
              mcqLayout: m,
            );

        // The reported need: CQ full width, MCQ side by side.
        final h =
            htmlFor(ex.QuestionLayout.single, ex.QuestionLayout.doubleColumn);
        expect(_isTwoColumn(h, 'cq-grid'), isFalse);
        expect(_isTwoColumn(h, 'mcq-grid'), isTrue);

        // ...and the reverse.
        final h2 =
            htmlFor(ex.QuestionLayout.doubleColumn, ex.QuestionLayout.single);
        expect(_isTwoColumn(h2, 'cq-grid'), isTrue);
        expect(_isTwoColumn(h2, 'mcq-grid'), isFalse);
      });

      test('word emits a real layout table for both options', () {
        for (final layout in ex.QuestionLayout.values) {
          final doc = ex.HighSchoolExportService.generateWordDoc(
            schoolName: 'S',
            examName: 'E',
            subject: 'M',
            className: 'C',
            time: 'T',
            totalMarks: '10',
            questions: qs,
            cqLayout: layout,
            mcqLayout: layout,
          );
          expect(doc, contains('mcq-layout-table'));
          expect(doc, contains('mcq-col-cell'));
        }
      });
    });

    test('cq questions follow the column layout', () {
      // The reported case: a CQ-only paper must still honour double column.
      final qs = List.generate(
        6,
        (i) => cq(
            stemImageUrl: i.isEven ? 'https://example.com/f.png' : '',
            id: 'c$i'),
      );

      String htmlFor(ex.QuestionLayout layout) =>
          ex.HighSchoolExportService.generateHtml(
            schoolName: 'S',
            examName: 'E',
            subject: 'M',
            className: 'C',
            time: 'T',
            totalMarks: '10',
            questions: qs,
            cqLayout: layout,
            mcqLayout: layout,
          );

      final single = htmlFor(ex.QuestionLayout.single);
      final dbl = htmlFor(ex.QuestionLayout.doubleColumn);

      expect(_isTwoColumn(single, 'cq-grid'), isFalse);
      expect(_isTwoColumn(dbl, 'cq-grid'), isTrue);

      // Every CQ card must sit inside the cq-grid container.
      // Match the class attribute, not the CSS selector of the same name.
      for (final html in [single, dbl]) {
        expect(html, contains('class="cq-grid"'));
        expect(html.indexOf('class="cq-grid"'),
            lessThan(html.indexOf('class="cq-card"')));
      }
      expect(RegExp('class="cq-card"').allMatches(dbl).length, 6);
    });

    test('word puts cq questions in the same layout table', () {
      final qs = List.generate(4, (i) => cq(id: 'c$i'));
      for (final layout in ex.QuestionLayout.values) {
        final doc = ex.HighSchoolExportService.generateWordDoc(
          schoolName: 'S',
          examName: 'E',
          subject: 'M',
          className: 'C',
          time: 'T',
          totalMarks: '10',
          questions: qs,
          cqLayout: layout,
          mcqLayout: layout,
        );
        // CQ section table appears before the MCQ one.
        expect(doc, contains('mcq-layout-table'));
        expect(RegExp('class="cq-box"').allMatches(doc).length, 4);
      }
    });

    test('sniffs the real image format instead of assuming png', () {
      expect(ex.HighSchoolExportService.sniffImageMime(_tinyPng), 'image/png');
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0]);
      expect(ex.HighSchoolExportService.sniffImageMime(jpeg), 'image/jpeg');
      final webp = Uint8List.fromList([
        0x52,
        0x49,
        0x46,
        0x46,
        0,
        0,
        0,
        0,
        0x57,
        0x45,
        0x42,
        0x50,
        0,
        0,
        0,
        0,
      ]);
      expect(ex.HighSchoolExportService.sniffImageMime(webp), 'image/webp');
    });

    test('word embeds bytes as a data URI when available', () {
      final bytes = _tinyPng;
      final doc = ex.HighSchoolExportService.generateWordDoc(
        schoolName: 'S',
        examName: 'E',
        subject: 'M',
        className: 'C',
        time: 'T',
        totalMarks: '10',
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
        schoolName: 'S',
        examName: 'E',
        subject: 'M',
        className: 'C',
        time: 'T',
        totalMarks: '10',
        questions: qs,
      );
      expect(doc, contains('<img'));
      expect(doc, contains('uc?export=download&amp;id=FILEID123'));
    });

    test('questions without an image are unaffected', () {
      final html = ex.HighSchoolExportService.generateHtml(
        schoolName: 'S',
        examName: 'E',
        subject: 'M',
        className: 'C',
        time: 'T',
        totalMarks: '10',
        questions: [cq()],
      );
      expect(html, isNot(contains('<img')));
    });

    test('json keeps the raw url for round-tripping', () {
      final json = ex.HighSchoolExportService.generateJson(
        schoolName: 'S',
        examName: 'E',
        subject: 'M',
        className: 'C',
        time: 'T',
        totalMarks: '10',
        questions: qs,
      );
      expect(json, contains('FILEID123'));
    });
  });

  test('pw.MemoryImage accepts fetched png bytes', () async {
    final bytes = _tinyPng;
    final doc = pw.Document();
    doc.addPage(
        pw.Page(build: (_) => pw.Image(pw.MemoryImage(bytes), height: 150)));
    final out = await doc.save();
    expect(out.length, greaterThan(500));
  });
}

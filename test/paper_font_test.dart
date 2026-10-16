// The face a paper is set in. The HTML sheet fetches what it can from Google
// Fonts and falls back to Hind Siliguri, which is always fetched, so a paper
// prints in something readable whatever the reader's machine has installed. The
// Word file names the same face and keeps its own fall-backs. The PDF is not
// part of this: it sets Bangla through the embedded Bijoy face.
import 'package:flutter_test/flutter_test.dart';

import 'package:pi_qbank/models/highschool_question.dart';
import 'package:pi_qbank/services/highschool_export_service.dart';

HighSchoolQuestion rq() => HighSchoolQuestion.fromJson({
      'id': 'q',
      'class': 'Class (9-10) SSC',
      'subject': 'গণিত',
      'chapter_number': '1',
      'chapter_name': 'অনুশীলনী',
      'question_type': 'RQ',
      'stem_text': 'সংক্ষিপ্ত প্রশ্ন',
      'stem_image_url': '',
      'sub_questions_json': <Object>[],
      'board_year_tag': '',
      'short_mark': 1,
    });

String sheetHtml({PaperFont font = PaperFont.hindSiliguri}) =>
    HighSchoolExportService.generateHtml(
      schoolName: 'S',
      examName: 'E',
      subject: 'গণিত',
      className: 'C',
      time: 'T',
      totalMarks: '10',
      font: font,
      questions: [rq()],
    );

String wordDoc({PaperFont font = PaperFont.hindSiliguri}) =>
    HighSchoolExportService.generateWordDoc(
      schoolName: 'S',
      examName: 'E',
      subject: 'গণিত',
      className: 'C',
      time: 'T',
      totalMarks: '10',
      font: font,
      questions: [rq()],
    );

/// The stylesheet of a generated sheet.
String cssOf(String html) => html.split('<style>')[1].split('</style>')[0];

/// The declarations inside one CSS rule, by selector, exactly as written.
String rule(String css, String selector) {
  final match =
      RegExp('${RegExp.escape(selector)}\\s*\\{([^}]*)\\}').firstMatch(css);
  return match == null ? '' : match.group(1)!;
}

/// One declaration's value inside a rule body, or null when it is not set.
String? decl(String body, String property) {
  final match = RegExp('(?:^|;)\\s*${RegExp.escape(property)}\\s*:([^;]*)',
          multiLine: true)
      .firstMatch(body);
  return match?.group(1)?.trim();
}

/// The families the sheet fetches, from its Google Fonts link.
List<String> fetchedFamilies(String html) {
  final link = RegExp('https://fonts\\.googleapis\\.com/css2\\?([^"]+)')
      .firstMatch(html);
  final query = link!.group(1)!;
  return [
    for (final part in query.split('&'))
      if (part.startsWith('family=')) part.substring('family='.length),
  ];
}

void main() {
  group('the sheet', () {
    test('the face it has always used is the one it still uses', () {
      // The default has to leave the sheet exactly as it was before the picker
      // existed: same stack, same single font fetch.
      final html = sheetHtml();

      expect(decl(rule(cssOf(html), 'body'), 'font-family'),
          "'Hind Siliguri', 'SolaimanLipi', sans-serif");
      expect(fetchedFamilies(html), ['Hind+Siliguri:wght@400;500;600;700']);
    });

    test('a face the browser cannot fetch falls back to the one it can', () {
      final html = sheetHtml(font: PaperFont.kalpurush);

      expect(decl(rule(cssOf(html), 'body'), 'font-family'),
          "'Kalpurush', 'SolaimanLipi', 'Hind Siliguri', sans-serif");
      // Kalpurush is not on Google Fonts, so only the fall-back is fetched.
      expect(fetchedFamilies(html), ['Hind+Siliguri:wght@400;500;600;700']);
    });

    test('a web face is fetched alongside the fall-back', () {
      final html = sheetHtml(font: PaperFont.notoSerifBengali);

      expect(decl(rule(cssOf(html), 'body'), 'font-family'),
          "'Noto Serif Bengali', 'SolaimanLipi', 'Hind Siliguri', sans-serif");
      expect(fetchedFamilies(html), [
        'Noto+Serif+Bengali:wght@400;500;600;700',
        'Hind+Siliguri:wght@400;500;600;700',
      ]);
    });

    test('every stack ends in a face the file fetches', () {
      for (final font in PaperFont.values) {
        final html = sheetHtml(font: font);

        expect(font.cssStack, startsWith("'${font.family}'"),
            reason: font.name);
        expect(font.cssStack, endsWith('sans-serif'), reason: font.name);
        expect(font.cssStack, contains("'Hind Siliguri'"), reason: font.name);
        expect(fetchedFamilies(html),
            contains('Hind+Siliguri:wght@400;500;600;700'),
            reason: font.name);
        // No face is ever named twice in one stack.
        expect(font.cssStack.split("'${font.family}'").length - 1, 1,
            reason: font.name);
      }
    });
  });

  group('the Word file', () {
    test('sets the chosen face and keeps its own fall-backs', () {
      expect(
        decl(rule(wordDoc(font: PaperFont.kalpurush), 'body'), 'font-family'),
        "'Kalpurush', 'SolaimanLipi', 'Nirmala UI', 'Vrinda', "
        "'Times New Roman', serif",
      );
    });

    test('names the picked face first, whoever it is', () {
      for (final font in PaperFont.values) {
        final family = decl(rule(wordDoc(font: font), 'body'), 'font-family')!;
        expect(family, startsWith("'${font.family}'"), reason: font.name);
        expect(family, endsWith('serif'), reason: font.name);
      }
    });
  });
}

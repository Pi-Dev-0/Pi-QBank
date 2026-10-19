// A face the app ships travels inside the sheet.
//
// A phone has no Kalpurush installed and no way to install one, so a paper set
// in it used to come out in whatever Bengali face the phone happened to have —
// right on the teacher's laptop, wrong on the student's phone, from one and the
// same file. The app now carries that face and writes it into the sheet as a
// data URI, which is the only thing a phone reading the file can use.
//
// What is locked down here: that the bytes are the face itself, that they are
// declared for Bengali *only* (Latin and the maths symbols keep the faces they
// had), that a sheet carries the one face it is set in and no other, that a
// sheet only ever names a face it actually carries, and that the Word file —
// which cannot carry a face — is untouched by any of it.
//
// Its own file on purpose: the loaded faces live in a static cache, and the
// tests in paper_font_test.dart are about the sheets that carry none.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

String sheetHtml({PaperFont font = PaperFont.kalpurush}) =>
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

String wordDoc({PaperFont font = PaperFont.kalpurush}) =>
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

/// The declarations inside one CSS rule, by selector.
String rule(String css, String selector) {
  final match =
      RegExp('${RegExp.escape(selector)}\\s*\\{([^}]*)\\}').firstMatch(css);
  return match == null ? '' : match.group(1)!;
}

/// One declaration's value inside a rule body, or null when it is not set.
String? decl(String body, String property) => RegExp(
        '(?:^|;)\\s*${RegExp.escape(property)}\\s*:([^;]*)', multiLine: true)
    .firstMatch(body)
    ?.group(1)
    ?.trim();

/// The `@font-face` rules the sheet carries, as written.
List<String> embeddedFaces(String html) =>
    RegExp('@font-face\\s*\\{[^}]*\\}').allMatches(html).map((m) => m[0]!).toList();

/// The face the sheet embedded, decoded from its data URI.
Uint8List embeddedBytes(String html) {
  final uri = RegExp(r'url\((data:font/ttf;base64,[^)]+)\)').firstMatch(html);
  expect(uri, isNotNull, reason: 'no face was embedded');
  final encoded = uri!.group(1)!.split(',').last;
  return base64Decode(encoded);
}

/// The code point ranges a `unicode-range` declaration covers.
List<(int, int)> codePointRanges(String faceRule) {
  final value = decl(faceRule, 'unicode-range');
  if (value == null) return const [];
  return [
    for (final part in value.split(','))
      if (part.trim().isNotEmpty) _parseRange(part.trim()),
  ];
}

(int, int) _parseRange(String part) {
  final pieces = part.replaceFirst('U+', '').split('-');
  final start = int.parse(pieces.first, radix: 16);
  return (start, pieces.length > 1 ? int.parse(pieces[1], radix: 16) : start);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the face the app carries', () {
    test('Kalpurush is carried, so no machine has to have it', () {
      expect(PaperFont.kalpurush.isBundled, isTrue);
      expect(File(PaperFont.kalpurush.asset).existsSync(), isTrue,
          reason: '${PaperFont.kalpurush.asset} must ship with the app');
      expect(File(PaperFont.kalpurush.asset).lengthSync(), greaterThan(1024));
    });

    test('a face it does not carry is still marked as one to install', () {
      // SolaimanLipi is not shipped with the app, and Nirmala UI is Windows' own
      // and cannot be handed out, so a paper set in either only comes out right
      // where the face is installed.
      expect(PaperFont.solaimanLipi.needsInstalling, isTrue);
      expect(PaperFont.nirmalaUi.needsInstalling, isTrue);
      expect(PaperFont.kalpurush.needsInstalling, isFalse);
      // A fetched face is neither: the sheet brings it over the network.
      expect(PaperFont.hindSiliguri.needsInstalling, isFalse);
      expect(PaperFont.hindSiliguri.isBundled, isFalse);
    });

    test('a sheet with no face in hand names it by name, not by data URI', () {
      // Nothing has been loaded yet, so the sheet must not pretend to carry a
      // face: no @font-face, and the stack it has always written.
      expect(HighSchoolExportService.carriesPaperFont(PaperFont.kalpurush),
          isFalse,
          reason: 'this test has to run before the faces are loaded');

      final html = sheetHtml();
      expect(embeddedFaces(html), isEmpty);
      expect(decl(rule(html, 'body'), 'font-family'), PaperFont.kalpurush.cssStack);
      expect(html, isNot(contains(PaperFont.kalpurush.embeddedFamily)));
    });

    test('loading the faces puts them in hand, once', () async {
      await HighSchoolExportService.preloadPaperFonts();
      expect(HighSchoolExportService.carriesPaperFont(PaperFont.kalpurush),
          isTrue);
      // Loading again is a no-op rather than a failure.
      await HighSchoolExportService.preloadPaperFonts();
      expect(HighSchoolExportService.carriesPaperFont(PaperFont.kalpurush),
          isTrue);
    });

    test('the sheet then carries the face itself', () {
      final html = sheetHtml();

      final faces = embeddedFaces(html);
      expect(faces, hasLength(1));
      expect(decl(faces.first, 'font-family'),
          "'${PaperFont.kalpurush.embeddedFamily}'");
      expect(faces.first, contains('data:font/ttf;base64,'));
      // The stack asks for the carried copy first — it is the only copy a phone
      // has — and keeps the face's own name for a letter it might miss.
      expect(decl(rule(html, 'body'), 'font-family'),
          PaperFont.kalpurush.embeddedStack);
      expect(decl(rule(html, 'body'), 'font-family'),
          startsWith("'${PaperFont.kalpurush.embeddedFamily}', sans-serif"));
      expect(decl(rule(html, 'body'), 'font-family'),
          contains("'Kalpurush'"));
    });

    test('the bytes it carries are the face itself', () {
      final bytes = embeddedBytes(sheetHtml());
      final onDisk = File(PaperFont.kalpurush.asset).readAsBytesSync();

      expect(bytes, onDisk,
          reason: 'the sheet must carry the very file the app ships');
      // A TrueType outline, and a name table that says which face it is.
      expect(bytes.sublist(0, 4), [0x00, 0x01, 0x00, 0x00]);
      expect(utf8.decode(bytes, allowMalformed: true), contains('Kalpurush'));
    });

    test('the carried face is used for Bengali and nothing else', () {
      // The range is the point of it: a Latin run (a `\` in a set difference, a
      // C:\Users\… path) is not something this face may draw, so it still falls
      // through to the Latin face, exactly as the named stack and the PDF do.
      final face = embeddedFaces(sheetHtml()).first;
      final ranges = codePointRanges(face);

      bool covered(int codePoint) =>
          ranges.any((r) => codePoint >= r.$1 && codePoint <= r.$2);

      expect(covered(0x0995), isTrue, reason: 'ক');
      expect(covered(0x09CD), isTrue, reason: 'the hasanta that shapes conjuncts');
      expect(covered(0x09E6), isTrue, reason: 'Bengali zero');
      expect(covered(0x0964), isTrue, reason: 'the danda a sentence ends with');
      expect(covered(0x005C), isFalse, reason: r'backslash');
      expect(covered(0x0041), isFalse, reason: 'A');
      expect(covered(0x0031), isFalse, reason: '1');
      expect(covered(0x0020), isFalse, reason: 'space');
      expect(covered(0x222A), isFalse, reason: '∪, which the .m class sets');
    });

    test('a face the app does not carry is never embedded', () async {
      // The sheets that name a fetched face keep the markup they always had.
      final html = sheetHtml(font: PaperFont.hindSiliguri);
      expect(embeddedFaces(html), isEmpty);
      expect(decl(rule(html, 'body'), 'font-family'),
          PaperFont.hindSiliguri.cssStack);
    });

    test('a sheet carries the one face it is set in, and no other', () {
      for (final font in PaperFont.values) {
        final html = sheetHtml(font: font);
        final faces = embeddedFaces(html);

        expect(faces, hasLength(font.isBundled ? 1 : 0), reason: font.name);
        if (!font.isBundled) {
          expect(decl(rule(html, 'body'), 'font-family'), font.cssStack,
              reason: font.name);
          continue;
        }
        expect(decl(faces.first, 'font-family'), "'${font.embeddedFamily}'",
            reason: font.name);
        expect(embeddedBytes(html), File(font.asset).readAsBytesSync(),
            reason: font.name);
        expect(decl(rule(html, 'body'), 'font-family'), font.embeddedStack,
            reason: font.name);
        // No other face's copy is dragged along, and no face is named that the
        // sheet does not carry.
        for (final other in PaperFont.values.where((f) => f != font)) {
          if (!other.isBundled) continue;
          expect(html, isNot(contains(other.embeddedFamily)),
              reason: '${font.name} carried ${other.name}');
        }
      }
    });

    test('the Word file is untouched: it names the face and carries nothing', () {
      final doc = wordDoc();
      expect(decl(rule(doc, 'body'), 'font-family'),
          startsWith("'Kalpurush'"));
      expect(doc, isNot(contains('@font-face')));
      expect(doc, isNot(contains('data:font/ttf;base64,')));
    });
  });
}

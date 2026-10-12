import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pi_qbank/bijoy_helper/bijoy_helper.dart' as bh;
import 'package:pi_qbank/utils/pdf_mixed_text.dart';

pw.Font loadSutonny() => pw.Font.ttf(
      ByteData.sublistView(
          File('assets/fonts/SutonnyMJ Regular.ttf').readAsBytesSync()),
    );

/// The font actually used for a span, as the renderer sees it.
pw.Font? effectiveFont(pw.TextSpan span) =>
    span.style?.fontNormal ?? span.style?.font;

void main() {
  late pw.Font sutonny;

  setUp(() => sutonny = loadSutonny());

  pw.TextStyle banglaStyle({double size = 11, bool bold = false}) =>
      pw.TextStyle(
        font: sutonny,
        fontSize: size,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      );

  group('mixed Bangla/Latin PDF text', () {
    test('pure English uses the Latin font', () {
      final span = buildPdfTextSpan('Greenfield Public School', banglaStyle());
      final kids = span.children as List;
      expect(kids.length, 1);
      expect(identical(effectiveFont(kids.first as pw.TextSpan), sutonny),
          isFalse);
    });

    test('pure Bangla stays in SutonnyMJ', () {
      final span = buildPdfTextSpan('বিষয়: উচ্চতর গণিত', banglaStyle());
      final kids = (span.children as List).cast<pw.TextSpan>();
      // Punctuation such as ": " is its own Latin segment by design, so assert
      // that the Bengali runs kept the Bangla font.
      expect(kids.where((k) => identical(effectiveFont(k), sutonny)), isNotEmpty);
    });

    test('mixed line splits Bangla and Latin across fonts', () {
      final span =
          buildPdfTextSpan('১. A = {1, 2, 3} এবং B দেওয়া আছে।', banglaStyle());
      final kids = (span.children as List).cast<pw.TextSpan>();

      final bangla = kids.where((k) => identical(effectiveFont(k), sutonny));
      final latin = kids.where((k) => !identical(effectiveFont(k), sutonny));
      expect(bangla, isNotEmpty, reason: 'no Bangla run found');
      expect(latin, isNotEmpty, reason: 'no Latin run found');
    });

    test('Latin run keeps its exact original text', () {
      const sentence = 'If x belongs to A, find x^2 and show the value.';
      final span = buildPdfTextSpan('খ. $sentence', banglaStyle());
      final latinText = (span.children as List)
          .cast<pw.TextSpan>()
          .where((k) => !identical(effectiveFont(k), sutonny))
          .map((k) => k.text)
          .join();
      expect(latinText, contains(sentence));
    });

    test('regression: copyWith(font:) alone leaves the Bangla font in place', () {
      // This is why buildPdfTextSpan overrides all four font slots.
      final base = banglaStyle();
      expect(identical(base.fontNormal, sutonny), isTrue);

      final latin = pw.Font.helvetica();
      final naive = base.copyWith(font: latin);
      // `font` on TextStyle is a *derived getter*, and copyWith forwards it to
      // the constructor — which only uses it to seed the four slots when they
      // are null. fontNormal is already set, so the argument is discarded.
      expect(identical(naive.fontNormal, sutonny), isTrue);
      expect(identical(naive.font, sutonny), isTrue);

      final correct = base.copyWith(
        font: latin,
        fontNormal: latin,
        fontBold: latin,
        fontItalic: latin,
        fontBoldItalic: latin,
      );
      expect(identical(correct.fontNormal, sutonny), isFalse);
    });

    test('bold Latin does not fall back to the Bangla font', () {
      final span =
          buildPdfTextSpan('Dhaka Board', banglaStyle(bold: true), bold: true);
      final kid = (span.children as List).first as pw.TextSpan;
      // Font.helveticaBold() builds a fresh instance per call, so identity
      // cannot be asserted against it — assert it is not the Bangla font, and
      // that every font slot was overridden (a bold span reads fontBold).
      expect(identical(effectiveFont(kid), sutonny), isFalse);
      expect(identical(kid.style?.fontBold, sutonny), isFalse);
      expect(identical(kid.style?.fontNormal, sutonny), isFalse);
    });

    test('empty input is safe', () {
      expect(buildPdfTextSpan('', banglaStyle()).text, '');
    });
  });

  group('Bijoy conversion leaves no Bengali Unicode codepoints', () {
    // SutonnyMJ has no Bengali Unicode cmap, so a stray U+0980-U+09FF char
    // renders as a black box mid-word.
    void expectNoBengaliUnicode(String label, String out) {
      final strays = out.runes
          .where((r) => r >= 0x0980 && r <= 0x09FF)
          .map((r) => 'U+${r.toRadixString(16).toUpperCase().padLeft(4, '0')}')
          .toSet();
      expect(strays, isEmpty, reason: '$label left $strays unconverted');
    }

    test('decomposed da+nukta composes to U+09DC', () {
      expectNoBengaliUnicode('da+nukta', bh.unicodeToBijoy('\u09A1\u09BC'));
      expect(bh.unicodeToBijoy('\u09A1\u09BC'), bh.unicodeToBijoy('\u09DC'));
    });

    test('decomposed dha+nukta composes to U+09DD', () {
      expectNoBengaliUnicode('dha+nukta', bh.unicodeToBijoy('\u09A2\u09BC'));
      expect(bh.unicodeToBijoy('\u09A2\u09BC'), bh.unicodeToBijoy('\u09DD'));
    });

    test('common word "পড়ে" converts without a stray nukta', () {
      expectNoBengaliUnicode('পড়ে', bh.unicodeToBijoy('পড়ে'));
    });

    test('processText output is free of Bengali Unicode', () {
      const samples = [
        'পড়ে প্রশ্নের উত্তর দাও।',
        'ড় ও ঢ় থেকে',
        'নির্ণেয়',
        'উদ্দীপক',
      ];
      for (final s in samples) {
        for (final seg in bh.BanglaTextProcessor.processText(s)) {
          expectNoBengaliUnicode('"$s"', seg.text);
        }
      }
    });
  });

  test('a real page renders without throwing', () async {
    final mathFont = pw.Font.ttf(
      ByteData.sublistView(
          File('assets/fonts/MathSymbols.ttf').readAsBytesSync()),
    );
    final style = banglaStyle();
    final withFallback = style.copyWith(fontFallback: [mathFont]);

    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (_) => pw.Column(children: [
        pw.RichText(text: buildPdfTextSpan('Greenfield Public School', style)),
        pw.RichText(text: buildPdfTextSpan('বিষয়: উচ্চতর গণিত', style)),
        pw.RichText(
            text: buildPdfTextSpan('১. যদি A = {1, 2, 3} হয়, তাহলে n(A) = কত?',
                style)),
        // The math line that used to log "Unable to find a font to draw".
        pw.RichText(
            text: buildPdfTextSpan(
                'যদি A ∩ B ≠ ∅ এবং x ∈ A, তবে √x ≤ ৫ এবং α ≥ β', withFallback)),
      ]),
    ));
    final bytes = await doc.save();
    expect(bytes.length, greaterThan(400));
    File('/tmp/opencode/math.pdf').writeAsBytesSync(bytes);
  });

  group('math symbol fallback', () {
    const symbols = '∩∪∈∅≠≤≥×√Σ−αβ²→≈±∀∃';

    /// Render [text] and capture the pdf package's "Unable to find a font" log.
    Future<List<String>> missingFontLogs(
      String text, {
      pw.Font? fallbackFont,
    }) async {
      final logs = <String>[];
      final zone = Zone.root.fork(specification: ZoneSpecification(
        print: (self, parent, zone, line) {
          if (line.contains('Unable to find a font')) logs.add(line);
          parent.print(zone, line);
        },
      ));
      await zone.run(() async {
        final style = pw.TextStyle(
          font: sutonny,
          fontFallback: fallbackFont == null ? const [] : [fallbackFont],
          fontSize: 14,
        );
        final doc = pw.Document();
        doc.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (_) => pw.RichText(text: buildPdfTextSpan(text, style)),
        ));
        await doc.save();
      });
      return logs;
    }

    test('without a fallback the math symbols cannot be drawn', () async {
      final logs = await missingFontLogs('A ∩ B ∪ C');
      expect(logs, isNotEmpty,
          reason: 'expected the pdf package to warn about missing glyphs');
    });

    test('the bundled MathSymbols font removes every warning', () async {
      final mathFont = pw.Font.ttf(
        ByteData.sublistView(
            File('assets/fonts/MathSymbols.ttf').readAsBytesSync()),
      );
      final logs = await missingFontLogs(symbols, fallbackFont: mathFont);
      expect(logs, isEmpty,
          reason: 'still missing glyphs: ${logs.join(' | ')}');
    });

    test('fallback does not disturb Bangla or English', () async {
      final mathFont = pw.Font.ttf(
        ByteData.sublistView(
            File('assets/fonts/MathSymbols.ttf').readAsBytesSync()),
      );
      final logs = await missingFontLogs(
        'যদি A ∩ B ≠ ∅ হয়, তবে n(A) = 3 এবং √x ≤ ৫',
        fallbackFont: mathFont,
      );
      expect(logs, isEmpty);
    });

    test('fontFallback survives the Latin copyWith path', () {
      final mathFont = pw.Font.ttf(
        ByteData.sublistView(
            File('assets/fonts/MathSymbols.ttf').readAsBytesSync()),
      );
      final span = buildPdfTextSpan(
        'n(A ∩ B)',
        banglaStyle().copyWith(fontFallback: [mathFont]),
      );
      for (final k in span.children as List) {
        final st = (k as pw.TextSpan).style;
        expect(st?.fontFallback, isNotNull);
        expect(st?.fontFallback, isNotEmpty);
      }
    });
  });
}
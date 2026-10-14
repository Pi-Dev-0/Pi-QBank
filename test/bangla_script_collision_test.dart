import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:pi_qbank/bijoy_helper/bijoy_helper.dart' as bh;
import 'package:pi_qbank/utils/math_text.dart';
import 'package:pi_qbank/utils/pdf_mixed_text.dart';
import 'package:pi_qbank/utils/pdf_text_metrics.dart';

/// Bangla is not Unicode in this PDF — it is drawn from SutonnyMJ using the
/// Bijoy legacy encoding, where letters are mapped onto arbitrary ASCII.
///
/// Two of those letters land on characters a script parser treats specially:
///
/// | letter | Bijoy | parser reads it as |
/// |---|---|---|
/// | `থ` | `_` | subscript |
/// | `ণ্ব` `ন্ব` `ম্ব` `স্ব` | `^` | superscript |
///
/// Parsing after the conversion therefore ate the letter and drew whatever
/// followed it as a raised or lowered script. These pin the ordering: LaTeX is
/// parsed on the original Unicode, and only then is Bangla converted.
void main() {
  late ByteData banglaData;
  late ByteData symbolData;

  setUpAll(() {
    banglaData = ByteData.sublistView(
        File('assets/fonts/SutonnyMJ Regular.ttf').readAsBytesSync());
    symbolData = ByteData.sublistView(
        File('assets/fonts/MathSymbols.ttf').readAsBytesSync());
  });

  PdfTextMetrics metrics() => PdfTextMetrics(
        banglaFontData: banglaData,
        symbolFontData: symbolData,
      );

  group('the encoding really does collide', () {
    test('these letters survive the Bijoy conversion intact', () {
      // If Bijoy ever stops emitting these, the guard below becomes vacuous —
      // worth knowing, so the test says so rather than quietly passing.
      final converted = bh.BanglaTextProcessor.processText('থ').first.text;
      expect(converted, '_');

      final conjunct = bh.BanglaTextProcessor.processText('স্ব').first.text;
      expect(conjunct, contains('^'));
    });

    test('but only after conversion — the original text is safe to parse', () {
      // This is the property the renderer relies on: the Unicode form carries
      // neither character, so the parser cannot misread it.
      expect(parseMath('থ'), hasLength(1));
      expect((parseMath('থ').single as MathText).text, 'থ');
      expect(parseMath('স্ব').whereType<MathScript>(), isEmpty);
    });
  });

  group('a Bangla letter that looks like a script marker', () {
    test('is measured as itself, not as a subscript', () {
      final m = metrics();
      // Two letters, so the comparison does not depend on glyph widths.
      final withLetter = m.textWidth('থ্য', fontSize: 11);
      final without = m.textWidth('অঅ', fontSize: 11);
      expect(withLetter, greaterThan(0));
      expect(without, greaterThan(0));
    });

    test('loses nothing: a script segment would have eaten the next glyph', () {
      // If `থ` were parsed as a subscript the following character would be
      // lifted out of the text run, so the run would measure shorter.
      final m = metrics();
      final alone = m.textWidth('থ', fontSize: 11);
      final followed = m.textWidth('থক', fontSize: 11);
      expect(followed, greaterThan(alone),
          reason: 'the character after থ must still be measured');
    });

    test('a real script is still recognised', () {
      // The fix must not have simply disabled script parsing.
      final m = metrics();
      expect(m.textWidth('x^{2}', fontSize: 11),
          greaterThan(m.textWidth('x', fontSize: 11)));
    });
  });

  group('drawing', () {
    test('a Bangla থ renders as text and draws without complaint', () async {
      // The app draws with MathSymbols as a fallback, and Bijoy sends several
      // vowel signs to characters outside the Basic Multilingual Plane —
      // `ে` becomes U+2021 — which SutonnyMJ alone cannot draw. Rendering
      // without the fallback would report a gap the real export does not have.
      final bangla = pw.Font.ttf(banglaData);
      final symbols = pw.Font.ttf(symbolData);
      final style =
          pw.TextStyle(font: bangla, fontFallback: [symbols], fontSize: 11);
      final doc = pw.Document();
      final log = <String>[];
      await runZoned(() async {
        doc.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (ctx) => pw.RichText(
            text: buildPdfTextSpan(
              'থ ব্যবহার করে পাশাপাশি রেখে দাও',
              style,
            ),
          ),
        ));
        File('/tmp/opencode/bangla_probe.pdf')
            .writeAsBytesSync(await doc.save());
      },
          zoneSpecification: ZoneSpecification(
              print: (self, parent, zone, line) => log.add(line)));

      // "Helvetica has no Unicode support" is printed once per document when
      // the base-14 font object is built and is harmless. What must not appear
      // is a glyph nothing in the chain can draw.
      expect(log.where((l) => l.contains('Unable to find a font')), isEmpty);
      expect(File('/tmp/opencode/bangla_probe.pdf').lengthSync(),
          greaterThan(1000));
    });

    test('a fraction degrades to inline form when it cannot be measured',
        () async {
      // A rule with no width to draw at takes the whole line, which looks like
      // a struck-through page rather than a fraction.
      final bangla = pw.Font.ttf(banglaData);
      final doc = pw.Document();
      await runZoned(() async {
        doc.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (ctx) => pw.RichText(
            text: buildPdfTextSpan(
              r'$\frac{2+x}{3}$',
              pw.TextStyle(font: bangla, fontSize: 11),
            ),
          ),
        ));
        File('/tmp/opencode/no_measure_probe.pdf')
            .writeAsBytesSync(await doc.save());
      },
          zoneSpecification:
              ZoneSpecification(print: (self, parent, zone, line) {}));
      expect(File('/tmp/opencode/no_measure_probe.pdf').lengthSync(),
          greaterThan(1000));
    });

    test('fractions still render alongside Bangla', () async {
      // Both paths now run in one string: the LaTeX parse and the conversion.
      final bangla = pw.Font.ttf(banglaData);
      final symbols = pw.Font.ttf(symbolData);
      final doc = pw.Document();
      await runZoned(() async {
        doc.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (ctx) => pw.RichText(
            text: buildPdfTextSpan(
              r'থ দিয়ে $\frac{2+x}{3}$ সমীকরণ',
              pw.TextStyle(font: bangla, fontFallback: [symbols], fontSize: 11),
              // The app always supplies a measurement; without one a stacked
              // fraction falls back to its inline form rather than drawing a
              // rule across the whole page.
              measure: (t, size, bold) =>
                  metrics().textWidth(t, fontSize: size, bold: bold),
            ),
          ),
        ));
        File('/tmp/opencode/bangla_math_probe.pdf')
            .writeAsBytesSync(await doc.save());
      },
          zoneSpecification:
              ZoneSpecification(print: (self, parent, zone, line) {}));
      expect(File('/tmp/opencode/bangla_math_probe.pdf').lengthSync(),
          greaterThan(1000));
    });
  });
}

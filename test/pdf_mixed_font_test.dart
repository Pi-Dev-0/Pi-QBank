import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pi_qbank/bijoy_helper/bijoy_helper.dart' as bh;
import 'package:pi_qbank/models/highschool_question.dart';
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
      expect(
          kids.where((k) => identical(effectiveFont(k), sutonny)), isNotEmpty);
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

    test('regression: copyWith(font:) alone leaves the Bangla font in place',
        () {
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

    group('short questions (RQ)', () {
      HighSchoolQuestion rq({
        String type = 'RQ',
        String text = 'সমান্তর সরলরেখার ঢাল কত?',
        Object? sub,
        Object? shortMark,
      }) {
        return HighSchoolQuestion.fromJson({
          'id': 'r1',
          'class': 'Class (9-10) SSC',
          'subject': 'উচ্চতর গণিত',
          'chapter_number': '2',
          'chapter_name': 'সমীকরণ',
          'question_type': type,
          'stem_text': text,
          'stem_image_url': '',
          'sub_questions_json': sub ?? <Object>[],
          'board_year_tag': '',
          'short_mark': shortMark,
        });
      }

      test('is recognised as its own type, not CQ or MCQ', () {
        final q = rq();
        expect(q.isShort, isTrue);
        expect(q.isCq, isFalse);
        expect(q.isMcq, isFalse);
      });

      test('accepts the SHORT alias', () {
        expect(rq(type: 'SHORT').isShort, isTrue);
      });

      test('reads the text from stem_text', () {
        final q = rq();
        expect(q.shortData?.text, 'সমান্তর সরলরেখার ঢাল কত?');
      });

      test('is worth one mark by default', () {
        expect(rq().shortData?.mark, 1);
        expect(rq().totalMarks, 1);
      });

      test('the mark varies per question', () {
        expect(rq(shortMark: 2).shortData?.mark, 2);
        expect(rq(shortMark: 2).totalMarks, 2);
        expect(rq(shortMark: 3).totalMarks, 3);
      });

      test('reads a mark sent as a string (how the Sheet stores it)', () {
        expect(rq(shortMark: '2').shortData?.mark, 2);
      });

      test('falls back to 1 for a missing or nonsense mark', () {
        expect(rq(shortMark: '').shortData?.mark, 1);
        expect(rq(shortMark: 'abc').shortData?.mark, 1);
        expect(rq(shortMark: 0).shortData?.mark, 1);
        expect(rq(shortMark: -3).shortData?.mark, 1);
      });

      test('different short questions can carry different marks', () {
        final a = rq(text: 'প্রথম', shortMark: 1);
        final b = rq(text: 'দ্বিতীয়', shortMark: 2);
        expect(a.totalMarks + b.totalMarks, 3);
      });

      test('sub_questions_json is not used', () {
        // Even if something odd is stored there, stem_text and short_mark win.
        final q = rq(sub: {'text': 'ভুল লেখা', 'mark': 5}, shortMark: 2);
        expect(q.shortData?.text, 'সমান্তর সরলরেখার ঢাল কত?');
        expect(q.totalMarks, 2);
      });

      test('honours a legacy payload when stem_text is empty', () {
        // Rows written by an older uploader kept the text in sub_questions_json.
        final q = rq(text: '', sub: {'text': 'পুরোনো লেখা'});
        expect(q.shortData?.text, 'পুরোনো লেখা');
      });

      test('survives a JSON-encoded legacy payload', () {
        final q = rq(text: '', sub: '{"text":"পুরোনো লেখা"}');
        expect(q.shortData?.text, 'পুরোনো লেখা');
      });

      test('toJson keeps the text in stem_text and empties the payload', () {
        final json = rq(shortMark: 2).toJson();
        expect(json['stem_text'], 'সমান্তর সরলরেখার ঢাল কত?');
        expect(json['sub_questions_json'], isEmpty);
        expect(json['short_mark'], 2);
      });

      test('short_mark is not emitted for CQ or MCQ', () {
        final mcq = HighSchoolQuestion.fromJson({
          'id': 'm1',
          'class': 'Class (9-10) SSC',
          'subject': 's',
          'chapter_number': '1',
          'chapter_name': 'c',
          'question_type': 'MCQ',
          'stem_text': '',
          'stem_image_url': '',
          'sub_questions_json': {
            'text': 'q',
            'options': ['a', 'b'],
            'correct_ans': 'a',
          },
          'board_year_tag': '',
        });
        expect(mcq.toJson()['short_mark'], isEmpty);
      });

      test('round-trips through toJson', () {
        final back = HighSchoolQuestion.fromJson(rq().toJson());
        expect(back.isShort, isTrue);
        expect(back.shortData?.text, 'সমান্তর সরলরেখার ঢাল কত?');
      });

      test('an empty RQ has no shortData', () {
        expect(rq(text: '').shortData, isNull);
      });

      test('CQ and MCQ are unaffected', () {
        final cq = HighSchoolQuestion.fromJson({
          'id': 'c1',
          'class': 'Class (9-10) SSC',
          'subject': 's',
          'chapter_number': '1',
          'chapter_name': 'c',
          'question_type': 'CQ',
          'stem_text': 'stem',
          'stem_image_url': '',
          'sub_questions_json': [
            {'label': 'ক', 'mark': 2, 'text': 'a'},
          ],
          'board_year_tag': '',
        });
        expect(cq.isShort, isFalse);
        expect(cq.shortData, isNull);
        expect(cq.totalMarks, 2);
      });
    });

    test('the Bijoy soft-hyphen reorder marker is stripped', () {
      // U+00AD is inserted by the converter and has no glyph in any bundled
      // font, which would draw a black box inside the word. (The Bangla run is
      // Bijoy-encoded here, so compare against the raw converter output.)
      final raw = bh.unicodeToBijoy('প্ল্যাটফর্ম');
      expect(raw.contains('­'), isTrue,
          reason: 'converter is expected to insert U+00AD');

      final span = buildPdfTextSpan('Pi-QBank প্ল্যাটফর্ম থেকে', banglaStyle());
      final all = (span.children as List)
          .cast<pw.TextSpan>()
          .map((k) => k.text ?? '')
          .join();
      expect(all, isNot(contains('­')));
      // Only the marker is gone — the rest of the text is untouched.
      expect(all.replaceAll('­', '').length, greaterThan(raw.length));
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
            text: buildPdfTextSpan(
                '১. যদি A = {1, 2, 3} হয়, তাহলে n(A) = কত?', style)),
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
    // Audited set: the glyphs Bangladeshi school maths papers actually use.
    const symbols = '–—…•×÷±−≠≡≈≤≥'
        '∩∪⊂⊃⊆⊇∅∈∉∀∃¬∧∨'
        '√∛∑∏∫∮∞∂∇∴∵°′″½¼¾'
        '→←↑↓↔⇒⇔⟹'
        '²³¹αβγδθλμπρστφχψωΓΔΘΛΠΣΦΩ'
        '✓✔✗✘☑☐★☆●○■□▲△▼▽◆※†§¶'
        // Modifier / phonetic letters used as superscripts: cosecᶜ, sin⁻¹, xⁿ
        'ᶜᵐⁿˡᵇᵈᵉᶠᵍʰⁱʲᵏᵒᵖʳˢᵗᵘᵛʷˣʸᶻ'
        'ᵀᴬᴮᴰᴱᴳᴴᴵᴶᴷᴸᴹᴺᴼᴾᵀᵁᵂ'
        '⁰⁴⁵⁶⁷⁸⁹⁺⁻⁼⁽⁾ⁿ'
        'ˢ°′″ʹʺ'
        // Combining marks for symbols available in the subset (vector notation
        // in physics): v⃗, a⃑, e⃖. U+20D5 is absent from DejaVu, so it is
        // deliberately not claimed here.
        '⃗⃑⃖';

    /// Render [text] and capture the pdf package's *actionable* font warnings:
    /// "Unable to find a font to draw ..." — i.e. a glyph that no configured
    /// font could supply.
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

    test('the "Helvetica has no Unicode support" line is constructor noise',
        () async {
      // PdfType1Font.create() prints this from an assert in its constructor,
      // once per font instance, whether or not a glyph actually fails. It is
      // informational: Helvetica is correct for plain ASCII, and any character
      // outside WinAnsi is resolved via fontFallback before the primary font
      // is asked to encode it. So we do NOT assert on it — but we assert the
      // fallback genuinely prevents the actionable warning.
      final mathFont = pw.Font.ttf(
        ByteData.sublistView(
            File('assets/fonts/MathSymbols.ttf').readAsBytesSync()),
      );
      // cosecᶜ : U+1D9C is not in WinAnsi, so without the fallback this is a
      // real "Unable to find a font" failure.
      expect(await missingFontLogs('cosecᶜ'), isNotEmpty);
      // With the fallback, zero actionable warnings.
      expect(await missingFontLogs('cosecᶜ', fallbackFont: mathFont), isEmpty);
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

    test('em dash and subset-or-equal are covered', () async {
      // Both were reported as "Unable to find a font to draw".
      final mathFont = pw.Font.ttf(
        ByteData.sublistView(
            File('assets/fonts/MathSymbols.ttf').readAsBytesSync()),
      );
      final logs = await missingFontLogs(
        'প্রশ্ন — A ⊆ B, তাই A ∩ B ≠ ∅',
        fallbackFont: mathFont,
      );
      expect(logs, isEmpty, reason: logs.join(' | '));
    });

    test('modifier-letter superscripts (cosecᶜ) are covered', () async {
      // U+1D9C is what "Unable to find a font to draw ᶜ" was about: Bangla
      // maths writes cosecant as "cosecᶜ".
      final mathFont = pw.Font.ttf(
        ByteData.sublistView(
            File('assets/fonts/MathSymbols.ttf').readAsBytesSync()),
      );
      final logs = await missingFontLogs(
        'cosecᶜx = 1, sin⁻¹(y), xⁿ + log₂N = M³',
        fallbackFont: mathFont,
      );
      expect(logs, isEmpty, reason: logs.join(' | '));
    });

    test('Latin runs resolve non-WinAnsi characters via the fallback',
        () async {
      final mathFont = pw.Font.ttf(
        ByteData.sublistView(
            File('assets/fonts/MathSymbols.ttf').readAsBytesSync()),
      );
      final logs = await missingFontLogs(
        'cosecᶜ and sin⁻¹ are English fragments',
        fallbackFont: mathFont,
      );
      expect(logs, isEmpty, reason: logs.join(' | '));
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

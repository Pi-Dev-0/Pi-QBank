import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/highschool_question.dart';
import '../utils/math_text.dart';

/// Service responsible for exporting High School question papers in multiple formats:
/// - Microsoft Word (.doc with Word XML/HTML formatting)
/// - Web / HTML (.html with print CSS)
/// - Plain Text (.txt)
/// - Markdown (.md)
/// - JSON Data (.json)
/// How stem images are sized in an export.
///
/// The same setting drives PDF (points), Word (points) and HTML (pixels) so the
/// question paper looks consistent no matter which format the student receives.
enum StemImageSize {
  /// Leave stem images out entirely.
  hidden,

  /// Thumbnail — good when there are many figures and space is tight.
  small,

  /// Default — readable on a phone screen and on paper.
  medium,

  /// Large figure, for diagrams that need detail.
  large,
}

extension StemImageSizeMetrics on StemImageSize {
  /// Max height in points, used by PDF and Word. 0 means "don't render".
  double get maxHeightPt {
    switch (this) {
      case StemImageSize.hidden:
        return 0;
      case StemImageSize.small:
        return 70;
      case StemImageSize.medium:
        return 130;
      case StemImageSize.large:
        return 220;
    }
  }

  /// Max width in points. Diagrams are rarely wider than they are tall, and
  /// letting them run to the full column makes small figures look lost.
  double get maxWidthPt {
    switch (this) {
      case StemImageSize.hidden:
        return 0;
      case StemImageSize.small:
        return 140;
      case StemImageSize.medium:
        return 250;
      case StemImageSize.large:
        return 400;
    }
  }

  /// Max height in CSS pixels for HTML (browsers render at ~1.33x points).
  double get maxHeightPx => maxHeightPt * 1.333;

  bool get isVisible => this != StemImageSize.hidden;

  /// Bengali label for the UI selector.
  String get label {
    switch (this) {
      case StemImageSize.hidden:
        return 'ছবি রাখবেন না';
      case StemImageSize.small:
        return 'ছোট';
      case StemImageSize.medium:
        return 'মাঝারি';
      case StemImageSize.large:
        return 'বড়';
    }
  }

  String get description {
    switch (this) {
      case StemImageSize.hidden:
        return 'শুধু লেখা, কোনো ছবি যাবে না';
      case StemImageSize.small:
        return 'ছোট থাম্বনেইল';
      case StemImageSize.medium:
        return 'সাধারণ আকার (প্রস্তাবিত)';
      case StemImageSize.large:
        return 'বড় ডায়াগ্রামের জন্য';
    }
  }
}

/// How MCQ questions are arranged on the page.
///
/// Applied to the CQ and MCQ sections. Short questions (SQ) are one line each
/// and are never split across columns.
enum QuestionLayout {
  /// One question per row, running the full width of the page.
  single,

  /// Two questions per row — the usual exam-paper layout, and much more compact.
  doubleColumn,
}

extension QuestionLayoutMetrics on QuestionLayout {
  /// How many MCQs sit side by side.
  int get mcqColumns => this == QuestionLayout.doubleColumn ? 2 : 1;

  bool get isDouble => this == QuestionLayout.doubleColumn;

  String get label => isDouble ? 'দুই কলাম' : 'এক কলাম';

  String get description => isDouble
      ? 'প্রতি সারিতে দুটি MCQ — কম পেজ, ছোট প্রশ্নপত্র'
      : 'প্রতি সারিতে একটি MCQ — প্রশ্ন ও অপশন সরল দেখা যায়';
}

/// A Bangla face a paper can be printed in.
///
/// The PDF stands apart: it sets Bangla through SutonnyMJ, a Bijoy-ANSI face
/// with a text pipeline of its own, so this choice reaches the HTML sheet and
/// the Word file, not the PDF.
///
/// [family] is the name a stylesheet asks for first. [google] is the Google
/// Fonts family that supplies it over the network when the machine reading the
/// file does not have it installed; a face with no [google] entry is one the
/// machine has to have (Kalpurush and SolaimanLipi ship with the Bangla typing
/// tools teachers already use). Every stack ends in Hind Siliguri, which is
/// always fetched, so the paper prints in something readable either way.
enum PaperFont {
  hindSiliguri('হিন্দ শিলিগুড়ি', 'Hind Siliguri',
      google: 'Hind+Siliguri:wght@400;500;600;700'),
  notoSansBengali('নোটো সানস বাংলা', 'Noto Sans Bengali',
      google: 'Noto+Sans+Bengali:wght@400;500;600;700'),
  notoSerifBengali('নোটো সেরিফ বাংলা', 'Noto Serif Bengali',
      google: 'Noto+Serif+Bengali:wght@400;500;600;700'),
  balooDa('বালু দা ২ (গোলাকার)', 'Baloo Da 2',
      google: 'Baloo+Da+2:wght@400;500;600;700'),
  mina('মিনা (চওড়া)', 'Mina', google: 'Mina:wght@400;700'),
  kalpurush('কলপুরুষ (Kalpurush)', 'Kalpurush'),
  solaimanLipi('সলাইমানলিপি (SolaimanLipi)', 'SolaimanLipi'),
  nirmalaUi('নির্মলা ইউআই (Nirmala UI)', 'Nirmala UI');

  const PaperFont(this.label, this.family, {this.google = ''});

  /// What the picker shows the reader.
  final String label;

  /// The face's own name, without quotes — the first name in every stack and
  /// the name a Word file asks for.
  final String family;

  /// The Google Fonts family query for this face, or empty when it has to be
  /// installed on the machine that opens the file.
  final String google;

  /// Whether reading the file means downloading this face.
  bool get isWebFont => google.isNotEmpty;

  /// The `font-family` a stylesheet sets: a Latin face first, then the chosen
  /// Bangla face, then the other Bangla faces.
  ///
  /// The Latin face comes first on purpose. The Bangla faces here are Bijoy-
  /// ANSI faces: their cmap claims the whole ASCII range and draws Bengali
  /// glyphs for it, so a backslash or a `C:\Users\…` path set in Kalpurush
  /// never reaches a face that can draw it — the browser never falls through.
  /// `sans-serif` takes every Latin run, and the Bangla faces supply everything
  /// they are for. This is exactly what the PDF does: Latin runs are set in
  /// Helvetica, never in the Bijoy font.
  String get cssStack => [
        'sans-serif',
        "'$family'",
        for (final fallback in const ['SolaimanLipi', 'Hind Siliguri'])
          if (fallback != family) "'$fallback'",
      ].join(', ');

  /// The family list a Word file asks for. Word looks for the first face on this
  /// machine, and Kalpurush is the one it is most likely to find — a Word export
  /// from before the picker existed named it first, and it still supplies the
  /// paper wherever Hind Siliguri is not installed.
  String get wordStack => [
        "'$family'",
        for (final fallback in const [
          'Kalpurush',
          'SolaimanLipi',
          'Nirmala UI',
          'Vrinda',
          'Times New Roman',
        ])
          if (fallback != family) "'$fallback'",
        'serif',
      ].join(', ');

  /// The Google Fonts families the sheet has to *fetch* for [font]: the face
  /// itself when it is a web font, Hind Siliguri — which every stack falls back
  /// to, and which is the one text face that is always fetched — and Noto Sans
  /// Math, which the `.m` class puts behind every maths symbol so `∪` and `∩`
  /// come out of the same face.
  static List<String> webFamiliesOf(PaperFont font) {
    const hindSiliguriFamily = 'Hind+Siliguri:wght@400;500;600;700';
    const notoSansMathFamily = 'Noto+Sans+Math';
    return [
      if (font.isWebFont && font.google != hindSiliguriFamily) font.google,
      hindSiliguriFamily,
      notoSansMathFamily,
    ];
  }
}

/// One of the blocks a question paper is divided into.
///
/// The reader can drag the blocks into any order, and that order reaches the
/// exports as a list of these — so the printed paper, the HTML preview and the
/// reorder list in the app all agree. The বাংলা letter a block is headed with
/// comes from its *position* in that list, not from its type: whichever block
/// the reader put first is ক-বিভাগ.
enum PaperSection {
  /// সৃজনশীল প্রশ্ন.
  cq,

  /// সংক্ষিপ্ত প্রশ্ন (the sheet calls these RQ).
  rq,

  /// বহুনির্বাচনী প্রশ্ন.
  mcq;

  /// CQ, then the short questions, then MCQ — the order a paper is printed in
  /// until the reader drags the blocks around.
  static const List<PaperSection> defaultOrder = [cq, rq, mcq];
}

class HighSchoolExportService {
  HighSchoolExportService._();

  // ─────────────────────────────────────────────────────────────────────────
  // Stem image helpers
  //
  // PDF and Word need the actual image bytes; HTML/Markdown only need a URL
  // that a browser can load. Both depend on the URL being *directly fetchable*,
  // which a Google Drive sharing link is not.
  // ─────────────────────────────────────────────────────────────────────────

  /// Largest image we will embed, to stop a few huge originals from blowing up
  /// the exported file (and the base64 payload Word embeds inline).
  static const int maxImageBytes = 5 * 1024 * 1024;
  static const Duration _imageTimeout = Duration(seconds: 20);

  /// Turn a Google Drive sharing link into a direct-download link.
  /// Any other URL is returned unchanged.
  static String resolveImageUrl(String rawUrl) {
    final url = rawUrl.trim();
    if (url.isEmpty) return url;
    if (!url.contains('drive.google.com')) return url;

    // .../file/d/<ID>/view  |  .../file/d/<ID>/preview  |  .../open?id=<ID>
    final fileMatch = RegExp(r'/file/d/([a-zA-Z0-9_-]+)').firstMatch(url);
    if (fileMatch != null) {
      return 'https://drive.google.com/uc?export=download&id=${fileMatch.group(1)}';
    }
    final idMatch = RegExp(r'[?&]id=([a-zA-Z0-9_-]+)').firstMatch(url);
    if (idMatch != null) {
      return 'https://drive.google.com/uc?export=download&id=${idMatch.group(1)}';
    }
    return url;
  }

  /// Download every distinct stem image once, keyed by *resolved* URL.
  ///
  /// Failures are skipped rather than thrown: an unreachable image must not
  /// block the whole export. Returns an empty map when nothing could be
  /// downloaded, and callers fall back to a plain URL reference.
  static Future<Map<String, Uint8List>> prefetchStemImages(
    List<HighSchoolQuestion> questions,
  ) async {
    final wanted = <String>{};
    for (final q in questions) {
      final resolved = resolveImageUrl(q.stemImageUrl);
      if (resolved.isNotEmpty) wanted.add(resolved);
    }
    if (wanted.isEmpty) return <String, Uint8List>{};

    final out = <String, Uint8List>{};
    for (final url in wanted) {
      try {
        final res = await http.get(Uri.parse(url)).timeout(_imageTimeout);
        if (res.statusCode != 200 || res.bodyBytes.isEmpty) continue;
        if (res.bodyBytes.length > maxImageBytes) continue;
        // Sanity check: Drive answers a blocked/large file with HTML.
        final isHtml =
            res.headers['content-type']?.contains('text/html') ?? false;
        if (isHtml) continue;
        out[url] = res.bodyBytes;
      } catch (_) {
        // Ignore — this image will be referenced by URL instead.
      }
    }
    return out;
  }

  /// Identify the image format from its magic bytes.
  ///
  /// Stem diagrams are very often JPEG or WEBP, so guessing "png" would emit a
  /// wrong MIME type in the data URI. Falls back to image/png.
  static String sniffImageMime(Uint8List bytes) {
    bool starts(List<int> sig, [int offset = 0]) {
      if (bytes.length < offset + sig.length) return false;
      for (var i = 0; i < sig.length; i++) {
        if (bytes[offset + i] != sig[i]) return false;
      }
      return true;
    }

    if (starts([0x89, 0x50, 0x4E, 0x47])) return 'image/png';
    if (starts([0xFF, 0xD8, 0xFF])) return 'image/jpeg';
    if (starts([0x47, 0x49, 0x46, 0x38])) return 'image/gif';
    if (starts([0x42, 0x4D])) return 'image/bmp';
    // RIFF....WEBP
    if (starts([0x52, 0x49, 0x46, 0x46]) &&
        starts([0x57, 0x45, 0x42, 0x50], 8)) {
      return 'image/webp';
    }
    return 'image/png';
  }

  /// An `<img>`/data-URI fragment for the stem image, or '' when there is none.
  ///
  /// [bytes] lets Word embed the image inline (Word will not reliably render a
  /// remote <img src>); HTML/Markdown pass null and just link to the URL.
  static String _stemImageMarkup(
    HighSchoolQuestion q, {
    Map<String, Uint8List>? bytes,
    required StemImageSize size,
    required bool usePoints,
  }) {
    if (!size.isVisible) return '';
    final resolved = resolveImageUrl(q.stemImageUrl);
    if (resolved.isEmpty) return '';

    final imageBytes = bytes?[resolved];
    final src = imageBytes != null
        ? 'data:${sniffImageMime(imageBytes)};base64,${base64Encode(imageBytes)}'
        : _escapeXml(resolved);

    final unit = usePoints ? 'pt' : 'px';
    final maxH = usePoints ? size.maxHeightPt : size.maxHeightPx;
    final maxW = usePoints ? size.maxWidthPt : size.maxWidthPt * 1.333;

    return '<img src="$src" alt="উদ্দীপক চিত্র" '
        'style="display:block; margin:4pt 0 6pt 0; '
        'max-width:${_trimNum(maxW)}$unit; max-height:${_trimNum(maxH)}$unit; '
        'object-fit:contain; '
        '${usePoints ? '' : 'margin-left:auto; margin-right:auto;'}" />';
  }

  /// Trim a double for CSS output (no trailing ".0").
  static String _trimNum(double v) {
    if (v == v.roundToDouble()) return v.round().toString();
    return v.toStringAsFixed(1);
  }

  /// True when the stem image should appear at all.
  static bool _hasStemImage(HighSchoolQuestion q, StemImageSize size) =>
      size.isVisible && resolveImageUrl(q.stemImageUrl).isNotEmpty;

  static String _stemImageUrlOf(HighSchoolQuestion q) =>
      resolveImageUrl(q.stemImageUrl);

  // ─────────────────────────────────────────────────────────────────────────
  // Shared-উদ্দীপক question numbers
  // ─────────────────────────────────────────────────────────────────────────

  /// Where an author puts the question numbers when the intro should carry
  /// whatever the paper ends up numbering them: `নিচের তথ্যের আলোকে ({}) নং…`.
  static const String stemNumbersPlaceholder = '{}';

  /// The `(১২ ও ১৩) নং` reference inside a shared intro.
  ///
  /// The bank's intros are copied verbatim from the board paper they came from,
  /// so they name *that* paper's numbers while a generated paper prints the
  /// questions wherever they were picked — `(১২ ও ১৩)` above questions numbered
  /// 1 and 2. The group has to start with a digit, so `(ক) ও (খ) নং প্রশ্ন` — the
  /// other form the phrase appears in — is left alone, and the reference has to
  /// be followed by নং/নম্বর so `(২০২৩) সালের…` is not mistaken for one.
  static final RegExp _stemNumbersRef = RegExp(
      r'\(([0-9\u09E6-\u09EF][0-9\u09E6-\u09EF\s,ওএবং\-–—]*)\)'
      r'(\s*(?:নং|নম্বর))');

  /// The same reference written bare: `২৬ ও ২৭ নং`, `12, 13 নম্বর`.
  ///
  /// Two numbers at least. A lone `৫ নং` is too easily a figure reference
  /// ("চিত্র ৫ নং"), so that form is left to [stemNumbersPlaceholder] or to the
  /// bracketed one, where it is unambiguous.
  static final RegExp _bareStemNumbersRef = RegExp(
      '([0-9\\u09E6-\\u09EF]+(?:\\s*(?:,|ও|এবং|and|&|\\-|–|—)\\s*[0-9\\u09E6-\\u09EF]+)+)'
      '(\\s*(?:নং|নম্বর))');

  /// The numbers of the questions that share the উদ্দীপক introduced at [start].
  ///
  /// These are the numbers the writer prints, so the helper takes the position
  /// in the list rather than the question: a run is the questions the model
  /// says share the intro (see [HighSchoolQuestion.sharesMcqStemWith]), which is
  /// what decides where one উদ্দীপক stops and the next begins.
  static List<int> mcqStemRunNumbers(
      List<HighSchoolQuestion> mcqs, int start) {
    if (start < 0 || start >= mcqs.length) return const [];
    final numbers = <int>[start + 1];
    for (var j = start; j + 1 < mcqs.length; j++) {
      if (!mcqs[j + 1].sharesMcqStemWith(mcqs[j])) break;
      numbers.add(j + 2);
    }
    return numbers;
  }

  /// [intro] with its "which questions" reference naming [numbers].
  ///
  /// The digits stay in the intro's own hand: an intro that wrote `(১২ ও ১৩)` is
  /// rewritten as `(১ ও ২)` in Bengali, one that wrote `(12, 13)` in ASCII. The
  /// intro is prose, so it should read like the book it was copied from; only
  /// the numbers are the paper's.
  ///
  /// An intro with nothing to rewrite — no `নং` reference, no
  /// [stemNumbersPlaceholder] — comes back untouched, which is what an author
  /// who never numbered anything wants.
  static String stemWithNumbers(String intro, List<int> numbers) {
    if (intro.isEmpty || numbers.isEmpty) return intro;
    // The placeholder takes Bengali: there is no reference to copy the hand
    // from, and the paper writes Bengali.
    if (intro.contains(stemNumbersPlaceholder)) {
      return intro.replaceAll(stemNumbersPlaceholder,
          _joinStemNumbers(numbers, bengali: true));
    }
    // Otherwise the new numbers take the hand of the reference they replace —
    // and only of *that*: an intro's own text is full of ASCII digits (`U = {1,
    // 2, 3, 4, 5, 6}`), which says nothing about how its question numbers were
    // written.
    //
    // The bracketed form first, then the bare one; both are idempotent, so a
    // reference just rewritten inside its brackets is left alone.
    var out = intro.replaceAllMapped(_stemNumbersRef, (m) {
      final joined = _joinStemNumbers(numbers,
          bengali: _writtenInBengaliDigits(m.group(1)!));
      return '($joined)${m.group(2)}';
    });
    out = out.replaceAllMapped(_bareStemNumbersRef, (m) {
      final joined = _joinStemNumbers(numbers,
          bengali: _writtenInBengaliDigits(m.group(1)!));
      return '$joined${m.group(2)}';
    });
    return out;
  }

  /// Whether [text] has any Bengali digit in it.
  static bool _writtenInBengaliDigits(String text) =>
      RegExp('[\u09E6-\u09EF]').hasMatch(text);

  /// `(১)`, `(১ ও ২)`, `(১, ২ ও ৩)` — the way a book writes a list of numbers.
  static String _joinStemNumbers(List<int> numbers, {required bool bengali}) {
    const bengaliDigits = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
    String show(int number) => bengali
        ? '$number'
            .split('')
            .map((d) => bengaliDigits[int.parse(d)])
            .join()
        : '$number';

    if (numbers.length == 1) return show(numbers.first);
    final head = numbers.take(numbers.length - 1).map(show).join(', ');
    return bengali ? '$head ও ${show(numbers.last)}' : '$head and ${show(numbers.last)}';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 1. Plain Text Format
  // ─────────────────────────────────────────────────────────────────────────

  static String generatePlainText({
    required String schoolName,
    required String examName,
    required String subject,
    required String className,
    required String time,
    required String totalMarks,
    required List<HighSchoolQuestion> questions,
    StemImageSize imageSize = StemImageSize.medium,
    List<String> setLabels = const [],
    List<PaperSection> sectionOrder = PaperSection.defaultOrder,
  }) {
    final buffer = StringBuffer();
    final labels = _setLabelsOf(setLabels);
    final sections = [
      for (final s in _orderedSections(sectionOrder))
        if (questions.any((q) => _sectionOf(q) == s)) s,
    ];

    // A two-set paper is two papers in one file, each carrying only its own
    // questions; a question the reader never filed rides in both. The PDF and
    // the HTML sheet read a paper the same way.
    final sets = labels.isEmpty ? 1 : labels.length;
    for (var s = 0; s < sets; s++) {
      if (s > 0) {
        buffer.writeln();
        buffer.writeln('=' * 50);
        buffer.writeln();
      }
      _writePlainTextSet(
        buffer,
        schoolName: schoolName,
        examName: examName,
        subject: subject,
        className: className,
        time: time,
        totalMarks: totalMarks,
        setLabel: labels.isEmpty ? '' : labels[s],
        questions: questionsForSet(questions, labels, s),
        sections: sections,
        imageSize: imageSize,
      );
    }
    return buffer.toString();
  }

  /// One set of the plain-text paper: its masthead, then every block in the
  /// reader's order, under the letter its position gives it.
  static void _writePlainTextSet(
    StringBuffer buffer, {
    required String schoolName,
    required String examName,
    required String subject,
    required String className,
    required String time,
    required String totalMarks,
    required String setLabel,
    required List<HighSchoolQuestion> questions,
    required List<PaperSection> sections,
    required StemImageSize imageSize,
  }) {
    final divider = '=' * 50;
    final thinDivider = '-' * 50;

    buffer.writeln(divider);
    if (schoolName.trim().isNotEmpty) {
      buffer.writeln(schoolName.trim());
    }
    if (examName.trim().isNotEmpty) {
      buffer.writeln(examName.trim());
    }
    buffer.writeln(divider);

    final metaLine1 = <String>[];
    if (setLabel.isNotEmpty) metaLine1.add('সেট: $setLabel');
    if (subject.trim().isNotEmpty) metaLine1.add('বিষয়: $subject');
    if (className.trim().isNotEmpty) metaLine1.add('শ্রেণি: $className');
    if (metaLine1.isNotEmpty) buffer.writeln(metaLine1.join('  |  '));

    final metaLine2 = <String>[];
    if (time.trim().isNotEmpty) metaLine2.add('সময়: $time');
    if (totalMarks.trim().isNotEmpty) metaLine2.add('পূর্ণমান: $totalMarks');
    if (metaLine2.isNotEmpty) buffer.writeln(metaLine2.join('  |  '));
    buffer.writeln(thinDivider);
    buffer.writeln();

    var printed = 0;
    // A sheet with one type of question has nothing to tell apart; its lone
    // declaration is dropped. See [_declaresSections].
    final declares = _declaresSections(questions);
    for (var i = 0; i < sections.length; i++) {
      final kind = sections[i];
      final inSection = questions.where((q) => _sectionOf(q) == kind).toList();
      // A block that came up empty in this set is skipped; the blocks that do
      // print keep the letters their positions give them.
      if (inSection.isEmpty) continue;

      if (printed > 0) buffer.writeln(thinDivider);
      printed++;

      if (declares) buffer.writeln('【 ${_sectionHeading(kind, i)} 】');
      switch (kind) {
        case PaperSection.cq:
          buffer
              .writeln('[নিচের উদ্দীপকগুলো পড়ে সংশ্লিষ্ট প্রশ্নের উত্তর দাও]');
          buffer.writeln();
          for (int j = 0; j < inSection.length; j++) {
            final q = inSection[j];
            buffer.writeln(
                '${j + 1}. ${latexToPlainText(q.paperStemText.trim())}');
            if (_hasStemImage(q, imageSize)) {
              // Plain text cannot embed an image, so surface the link.
              buffer.writeln('   [চিত্র: ${_stemImageUrlOf(q)}]');
            }
            for (final sq in q.cqSubQuestions) {
              final markStr = sq.mark > 0 ? ' [${sq.mark}]' : '';
              buffer.writeln('   (${sq.label}) ${sq.text}$markStr');
            }
            buffer.writeln();
          }
          break;

        case PaperSection.mcq:
          buffer.writeln('[সঠিক উত্তরের পাশে টিক (✓) চিহ্ন দাও]');
          buffer.writeln();
          const bengaliLetters = ['ক', 'খ', 'গ', 'ঘ'];
          HighSchoolQuestion? previousMcq;
          for (int j = 0; j < inSection.length; j++) {
            final q = inSection[j];
            final mcq = q.mcqData;
            if (mcq == null) continue;
            // A shared উদ্দীপক is written once, over the first question of the
            // group, in every export format alike.
            if (q.opensMcqStemGroup(previousMcq)) {
              buffer.writeln(
                  stemWithNumbers(q.mcqStemText, mcqStemRunNumbers(inSection, j)));
              buffer.writeln();
            }
            previousMcq = q;
            buffer.writeln('${j + 1}. ${q.paperQuestionText}');
            final options = mcq.options;
            for (int optIdx = 0; optIdx < options.length; optIdx++) {
              final letter = optIdx < bengaliLetters.length
                  ? bengaliLetters[optIdx]
                  : '${optIdx + 1}';
              buffer.writeln('   ($letter) ${options[optIdx]}');
            }
            buffer.writeln();
          }
          break;

        case PaperSection.rq:
          buffer.writeln();
          for (int j = 0; j < inSection.length; j++) {
            final data = inSection[j].shortData;
            if (data == null || data.text.trim().isEmpty) continue;
            final markStr = data.mark > 0 ? ' [${data.mark}]' : '';
            buffer.writeln('${j + 1}. ${data.text.trim()}$markStr');
          }
          buffer.writeln();
          break;
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 2. Microsoft Word Document (.doc via Word-HTML format)
  // ─────────────────────────────────────────────────────────────────────────

  static String generateWordDoc({
    required String schoolName,
    required String examName,
    required String subject,
    required String className,
    required String time,
    required String totalMarks,
    required List<HighSchoolQuestion> questions,
    Map<String, Uint8List>? imageBytes,
    StemImageSize imageSize = StemImageSize.medium,
    List<String> setLabels = const [],
    List<PaperSection> sectionOrder = PaperSection.defaultOrder,
    QuestionLayout cqLayout = QuestionLayout.single,
    QuestionLayout mcqLayout = QuestionLayout.doubleColumn,
    QuestionLayout rqLayout = QuestionLayout.single,

    /// The face the document is set in, as in the HTML sheet; see [PaperFont].
    PaperFont font = PaperFont.hindSiliguri,
  }) {
    final labels = _setLabelsOf(setLabels);

    final buffer = StringBuffer();
    buffer.write('''
<html xmlns:o='urn:schemas-microsoft-com:office:office'
      xmlns:w='urn:schemas-microsoft-com:office:word'
      xmlns='http://www.w3.org/TR/REC-html40'>
<head>
  <meta charset='utf-8'>
  <title>${_escapeXml(examName.isEmpty ? 'Question Paper' : examName)}</title>
  <!--[if gte mso 9]>
  <xml>
    <w:WordDocument>
      <w:View>Print</w:View>
      <w:Zoom>100</w:Zoom>
      <w:DoNotOptimizeForBrowser/>
    </w:WordDocument>
  </xml>
  <![endif]-->
  <style>
    @page Section1 {
      size: 595.45pt 841.9pt; /* A4 */
      margin: 1.0in 0.8in 1.0in 0.8in;
      mso-header-margin: 36.0pt;
      mso-footer-margin: 36.0pt;
      mso-paper-source: 0;
    }
    div.Section1 { page: Section1; }
    body {
      font-family: ${font.wordStack};
      font-size: 11pt;
      line-height: 1.45;
      color: #000000;
    }
    .header-table {
      width: 100%;
      border-collapse: collapse;
      margin-bottom: 8pt;
      border-bottom: 2pt solid #000000;
      padding-bottom: 6pt;
    }
    .school-title {
      font-size: 18pt;
      font-weight: bold;
      text-align: center;
      margin: 0 0 4pt 0;
    }
    .exam-title {
      font-size: 14pt;
      font-weight: bold;
      text-align: center;
      margin: 0 0 6pt 0;
    }
    .meta-row {
      font-size: 11pt;
      font-weight: bold;
    }
    .section-title {
      font-size: 13pt;
      font-weight: bold;
      text-align: center;
      background-color: #f0f0f0;
      padding: 4pt;
      margin: 12pt 0 8pt 0;
      border: 1pt solid #cccccc;
    }
    .cq-box {
      margin-bottom: 12pt;
      page-break-inside: avoid;
    }
    .cq-stem {
      font-size: 11pt;
      margin-bottom: 4pt;
    }
    .cq-stem-img {
      max-width: 420pt;
      max-height: 320pt;
      margin: 4pt 0 6pt 0;
      display: block;
    }
    .cq-sub-table {
      width: 100%;
      border-collapse: collapse;
      margin-left: 12pt;
    }
    .cq-sub-label {
      width: 25pt;
      font-weight: bold;
      vertical-align: top;
    }
    .cq-sub-text {
      vertical-align: top;
    }
    .cq-sub-mark {
      width: 40pt;
      text-align: right;
      font-weight: bold;
      vertical-align: top;
    }
    .mcq-container {
      margin-bottom: 8pt;
      page-break-inside: avoid;
    }
    .mcq-layout-table {
      width: 100%;
      border-collapse: collapse;
      table-layout: fixed;
    }
    .cq-col-cell {
      width: ${cqLayout.isDouble ? '50%' : '100%'};
      vertical-align: top;
      padding: 0pt 4pt 8pt 0pt;
    }
    .mcq-col-cell {
      width: ${mcqLayout.isDouble ? '50%' : '100%'};
      vertical-align: top;
      padding: 0pt 4pt 8pt 0pt;
    }
    .mcq-question {
      font-weight: 500;
      margin-bottom: 3pt;
    }
    /* An MCQ's shared intro: printed once, over the first question of the group
       that carries it, and never numbered. */
    .mcq-stem {
      font-size: 11pt;
      margin-bottom: 4pt;
    }
    .mcq-options-table {
      width: 100%;
      border-collapse: collapse;
      margin-left: 10pt;
    }
    .mcq-opt-cell {
      width: 50%;
      padding: 2pt 4pt;
      vertical-align: top;
    }
    .rq-col-cell {
      width: ${rqLayout.isDouble ? '50%' : '100%'};
      vertical-align: top;
      padding: 0pt 4pt 0pt 0pt;
    }
    .rq-item {
      display: flex;
      justify-content: space-between;
      gap: 12pt;
      margin-bottom: 6pt;
      font-size: 11pt;
      page-break-inside: avoid;
    }
    .rq-mark {
      font-weight: bold;
      white-space: nowrap;
    }
    .frac { display:inline-block; vertical-align:middle; text-align:center; margin:0 .15em; line-height:1.05; }
    .frac-num { display:block; padding:0 .25em; border-bottom:1px solid #000; }
    .frac-den { display:block; padding:0 .25em; }
    .mathv { font-style:italic; }
    /* One face for maths symbols: the text faces cover ∩ but not ∪, which
       used to leave the union drawn by a different face than the intersection. */
    .m { font-family: $kMathFontStack; font-style: normal; }
  </style>
</head>
<body>
<div class="Section1">
''');

    // The blocks the paper has, in the reader's order. Read off every question,
    // so a block that is empty in one set keeps its letter in the other — the
    // PDF and the HTML sheet read a paper the same way.
    final sections = [
      for (final s in _orderedSections(sectionOrder))
        if (questions.any((q) => _sectionOf(q) == s)) s,
    ];

    // Two sets are two papers in one document, each starting on a page of its
    // own — the same pair the PDF prints.
    final sets = labels.isEmpty ? 1 : labels.length;
    for (var s = 0; s < sets; s++) {
      if (s > 0) {
        buffer.write('''
  <br clear=all style='mso-special-character:line-break;page-break-before:always'>
''');
      }
      _writeWordSet(
        buffer,
        schoolName: schoolName,
        examName: examName,
        subject: subject,
        className: className,
        time: time,
        totalMarks: totalMarks,
        setLabel: labels.isEmpty ? '' : labels[s],
        questions: questionsForSet(questions, labels, s),
        sections: sections,
        imageBytes: imageBytes,
        imageSize: imageSize,
        cqLayout: cqLayout,
        mcqLayout: mcqLayout,
        rqLayout: rqLayout,
      );
    }

    buffer.write('''
</div>
</body>
</html>
''');
    return buffer.toString();
  }

  /// One set of the Word paper: its masthead, then every block in the reader's
  /// order, under the letter its position gives it.
  static void _writeWordSet(
    StringBuffer buffer, {
    required String schoolName,
    required String examName,
    required String subject,
    required String className,
    required String time,
    required String totalMarks,
    required String setLabel,
    required List<HighSchoolQuestion> questions,
    required List<PaperSection> sections,
    required Map<String, Uint8List>? imageBytes,
    required StemImageSize imageSize,
    required QuestionLayout cqLayout,
    required QuestionLayout mcqLayout,
    required QuestionLayout rqLayout,
  }) {
    buffer.write('''
  <div class="header-table">
    ${schoolName.trim().isNotEmpty ? '<div class="school-title">${_escapeXml(schoolName)}</div>' : ''}
    ${examName.trim().isNotEmpty ? '<div class="exam-title">${_escapeXml(examName)}</div>' : ''}
    <table style="width:100%; border:none; margin-top:4pt;">
      <tr class="meta-row">
        <td style="text-align:left;">${setLabel.isNotEmpty ? 'সেট: ${_escapeXml(setLabel)} | ' : ''}বিষয়: ${_escapeXml(subject)}</td>
        <td style="text-align:center;">শ্রেণি: ${_escapeXml(className)}</td>
        <td style="text-align:right;">সময়: ${_escapeXml(time)} | পূর্ণমান: ${_escapeXml(totalMarks)}</td>
      </tr>
    </table>
  </div>
''');

    for (var i = 0; i < sections.length; i++) {
      final kind = sections[i];
      final inSection = questions.where((q) => _sectionOf(q) == kind).toList();
      // A block that came up empty in this set is skipped; the blocks that do
      // print keep the letters their positions give them.
      if (inSection.isEmpty) continue;

      final heading =
          _declaresSections(questions) ? _sectionHeading(kind, i) : '';
      switch (kind) {
        case PaperSection.cq:
          _writeWordCqSection(
              buffer, inSection, heading, cqLayout, imageBytes, imageSize);
          break;
        case PaperSection.mcq:
          _writeWordMcqSection(
              buffer, inSection, heading, mcqLayout, imageBytes, imageSize);
          break;
        case PaperSection.rq:
          _writeWordRqSection(buffer, inSection, heading, rqLayout);
          break;
      }
    }
  }

  /// A Word block's declaration bar — or, when the sheet holds one type of
  /// question, the air the bar took.
  ///
  /// A bare `<div>` with a margin collapses away in Word, so the stand-in is a
  /// line of its own: hair-thin, empty, and carrying the bar's top margin.
  static String _wordSectionTitle(String heading) => heading.isEmpty
      ? '<div style="font-size:1pt; line-height:1pt; margin-top:12pt;">&nbsp;</div>'
      : '<div class="section-title">${_escapeXml(heading)}</div>';

  /// The CQ block of a Word paper.
  ///
  /// A real table keeps columns stable in Word/WPS, which CSS does not.
  static void _writeWordCqSection(
    StringBuffer buffer,
    List<HighSchoolQuestion> cqs,
    String heading,
    QuestionLayout layout,
    Map<String, Uint8List>? imageBytes,
    StemImageSize imageSize,
  ) {
    buffer.write('''
  ${_wordSectionTitle(heading)}
  <div style="font-size:10pt; font-style:italic; margin-bottom:8pt; text-align:center;">[যেকোনো নির্ধারিত সংখ্যক প্রশ্নের উত্তর দাও]</div>
''');

    buffer.write('''
  <table class="mcq-layout-table" width="100%" cellspacing="0" cellpadding="0">
''');
    final cqCols = layout.mcqColumns;
    for (int i = 0; i < cqs.length; i += cqCols) {
      final cells = StringBuffer();
      for (int c = 0; c < cqCols; c++) {
        if (c > 0) cells.write('<td class="mcq-col-gap" width="16"></td>');
        final idx = i + c;
        if (idx >= cqs.length) {
          cells.write('<td class="mcq-col-cell"></td>');
          continue;
        }
        final q = cqs[idx];
        final index = idx + 1;
        cells.write('''
    <td class="cq-col-cell">
      <div class="cq-box">
        <div class="cq-stem">
          <b>$index.</b> ${_htmlText(q.paperStemText, latex: true)}
        </div>
        ${_stemImageMarkup(q, bytes: imageBytes, size: imageSize, usePoints: true)}
        <table class="cq-sub-table">''');
        for (final sq in q.cqSubQuestions) {
          cells.write('''
          <tr>
            <td class="cq-sub-label">(${_escapeXml(sq.label)})</td>
            <td class="cq-sub-text">${_htmlText(sq.text, latex: true)}</td>
            <td class="cq-sub-mark">${sq.mark > 0 ? '[${sq.mark}]' : ''}</td>
          </tr>''');
        }
        cells.write('''
        </table>
      </div>
    </td>''');
      }
      buffer.write('''
    <tr>$cells
    </tr>
''');
    }
    buffer.write('''
  </table>
''');
  }

  /// The MCQ block of a Word paper, options in two columns inside each cell.
  ///
  /// A shared উদ্দীপক prints once, over the first question of its group, exactly
  /// as the HTML and the PDF do it.
  static void _writeWordMcqSection(
    StringBuffer buffer,
    List<HighSchoolQuestion> mcqs,
    String heading,
    QuestionLayout layout,
    Map<String, Uint8List>? imageBytes,
    StemImageSize imageSize,
  ) {
    buffer.write('''
  ${_wordSectionTitle(heading)}
  <div style="font-size:10pt; font-style:italic; margin-bottom:8pt; text-align:center;">[সঠিক উত্তরের পাশে টিক (✓) চিহ্ন দাও]</div>
''');

    const bengaliLetters = ['ক', 'খ', 'গ', 'ঘ'];

    // Options for one question, as an HTML fragment.
    String optionsHtml(List<String> options) {
      final b = StringBuffer();
      for (int opt = 0; opt < options.length; opt += 2) {
        final l1 =
            opt < bengaliLetters.length ? bengaliLetters[opt] : '${opt + 1}';
        final has2 = opt + 1 < options.length;
        final l2 = has2 && (opt + 1) < bengaliLetters.length
            ? bengaliLetters[opt + 1]
            : '${opt + 2}';
        final o2 = has2 ? options[opt + 1] : '';
        b.write('''
      <tr>
        <td class="mcq-opt-cell">($l1) ${_htmlText(options[opt])}</td>
        <td class="mcq-opt-cell">${has2 ? '($l2) ${_htmlText(o2)}' : ''}</td>
      </tr>''');
      }
      return b.toString();
    }

    // One question as a full cell.
    HighSchoolQuestion? previous;
    String questionCell(int index, HighSchoolQuestion q) {
      final mcq = q.mcqData;
      if (mcq == null) return '<td class="mcq-col-cell"></td>';
      // The last question actually printed decides whether this one has already
      // had its intro.
      final opensStem = q.opensMcqStemGroup(previous);
      previous = q;
      return '''
    <td class="mcq-col-cell">
      ${opensStem ? '<div class="mcq-stem">${_htmlText(stemWithNumbers(q.mcqStemText, mcqStemRunNumbers(mcqs, index - 1)), latex: true)}${_stemImageMarkup(q, bytes: imageBytes, size: imageSize, usePoints: true)}</div>' : ''}
      <div class="mcq-question"><b>$index.</b> ${_htmlText(q.paperQuestionText)}</div>
      <table class="mcq-options-table">${optionsHtml(mcq.options)}</table>
    </td>''';
    }

    // A real table keeps the columns stable in Word/WPS, which a CSS grid
    // does not reliably survive.
    buffer.write('''
  <table class="mcq-layout-table" width="100%" cellspacing="0" cellpadding="0">
''');
    final cols = layout.mcqColumns;
    for (int i = 0; i < mcqs.length; i += cols) {
      final cells = StringBuffer();
      for (int c = 0; c < cols; c++) {
        final idx = i + c;
        if (c > 0) cells.write('<td class="mcq-col-gap" width="16"></td>');
        cells.write(idx < mcqs.length
            ? questionCell(idx + 1, mcqs[idx])
            : '<td class="mcq-col-cell"></td>');
      }
      buffer.write('''
    <tr>$cells
    </tr>
''');
    }
    buffer.write('''
  </table>
''');
  }

  /// The short-question block of a Word paper.
  ///
  /// Laid out as a table so Word keeps the fixed 50/50 split that its CQ and
  /// MCQ blocks use.
  static void _writeWordRqSection(
    StringBuffer buffer,
    List<HighSchoolQuestion> shorts,
    String heading,
    QuestionLayout layout,
  ) {
    buffer.write('''
  ${_wordSectionTitle(heading)}
  <div style="font-size:10pt; font-style:italic; margin-bottom:8pt; text-align:center;">[সংক্ষেপে উত্তর দাও]</div>
''');

    String rqCell(int index) {
      final data = shorts[index].shortData;
      if (data == null || data.text.trim().isEmpty) return '';
      return '''
    <div class="rq-item">
      <span>${index + 1}. ${_htmlText(data.text)}</span>
      <span class="rq-mark">[${data.mark}]</span>
    </div>''';
    }

    final rqCols = layout.mcqColumns;
    if (rqCols > 1) {
      buffer.write('''
  <table class="mcq-layout-table" width="100%" cellspacing="0" cellpadding="0">
''');
      for (int i = 0; i < shorts.length; i += rqCols) {
        buffer.write('  <tr>');
        for (int c = 0; c < rqCols; c++) {
          if (c > 0) buffer.write('<td class="mcq-col-gap" width="16"></td>');
          final idx = i + c;
          buffer.write(idx < shorts.length
              ? '    <td class="rq-col-cell">${rqCell(idx)}</td>'
              : '    <td class="rq-col-cell"></td>');
        }
        buffer.write('  </tr>\n');
      }
      buffer.write('  </table>\n');
    } else {
      for (int i = 0; i < shorts.length; i++) {
        final cell = rqCell(i);
        if (cell.isNotEmpty) buffer.write('$cell\n');
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 3. Web / HTML Format (Print-optimized, responsive)
  // ─────────────────────────────────────────────────────────────────────────

  /// A font size for the sheet's CSS: the tuned pixel size plus the paper's
  /// font step, in points.
  ///
  /// Points rather than pixels because the step has to match the PDF, which
  /// moves its own sizes by one point per step; `calc()` mixes the two units so
  /// the sheet and the PDF grow by the same amount. At step 0 the plain pixel
  /// value comes out, so an untouched paper's CSS is exactly what it was.
  static String _cssFontSize(double basePx, double fontStep) {
    if (fontStep == 0) return '${_cssNumber(basePx)}px';
    // Written as a subtraction rather than an added negative: `calc(15px + -2pt)`
    // is well-formed but reads like a mistake.
    final sign = fontStep > 0 ? '+' : '-';
    return 'calc(${_cssNumber(basePx)}px $sign ${_cssNumber(fontStep.abs())}pt)';
  }

  /// A number for the CSS, with no trailing `.0`.
  static String _cssNumber(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();

  static String generateHtml({
    required String schoolName,
    required String examName,
    required String subject,
    required String className,
    required String time,
    required String totalMarks,
    required List<HighSchoolQuestion> questions,
    List<String> setLabels = const [],
    List<PaperSection> sectionOrder = PaperSection.defaultOrder,
    StemImageSize imageSize = StemImageSize.medium,
    QuestionLayout cqLayout = QuestionLayout.single,
    QuestionLayout mcqLayout = QuestionLayout.doubleColumn,
    QuestionLayout rqLayout = QuestionLayout.single,
    double fontStep = 0,

    /// The face the sheet is set in. Fetched from Google Fonts when it is a web
    /// font, and fallen back on when it is not; see [PaperFont].
    PaperFont font = PaperFont.hindSiliguri,

    /// Lay the sheet out for a desktop-width window instead of the device's own
    /// width. The live preview asks for this; see [desktopViewport] below.
    bool desktopMode = false,
  }) {
    // A two-set paper prints as two papers in one file. A question belongs to a
    // set through [HighSchoolQuestion.setLabel], and a question the reader never
    // filed into a set belongs to both — dropping it would silently lose a
    // question from the paper.
    final labels = _setLabelsOf(setLabels);
    final sets = <List<HighSchoolQuestion>>[
      for (var i = 0; i < (labels.isEmpty ? 1 : labels.length); i++)
        questionsForSet(questions, labels, i),
    ];

    // The blocks the paper actually has, in the order the reader arranged them.
    // Read off every question rather than one set, so a block that happens to be
    // empty in one set keeps its letter in the other — the PDF does the same.
    final ordered = _orderedSections(sectionOrder);
    final sections = [
      for (final s in ordered)
        if (questions.any((q) => _sectionOf(q) == s)) s,
    ];

    // Which blocks are laid out in two columns, and whether CQ and the short
    // questions share one continuous flow. The PDF merges the two the same way:
    // they are packed together only while they sit next to each other and both
    // are two-column. MCQ never joins the flow — its options lay out
    // differently, and it wants a fresh pair of columns.
    final twoColumnBlocks = <PaperSection>{
      if (cqLayout.isDouble) PaperSection.cq,
      if (rqLayout.isDouble) PaperSection.rq,
      if (mcqLayout.isDouble) PaperSection.mcq,
    };
    final mergeCqAndShort = cqLayout.isDouble && rqLayout.isDouble;

    // The live preview renders this same file in a phone-width WebView, where
    // `width=device-width` reflows the A4 sheet into a narrow column that is
    // nothing like the page that prints. Naming the sheet's own width instead —
    // 210mm, about 794px, plus the page's 24px of side padding — makes the
    // WebView lay the sheet out at its real size and scale the whole page down
    // to fit the screen. The exported file keeps the device width.
    const desktopViewport = 'width=900';

    // The faces the sheet fetches: the chosen one, when the browser cannot be
    // expected to have it, and Hind Siliguri, which every stack falls back to.
    final fontQuery = [
      for (final family in PaperFont.webFamiliesOf(font)) 'family=$family',
    ].join('&');

    final buffer = StringBuffer();
    buffer.write('''
<!DOCTYPE html>
<html lang="bn">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="${desktopMode ? desktopViewport : 'width=device-width, initial-scale=1.0'}">
  <title>${_escapeXml(examName.isEmpty ? 'Question Paper' : examName)} - Pi-QBank</title>
  <link href="https://fonts.googleapis.com/css2?$fontQuery&display=swap" rel="stylesheet">
  <style>
    :root {
      --primary: #4f46e5;
      /* The PDF writes its text in pure black; the page should look the same. */
      --text: #000000;
      /* Marks and source tags: secondary text, a touch grey. */
      --muted: #64748b;
      --border: #cbd5e1;
      --bg: #f8fafc;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: ${font.cssStack};
      background: var(--bg);
      color: var(--text);
      line-height: 1.6;
      padding: 24px;
    }
    .no-print-toolbar {
      max-width: 210mm;
      margin: 0 auto 20px auto;
      display: flex;
      justify-content: space-between;
      align-items: center;
      background: white;
      padding: 14px 20px;
      border-radius: 12px;
      box-shadow: 0 4px 12px rgba(0,0,0,0.06);
    }
    .btn {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 10px 18px;
      font-size: 14px;
      font-weight: 600;
      border-radius: 8px;
      border: none;
      cursor: pointer;
      text-decoration: none;
      transition: all 0.2s;
    }
    .btn-primary { background: var(--primary); color: white; }
    .btn-primary:hover { background: #4338ca; }
    .btn-outline { background: white; border: 1px solid #cbd5e1; color: var(--text); }
    .btn-outline:hover { background: #f1f5f9; }

    /* Live edit turns the sheet itself into the editor, so a typo is fixed where
       it is seen. The cues for it are screen-only: an outline marks the sheet
       and the field being typed in, and neither belongs on paper. */
    @media screen {
      [contenteditable="true"] {
        outline: 2px dashed #c7d2fe;
        outline-offset: 4px;
        cursor: text;
      }
      [contenteditable="true"] :focus {
        outline: 1px solid #a5b4fc;
        background: #eef2ff;
      }
    }
    .edit-hint { font-size: 12px; color: var(--muted); }
    .edit-hint[hidden] { display: none; }

    /* The sheet *is* an A4 page: the same 210×297mm canvas the PDF export uses,
       the same 18pt at the head and 40pt down each side, and a foot of 18px.
       Same paper, same text width, so a line that wraps here wraps the same way
       in the PDF: the canvas on screen is what the printer produces. */
    .paper-sheet {
      width: 210mm;
      max-width: 100%;
      min-height: 297mm;
      margin: 0 auto;
      background: white;
      padding: 18pt 28pt 18px;
      border-radius: 8px;
      box-shadow: 0 4px 24px rgba(0,0,0,0.08);
      /* The paper's base size, set where the PDF sets its body style. Text with
         no size of its own — an MCQ stem, for one — has to move with the
         font-size control too, and 16px is what it inherited before. */
      font-size: ${_cssFontSize(16, fontStep)};
    }
    /* A second sheet exists only when the two sets do not fit on one page: the
       script at the foot of the file splits them when that is the case, and on
       paper the split becomes a page break. */
    .paper-sheet + .paper-sheet { margin-top: 24px; }
    /* One set. Sets share the sheet while the pair fits on a page. */
    .set-head {
      break-inside: avoid;
      break-after: avoid;
    }
    /* The dashed rule the PDF draws between two sets that share a sheet, with
       the same gaps above and below it. */
    .set-divider {
      border-top: 1px dashed var(--border);
      margin: 16pt 0 12pt 0;
      break-after: avoid;
    }
    .school-title { font-size: ${_cssFontSize(24, fontStep)}; font-weight: 700; text-align: center; margin-bottom: 4px; }
    .exam-title { font-size: ${_cssFontSize(18, fontStep)}; font-weight: 600; text-align: center; }
    .meta-bar {
      display: flex;
      justify-content: space-between;
      flex-wrap: wrap;
      padding: 2px 0;
      border-top: 1.5px solid var(--text);
      border-bottom: 1.5px solid var(--text);
      font-weight: 600;
      font-size: ${_cssFontSize(15, fontStep)};
    }
    /* The PDF's own spacing, in the PDF's own units: `PdfLayout.sectionGap`
       above every banner and `PdfLayout.sectionBannerGap` below it. The same
       two numbers the page charges its widget tree, so the band under the
       masthead is no wider here than the gap before any other section, and the
       three sections sit the same distance apart in both exports. */
    .section-banner {
      text-align: center;
      font-size: ${_cssFontSize(14, fontStep)};
      font-weight: 700;
      background: #f1f5f9;
      padding: 3px 6px;
      border-radius: 6px;
      margin: 5pt 0 10pt 0;
      border: 1px solid #e2e8f0;
    }
    /* The same bar inside a two-column block: it opens the first column instead
       of spanning the page, so the declaration is one column wide like the
       questions under it. Its top margin goes: a margin on the first child of
       the flow would push the declaration's column down and leave the right
       column's first question sitting higher than the heading beside it. The
       gap above the block moves out to the column container instead, which both
       columns share and which therefore starts them level. `break-after` keeps
       the bar from being stranded at the foot of a column with its questions
       overleaf. */
    .section-banner.in-flow {
      margin: 0 0 6px 0;
      break-after: avoid;
    }
    /* A block with no declaration to print — the sheet holds one type of
       question — keeps the air the bar's top margin gave it and nothing else.
       The same 5pt as the bar's own `margin` above. See the writers'
       `_declaresSections`. */
    .section-gap {
      height: 5pt;
    }
    /* No frame around a question. The two sides are divided by one vertical
       line down the gutter — set on the flow containers with `column-rule` —
       instead of every question carrying a box of its own, which is what made
       the two columns read as two stacks of cards.
       And no `break-inside: avoid` either: keeping every question whole is what
       left the columns lopsided, since a card too tall for the space it had
       left jumped to the next column and stranded the rest of the one before
       it. Letting a question break — as the PDF does, where it repeats the
       number on the continuation — is what lets the two sides finish level.
       `widows`/`orphans` keep a split from leaving one line behind. */
    .cq-card {
      margin-bottom: 10px;
      orphans: 2;
      widows: 2;
    }
    .cq-stem { font-size: ${_cssFontSize(15, fontStep)}; margin-bottom: 5px; }
    .cq-stem-img {
      display: block;
      max-width: 100%;
      max-height: 340px;
      margin: 0 auto 12px auto;
      object-fit: contain;
    }
    /* A sub-question row under its stem: just a small indent and the mark on
       the right. No margin of its own — the line boxes are the whole of the
       spacing, so the run sits tight. */
    .cq-sub-item {
      display: flex;
      justify-content: space-between;
      font-size: ${_cssFontSize(14, fontStep)};
      padding-left: 6px;
    }
    .cq-mark {
      font-weight: 400;
      min-width: 20px;
      text-align: right;
      color: var(--muted);
    }
    /* Two-column sections flow like a newspaper: a question keeps the height it
       needs and the next one continues below it in the same column. A grid
       would instead stretch every pair in a row to the taller of the two, so a
       one-line question beside a diagram sat in a card half full of white. */
    .cq-grid {${cqLayout.isDouble ? '\n      margin-top: 5pt;\n      column-count: 2;\n      column-gap: 22px;\n      column-rule: 1px solid var(--border);' : ''}
    }
    /* A merged CQ + short-question run: one continuous pair of columns, so the
       short questions begin exactly where the creative questions run out —
       mid-column or at the head of the next one. The gap above the run sits on
       the container, not on the heading inside it, so both columns start level. */
    .flow-grid {${mergeCqAndShort ? '\n      margin-top: 5pt;\n      column-count: 2;\n      column-gap: 22px;\n      column-rule: 1px solid var(--border);' : ''}
    }
    .mcq-grid {${mcqLayout.isDouble ? '\n      margin-top: 5pt;\n      column-count: 2;\n      column-gap: 22px;\n      column-rule: 1px solid var(--border);' : ''}
    }
    /* The card is the question and nothing else: no padding, no margin of its
       own and no rule under it. */
    .mcq-card {
      orphans: 2;
      widows: 2;
    }
    /* The question and its options are one block of text, set at one size: the
       PDF draws both from the same style, and an option smaller than the
       question it belongs to reads as a footnote to it. */
    .mcq-question { font-size: ${_cssFontSize(15, fontStep)}; }
    /* The intro an MCQ shares with the question below it — printed once, at the
       head of the first question of the group, and never numbered. */
    .mcq-stem {
      font-size: ${_cssFontSize(15, fontStep)};
      margin-bottom: 4px;
    }
    /* The intro and its figure ride with the question they introduce, exactly as
       they do in the PDF: an intro left at the foot of a column while its
       question starts the next one reads as belonging to whatever is beside it.
       The options stay free to break — that is what keeps the two columns
       level. */
    .mcq-head { break-inside: avoid; }
    .mcq-options {
      display: grid;
      /* The script below measures the options and gives them four to a line, two
         or one, whichever the room allows — in a narrow column just as in a
         full-width block. This is what prints if the file is opened with scripts
         turned off: two per row where there is a page's width, one per row where
         the block sits inside a half-page column. */
      grid-template-columns: ${mcqLayout.isDouble ? '1fr' : '1fr 1fr'};
      /* No gap between the rows of options, so they sit as one tight stack
         under their question. The columns keep a small gutter, 6px, and the
         indent under the question number is 8px. Both are read back by the
         fitting script, which measures the room with `paddingLeft` and the
         gutter with `columnGap`, so they may be changed here alone. */
      gap: 0 6px;
      padding-left: 6px;
      font-size: ${_cssFontSize(15, fontStep)};
    }
    .rq-grid {${rqLayout.isDouble ? '\n      margin-top: 5pt;\n      column-count: 2;\n      column-gap: 22px;\n      column-rule: 1px solid var(--border);' : ''}
    }
    /* Short questions are a single line each, as in the PDF: no padding and no
       gap of their own — the line box is the whole of the row, and the mark is
       held at the right edge by the flex row. A one-line row stays whole:
       breaking inside it would gain nothing for the column balance and could cut
       a question in half. */
    .rq-item {
      display: flex;
      justify-content: space-between;
      align-items: baseline;
      font-size: ${_cssFontSize(15, fontStep)};
      page-break-inside: avoid;
      break-inside: avoid;
    }
    .rq-mark { font-weight: 400; white-space: nowrap; color: var(--muted); }

    @page { size: A4; margin: 0; }

    @media print {
      body { background: white; padding: 0; }
      .no-print-toolbar { display: none !important; }
      /* No margin on the page box: the sheet carries the page's own margins, so
         a printed page breaks where the exported PDF page breaks. */
      .paper-sheet {
        width: auto;
        max-width: none;
        min-height: 0;
        box-shadow: none;
        border-radius: 0;
        padding: 18pt 28pt 18px;
      }
      .paper-sheet + .paper-sheet { break-before: page; margin-top: 0; }
    }
    .frac { display:inline-block; vertical-align:middle; text-align:center; margin:0 .15em; line-height:1.05; }
    .frac-num { display:block; padding:0 .25em; border-bottom:1px solid #000; }
    .frac-den { display:block; padding:0 .25em; }
    .mathv { font-style:italic; }
    /* One face for maths symbols: the text faces cover ∩ but not ∪, which
       used to leave the union drawn by a different face than the intersection. */
    .m { font-family: $kMathFontStack; font-style: normal; }
  </style>
</head>
<body>
  <div class="no-print-toolbar">
    <div><b>Pi-QBank</b> প্রশ্নপত্র প্রিভিউ</div>
    <div style="display:flex; gap:10px; align-items:center;">
      <span class="edit-hint" id="editHint" hidden>যা লিখবেন সেটাই প্রিন্ট হবে</span>
      <button class="btn btn-outline" id="editBtn">✏️ লাইভ এডিট</button>
      <button class="btn btn-primary" onclick="window.print()">🖨️ প্রিন্ট / PDF সংরক্ষণ</button>
    </div>
  </div>

  <div class="paper-sheet">
''');

    // Every set goes on one sheet. Whether the sets stay together or get a sheet
    // each is decided by what actually fits, in the script at the foot of the
    // file — the page is A4 either way, so what fits on screen is what fits on
    // paper.
    for (var i = 0; i < sets.length; i++) {
      if (i > 0) {
        buffer.write('''
    <div class="set-divider"></div>
''');
      }
      _writeHtmlSet(
        buffer,
        schoolName: schoolName,
        examName: examName,
        subject: subject,
        className: className,
        time: time,
        totalMarks: totalMarks,
        setLabel: labels.isEmpty ? '' : labels[i],
        questions: sets[i],
        sections: sections,
        twoColumnBlocks: twoColumnBlocks,
        mergeCqAndShort: mergeCqAndShort,
        imageSize: imageSize,
      );
    }

    buffer.write('''
  </div>

  <script>
    /* Two sets share the sheet while the pair fits on a single A4 page; when it
       does not, the second set moves into a sheet of its own and the printer —
       which breaks between sheets — puts it on a page of its own. Measured
       rather than guessed: the sheet is A4 wide either way, so what fits here is
       what fits on paper. A pair that fits gets the page's leftover space put
       between the sets, so the second one reaches the foot of the page instead
       of leaving a band of white under it. */
    (function () {
      /* The MCQ options sit in a grid: all four on one line where the four of
         them fit, two lines of two where they do not, and one per line where
         even two will not sit side by side. Which of the three it is cannot be
         written in a stylesheet — it depends on how wide the options turn out
         to be — so the file measures them. This runs before the two-set
         decision, which measures the heights this choice decides. */
      function fitOptions() {
        var lists = document.querySelectorAll('.mcq-options[data-fit]');
        for (var i = 0; i < lists.length; i++) {
          var list = lists[i];
          var cells = Array.prototype.slice.call(list.children);
          // One option, or none: there is nothing to fit.
          if (cells.length < 2) continue;

          var style = getComputedStyle(list);
          var room = list.clientWidth - parseFloat(style.paddingLeft) -
              parseFloat(style.paddingRight);
          var gutter = parseFloat(style.columnGap) || 0;
          var wanted = cells.map(function (cell) {
            return wantedWidth(cell, style.fontSize);
          });

          var counts = [4, 2, 1];
          for (var c = 0; c < counts.length; c++) {
            var count = counts[c];
            if (count > wanted.length) continue;
            var cell = (room - (count - 1) * gutter) / count;
            var fits = wanted.every(function (width) {
              return width <= cell;
            });
            // A smaller count always gives every option more room, so one per
            // line always fits and the search ends there.
            if (fits) {
              list.style.gridTemplateColumns = 'repeat(' + count + ', 1fr)';
              break;
            }
          }
        }
      }

      /* How wide one option wants to be unwrapped: the same text, at the size
         the options print at, in a plain box out of the flow. */
      function wantedWidth(cell, fontSize) {
        var probe = document.createElement('span');
        probe.style.cssText = 'position:absolute;left:-10000px;top:0;' +
            'white-space:nowrap;visibility:hidden;margin:0;padding:0;' +
            'font-size:' + fontSize + ';';
        probe.textContent = cell.textContent;
        document.body.appendChild(probe);
        var width = probe.getBoundingClientRect().width;
        probe.parentNode.removeChild(probe);
        return width;
      }

      function decide() {
        var sheet = document.querySelector('.paper-sheet');
        if (!sheet) return;
        var sets = Array.prototype.slice.call(
            sheet.querySelectorAll(':scope > .paper-set'));
        if (sets.length < 2) return;

        var style = getComputedStyle(sheet);
        var padTop = parseFloat(style.paddingTop);
        var padBottom = parseFloat(style.paddingBottom);

        // A page's worth of room, from the page box itself rather than a
        // hard-coded number of pixels.
        var probe = document.createElement('div');
        probe.style.cssText =
            'position:absolute;visibility:hidden;width:0;height:297mm;';
        document.body.appendChild(probe);
        var room = probe.getBoundingClientRect().height - padTop - padBottom;
        probe.remove();

        var divider = sheet.querySelector(':scope > .set-divider');
        /* The slack a previous pass added goes back before anything is
           measured: the live editor runs this again after every edit, and slack
           measured on top of slack would grow with nothing to earn it. */
        if (divider) {
          divider.style.marginTop = '';
          divider.style.marginBottom = '';
        }

        // What the sets take right now — the rule between them and every margin
        // included. Measured with the page's own minimum height out of the way,
        // so a short pair reports its real height and not a full page.
        var minHeight = sheet.style.minHeight;
        sheet.style.minHeight = '0';
        var used = sheet.getBoundingClientRect().height - padTop - padBottom;
        sheet.style.minHeight = minHeight;

        if (used <= room) {
          if (divider) {
            // The leftover belongs between the sets: half above the rule and
            // half below, so it marks the middle of the separation and the
            // second set finishes level with the foot of the page.
            var slack = (room - used) / 2;
            var rule = getComputedStyle(divider);
            divider.style.marginTop =
                (parseFloat(rule.marginTop) + slack) + 'px';
            divider.style.marginBottom =
                (parseFloat(rule.marginBottom) + slack) + 'px';
          }
          return;
        }

        var anchor = sheet;
        for (var i = 1; i < sets.length; i++) {
          var next = document.createElement('div');
          next.className = 'paper-sheet';
          anchor.parentNode.insertBefore(next, anchor.nextSibling);
          next.appendChild(sets[i]);
          anchor = next;
        }
        if (divider) divider.remove();
      }

      /* ── Live edit ──────────────────────────────────────────────────────
         A typo noticed here should be fixed here. The button hands the sheet
         over to the reader: every text on it can be typed over in place, and
         what prints is what is left on the page. Nothing goes back to the
         .html file or to the app — the edit lives in this tab — so a paper
         worth keeping still comes from a fresh export. */
      function setEditing(on) {
        var sheets = document.querySelectorAll('.paper-sheet');
        for (var i = 0; i < sheets.length; i++) {
          if (on) {
            sheets[i].setAttribute('contenteditable', 'true');
            sheets[i].setAttribute('spellcheck', 'false');
          } else {
            sheets[i].removeAttribute('contenteditable');
            sheets[i].removeAttribute('spellcheck');
          }
        }
        document.body.classList.toggle('editing', on);
        var hint = document.getElementById('editHint');
        if (hint) hint.hidden = !on;
        var button = document.getElementById('editBtn');
        if (button) button.textContent = on ? '✅ এডিট শেষ' : '✏️ লাইভ এডিট';
      }

      function isEditing() {
        return document.body.classList.contains('editing');
      }

      var relayout = null;
      /* Typing can push a set past the foot of the page, so the measurement
         that laid the page out runs again — debounced, because it walks every
         option on the sheet. */
      function relayoutSoon() {
        clearTimeout(relayout);
        relayout = setTimeout(function () {
          fitOptions();
          decide();
          // A split makes a new sheet, and the new sheet has to be editable too.
          setEditing(isEditing());
        }, 260);
      }

      function wireEditor() {
        var button = document.getElementById('editBtn');
        if (button) {
          button.addEventListener('click', function () {
            setEditing(!isEditing());
          });
        }
        // One listener on the document rather than one per sheet: a split
        // makes a sheet that was not there when this ran, and the delegate does
        // not care which sheet the typing landed in.
        document.addEventListener('input', function (event) {
          var node = event.target;
          if (node && node.closest && node.closest('.paper-sheet')) relayoutSoon();
        });
        // Escape closes the editor the way it closes anything else.
        document.addEventListener('keydown', function (event) {
          if (event.key === 'Escape' && isEditing()) setEditing(false);
        });
      }

      function run() {
        // Fonts and images decide how wide a line is and how tall a set is, so
        // wait for both before measuring anything.
        if (document.fonts && document.fonts.ready) {
          document.fonts.ready.then(function () {
            fitOptions();
            decide();
          });
        } else {
          fitOptions();
          decide();
        }
      }

      wireEditor();
      if (document.readyState === 'complete') run();
      else window.addEventListener('load', run);
    })();
  </script>
</body>
</html>
''');
    return buffer.toString();
  }

  /// The block a question is printed in, or null when its type is none of the
  /// three the paper is divided into — a row every export leaves out.
  static PaperSection? _sectionOf(HighSchoolQuestion q) {
    if (q.isCq) return PaperSection.cq;
    if (q.isMcq) return PaperSection.mcq;
    if (q.isShort) return PaperSection.rq;
    return null;
  }

  /// The questions printed on the paper of set [index], out of a paper printed
  /// with [labels].
  ///
  /// Without labels there is one set and every question belongs to it.
  ///
  /// An unlabelled question belongs to *every* set: it is a question the reader
  /// selected but never filed away, and both papers should still carry it —
  /// dropping it would lose it from the paper altogether.
  ///
  /// A set that would come out empty takes the whole paper instead. That is the
  /// "সব প্রশ্ন প্রথম সেটে" case: the reader wants two copies of one set of
  /// questions, not one copy and a blank sheet. The copy's MCQs come in a
  /// different order — two papers handed out in the same room should not have
  /// the answers in the same places — while every other question keeps the
  /// order it was selected in. The first paper is never reordered.
  static List<HighSchoolQuestion> questionsForSet(
    List<HighSchoolQuestion> questions,
    List<String> labels,
    int index,
  ) {
    if (labels.isEmpty) return questions;
    final mine = questions
        .where((q) => q.setLabel.trim().isEmpty || q.setLabel == labels[index])
        .toList();
    if (mine.isNotEmpty) return mine;
    if (index == 0) return questions;
    return _mcqsReshuffled(questions, index);
  }

  /// The paper with its MCQs in a different order, everything else untouched.
  ///
  /// Seeded rather than random: the sheet, the PDF and the Word file are three
  /// exports of one paper and have to print the same order. Every MCQ moves, so
  /// no question sits in the same place on both papers.
  ///
  /// What moves is the *group*, not the question: MCQs written under one
  /// উদ্দীপক are printed under it, so shuffling one of them away from the intro
  /// would print the intro twice, or leave a question with none.
  static List<HighSchoolQuestion> _mcqsReshuffled(
    List<HighSchoolQuestion> questions,
    int index,
  ) {
    final mcqs = [
      for (final q in questions)
        if (q.isMcq) q,
    ];
    if (mcqs.length < 2) return questions;

    // One unit for each opener and the questions that follow it, so a group
    // travels as a block.
    final units = <List<HighSchoolQuestion>>[];
    for (final q in mcqs) {
      if (q.sharesMcqStemWith(units.isEmpty ? null : units.last.last)) {
        units.last.add(q);
      } else {
        units.add([q]);
      }
    }
    units.shuffle(Random(_mcqShuffleSeed + index));

    // Hand the MCQs their shuffled order back in the places they already hold,
    // so the creative and short questions keep their own order.
    final next = [for (final unit in units) ...unit];
    return [
      for (final q in questions)
        if (q.isMcq) next.removeAt(0) else q,
    ];
  }

  /// Seed for [_mcqsReshuffled]: any fixed number, so the shuffle is the same
  /// in every export of a paper.
  static const int _mcqShuffleSeed = 8137;

  /// The paper's blocks, in the reader's order.
  ///
  /// The blocks the reader dragged into place come first, then any block they
  /// left where it was. Every export reads its order from here, so the letters
  /// match across formats.
  static List<PaperSection> _orderedSections(List<PaperSection> order) => [
        ...order,
        ...PaperSection.defaultOrder.where((s) => !order.contains(s)),
      ];

  /// The set labels a paper actually prints.
  ///
  /// A blank label is not a set: a paper the reader named only one half of
  /// still prints one paper. The HTML reads the labels the same way.
  static List<String> _setLabelsOf(List<String> setLabels) => [
        for (final label in setLabels)
          if (label.trim().isNotEmpty) label.trim(),
      ];

  /// The heading a block is printed under.
  ///
  /// The বাংলা letter comes from the block's *position*, not its type: the
  /// blocks can be dragged into any order, so whichever one the reader put
  /// first is ক-বিভাগ. Tying the letter to the type would print two "ক-বিভাগ"s
  /// the moment a block moved.
  static String _sectionHeading(PaperSection kind, int position) {
    const letters = ['ক', 'খ', 'গ'];
    final letter =
        position < letters.length ? letters[position] : '${position + 1}';
    switch (kind) {
      case PaperSection.cq:
        return '$letter-বিভাগ: সৃজনশীল প্রশ্ন (CQ)';
      case PaperSection.rq:
        return '$letter-বিভাগ: সংক্ষিপ্ত প্রশ্ন (SQ)';
      case PaperSection.mcq:
        return '$letter-বিভাগ: বহুনির্বাচনী প্রশ্ন (MCQ)';
    }
  }

  /// Whether a sheet — or one set of it — still has blocks worth declaring.
  ///
  /// A sheet that holds a single type of question has nothing to tell apart, so
  /// its lone «ক-বিভাগ: বহুনির্বাচনী প্রশ্ন (MCQ)» bar is dropped and the
  /// questions print on their own. The instruction line under the bar stays: it
  /// is a directive, not a label. Every writer asks this of its own questions,
  /// so a paper with one block declares nothing in any export — and in the PDF.
  static bool _declaresSections(List<HighSchoolQuestion> questions) {
    final kinds = <PaperSection>{};
    for (final q in questions) {
      final kind = _sectionOf(q);
      if (kind != null) kinds.add(kind);
    }
    return kinds.length > 1;
  }

  /// One set of the paper: its masthead, then every block in the reader's order.
  ///
  /// The sheet holds each set in a `.paper-set` of its own so the script at the
  /// foot of the file can move one into a separate sheet when the pair does not
  /// fit on a single page. The set's name rides in the masthead's meta bar
  /// rather than in a banner of its own — the PDF does the same, and it costs no
  /// vertical space.
  static void _writeHtmlSet(
    StringBuffer buffer, {
    required String schoolName,
    required String examName,
    required String subject,
    required String className,
    required String time,
    required String totalMarks,
    required String setLabel,
    required List<HighSchoolQuestion> questions,
    required List<PaperSection> sections,
    required Set<PaperSection> twoColumnBlocks,
    required bool mergeCqAndShort,
    required StemImageSize imageSize,
  }) {
    buffer.write('''
    <div class="paper-set">
      <div class="set-head">
        ${schoolName.trim().isNotEmpty ? '<div class="school-title">${_escapeXml(schoolName)}</div>' : ''}
        ${examName.trim().isNotEmpty ? '<div class="exam-title">${_escapeXml(examName)}</div>' : ''}

        <div class="meta-bar">
          ${setLabel.isNotEmpty ? '<div>সেট: ${_escapeXml(setLabel)}</div>' : ''}
          <div>বিষয়: ${_escapeXml(subject)}</div>
          <div>শ্রেণি: ${_escapeXml(className)}</div>
          <div>সময়: ${_escapeXml(time)}</div>
          <div>পূর্ণমান: ${_escapeXml(totalMarks)}</div>
        </div>
      </div>
''');

    // What this set has to declare. A set carrying a single type of question
    // gets no bar; see [_declaresSections].
    final declares = _declaresSections(questions);

    for (var i = 0; i < sections.length; i++) {
      final kind = sections[i];
      final inSection = questions.where((q) => _sectionOf(q) == kind).toList();
      // A block that came up empty in this set is skipped. Its letter comes from
      // [i], its position in the paper, so the blocks that do print keep the
      // letters they have in the other set.
      if (inSection.isEmpty) continue;

      // A set with one type of question declares nothing — see
      // [_declaresSections] — but keeps the letters its positions give it.
      final heading = declares ? _sectionHeading(kind, i) : '';

      // CQ and the short questions are neighbours on a two-column sheet: one
      // flow for both, so the second type begins exactly where the first one
      // runs out. The partner's own turn in this loop is consumed here.
      final partner = _mergePartnerOf(sections, i, mergeCqAndShort);
      if (partner != null) {
        _writeHtmlMergedFlow(
          buffer,
          questions: questions,
          first: kind,
          second: partner,
          firstHeading: heading,
          secondHeading: _sectionHeading(partner, i + 1),
          imageSize: imageSize,
        );
        i++;
        continue;
      }

      // A block laid out in two columns declares itself *inside* the first
      // column. See [_writeHtmlDeclaration].
      final declarationInFlow = twoColumnBlocks.contains(kind);
      switch (kind) {
        case PaperSection.cq:
          _writeHtmlCqSection(buffer, inSection, heading, imageSize,
              declarationInFlow: declarationInFlow);
          break;
        case PaperSection.mcq:
          _writeHtmlMcqSection(buffer, inSection, heading, imageSize,
              declarationInFlow: declarationInFlow);
          break;
        case PaperSection.rq:
          _writeHtmlRqSection(buffer, inSection, heading,
              declarationInFlow: declarationInFlow);
          break;
      }
    }

    buffer.write('''
    </div>
''');
  }

  /// A block's declaration — the bar naming the question type.
  ///
  /// [inFlow] writes it to be placed *inside* the block's columns instead of
  /// across the page. A full-width bar over a two-column block reads as a page
  /// header and costs a line of the sheet; inside the flow it opens the first
  /// column, one column wide like the questions under it.
  static void _writeHtmlDeclaration(
    StringBuffer buffer,
    String heading, {
    required bool inFlow,
  }) {
    if (heading.isEmpty) {
      // Nothing to declare: the sheet holds one type of question. The air the
      // bar took is kept so the block does not start flush against the masthead
      // — an in-flow block gets that air from its container already, and a bar
      // inside the flow would have sat in the first column only.
      if (!inFlow) buffer.write('    <div class="section-gap"></div>\n');
      return;
    }
    buffer.write(inFlow
        ? '      <div class="section-banner in-flow">${_escapeXml(heading)}</div>\n'
        : '    <div class="section-banner">${_escapeXml(heading)}</div>\n');
  }

  /// The block that shares a flow with the one at [index], or null.
  ///
  /// CQ and the short questions merge while they are neighbours on a two-column
  /// sheet, so the second type begins where the first one runs out. MCQ never
  /// merges — its options lay out differently, and it wants a fresh pair of
  /// columns. The PDF merges on exactly the same terms.
  static PaperSection? _mergePartnerOf(
    List<PaperSection> sections,
    int index,
    bool mergeCqAndShort,
  ) {
    if (!mergeCqAndShort || index + 1 >= sections.length) return null;
    final a = sections[index], b = sections[index + 1];
    final pair = (a == PaperSection.cq && b == PaperSection.rq) ||
        (a == PaperSection.rq && b == PaperSection.cq);
    return pair ? b : null;
  }

  /// CQ and the short questions as one continuous two-column flow.
  ///
  /// Both types share one pair of columns, so the second declaration and its
  /// questions land exactly where the first type's questions run out — mid
  /// column, or at the head of the next one — instead of the second block
  /// starting a fresh full-width row below whatever the first one left over.
  static void _writeHtmlMergedFlow(
    StringBuffer buffer, {
    required List<HighSchoolQuestion> questions,
    required PaperSection first,
    required PaperSection second,
    required String firstHeading,
    required String secondHeading,
    required StemImageSize imageSize,
  }) {
    buffer.write('''
    <div class="flow-grid">
''');
    _writeHtmlFlowPart(buffer, questions, first, firstHeading, imageSize);
    _writeHtmlFlowPart(buffer, questions, second, secondHeading, imageSize);
    buffer.write('''
    </div>
''');
  }

  /// One type's share of a merged flow: its declaration, then its questions.
  ///
  /// With no container of its own — the flow the two types share *is* the
  /// column container, and that is what makes the second type continue where
  /// the first one ended.
  static void _writeHtmlFlowPart(
    StringBuffer buffer,
    List<HighSchoolQuestion> questions,
    PaperSection kind,
    String heading,
    StemImageSize imageSize,
  ) {
    final inSection = questions.where((q) => _sectionOf(q) == kind).toList();
    if (inSection.isEmpty) return;

    _writeHtmlDeclaration(buffer, heading, inFlow: true);
    if (kind == PaperSection.cq) {
      _writeHtmlCqCards(buffer, inSection, imageSize);
    } else {
      _writeHtmlRqItems(buffer, inSection);
    }
  }

  /// The সৃজনশীল প্রশ্ন block: its declaration, then one bordered card per
  /// question.
  static void _writeHtmlCqSection(
    StringBuffer buffer,
    List<HighSchoolQuestion> cqs,
    String heading,
    StemImageSize imageSize, {
    required bool declarationInFlow,
  }) {
    if (!declarationInFlow) {
      _writeHtmlDeclaration(buffer, heading, inFlow: false);
    }
    buffer.write('''
    <div class="cq-grid">
''');
    if (declarationInFlow) {
      _writeHtmlDeclaration(buffer, heading, inFlow: true);
    }
    _writeHtmlCqCards(buffer, cqs, imageSize);
    buffer.write('''
    </div>
''');
  }

  /// The CQ cards, with no container: the block or the merged flow supplies the
  /// columns.
  static void _writeHtmlCqCards(
    StringBuffer buffer,
    List<HighSchoolQuestion> cqs,
    StemImageSize imageSize,
  ) {
    for (int i = 0; i < cqs.length; i++) {
      final q = cqs[i];
      final index = i + 1;
      buffer.write('''
    <div class="cq-card" title="${_idTooltip(q)}">
      <div class="cq-stem">
        <b>$index.</b> ${_htmlText(q.paperStemText, latex: true)}
      </div>
      ${_stemImageMarkup(q, size: imageSize, usePoints: false)}
''');
      for (final sq in q.cqSubQuestions) {
        buffer.write('''
      <div class="cq-sub-item">
        <div><b>(${_escapeXml(sq.label)})</b> ${_htmlText(sq.text, latex: true)}</div>
        <div class="cq-mark">${sq.mark > 0 ? '[${sq.mark}]' : ''}</div>
      </div>
''');
      }
      buffer.write('''
    </div>
''');
    }
  }

  /// The বহুনির্বাচনী প্রশ্ন block.
  ///
  /// MCQs written under one উদ্দীপক share it: the intro and its figure print once,
  /// over the first question of the group, and the questions under it print bare.
  /// The grouping is by consecutive identical stem text and figure, so the sheet
  /// says which questions belong together simply by repeating the intro on each
  /// row.
  static void _writeHtmlMcqSection(
    StringBuffer buffer,
    List<HighSchoolQuestion> mcqs,
    String heading,
    StemImageSize imageSize, {
    required bool declarationInFlow,
  }) {
    if (!declarationInFlow) {
      _writeHtmlDeclaration(buffer, heading, inFlow: false);
    }
    buffer.write('''
    <div class="mcq-grid">
''');
    if (declarationInFlow) {
      _writeHtmlDeclaration(buffer, heading, inFlow: true);
    }
    const bengaliLetters = ['ক', 'খ', 'গ', 'ঘ'];
    HighSchoolQuestion? previous;
    for (int i = 0; i < mcqs.length; i++) {
      final q = mcqs[i];
      final mcq = q.mcqData;
      final index = i + 1;
      if (mcq == null) continue;

      // The last question actually printed, which is what decides whether this
      // one has already had its intro.
      final opensStem = q.opensMcqStemGroup(previous);
      previous = q;

      buffer.write('''
      <div class="mcq-card" title="${_idTooltip(q)}">
        <div class="mcq-head">
''');
      if (opensStem) {
        buffer.write('''
          <div class="mcq-stem">${_htmlText(stemWithNumbers(q.mcqStemText, mcqStemRunNumbers(mcqs, i)), latex: true)}${_stemImageMarkup(q, size: imageSize, usePoints: false)}</div>
''');
      }
      buffer.write('''
          <div class="mcq-question"><b>$index.</b> ${_htmlText(q.paperQuestionText)}</div>
        </div>
        <div class="mcq-options" data-fit="1">
''');
      final options = mcq.options;
      for (int opt = 0; opt < options.length; opt++) {
        final l =
            opt < bengaliLetters.length ? bengaliLetters[opt] : '${opt + 1}';
        buffer.write('''
          <div>($l) ${_htmlText(options[opt])}</div>
''');
      }
      buffer.write('''
        </div>
      </div>
''');
    }
    buffer.write('''
    </div>
''');
  }

  /// The `title` every question block carries: its id, shown by the browser on
  /// hover and printed by nothing.
  ///
  /// It is there so a question on the paper can be found in the sheet it came
  /// from. Hand-typed questions have a local `manual-…` id, which is exactly
  /// right: it says the row is not in the bank.
  static String _idTooltip(HighSchoolQuestion q) => 'আইডি: ${_escapeXml(q.id)}';

  /// The সংক্ষিপ্ত প্রশ্ন block.
  static void _writeHtmlRqSection(
    StringBuffer buffer,
    List<HighSchoolQuestion> shorts,
    String heading, {
    required bool declarationInFlow,
  }) {
    if (!declarationInFlow) {
      _writeHtmlDeclaration(buffer, heading, inFlow: false);
    }
    buffer.write('''
    <div class="rq-list">
      <div class="rq-grid">
''');
    if (declarationInFlow) {
      _writeHtmlDeclaration(buffer, heading, inFlow: true);
    }
    _writeHtmlRqItems(buffer, shorts);
    buffer.write('''
      </div>
    </div>
''');
  }

  /// The short-question lines, with no container: the block or the merged flow
  /// supplies the columns.
  static void _writeHtmlRqItems(
    StringBuffer buffer,
    List<HighSchoolQuestion> shorts,
  ) {
    for (int i = 0; i < shorts.length; i++) {
      final data = shorts[i].shortData;
      if (data == null || data.text.trim().isEmpty) continue;
      buffer.write('''
        <div class="rq-item" title="${_idTooltip(shorts[i])}">
          <div><b>${i + 1}.</b> ${_htmlText(data.text)}</div>
          <div class="rq-mark">[${data.mark}]</div>
        </div>
''');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 4. Markdown Format (.md)
  // ─────────────────────────────────────────────────────────────────────────

  static String generateMarkdown({
    required String schoolName,
    required String examName,
    required String subject,
    required String className,
    required String time,
    required String totalMarks,
    required List<HighSchoolQuestion> questions,
    StemImageSize imageSize = StemImageSize.medium,
    List<String> setLabels = const [],
    List<PaperSection> sectionOrder = PaperSection.defaultOrder,
  }) {
    final buffer = StringBuffer();
    final labels = _setLabelsOf(setLabels);
    final sections = [
      for (final s in _orderedSections(sectionOrder))
        if (questions.any((q) => _sectionOf(q) == s)) s,
    ];

    // Two sets are two papers in one file, as in the PDF and the HTML sheet.
    final sets = labels.isEmpty ? 1 : labels.length;
    for (var s = 0; s < sets; s++) {
      if (s > 0) buffer.writeln('---\n');
      _writeMarkdownSet(
        buffer,
        schoolName: schoolName,
        examName: examName,
        subject: subject,
        className: className,
        time: time,
        totalMarks: totalMarks,
        setLabel: labels.isEmpty ? '' : labels[s],
        questions: questionsForSet(questions, labels, s),
        sections: sections,
        imageSize: imageSize,
      );
    }
    return buffer.toString();
  }

  /// One set of the markdown paper: its masthead, then every block in the
  /// reader's order, under the letter its position gives it.
  static void _writeMarkdownSet(
    StringBuffer buffer, {
    required String schoolName,
    required String examName,
    required String subject,
    required String className,
    required String time,
    required String totalMarks,
    required String setLabel,
    required List<HighSchoolQuestion> questions,
    required List<PaperSection> sections,
    required StemImageSize imageSize,
  }) {
    if (schoolName.trim().isNotEmpty) {
      buffer.writeln('# ${schoolName.trim()}\n');
    }
    if (examName.trim().isNotEmpty) {
      buffer.writeln('## ${examName.trim()}\n');
    }

    buffer.writeln(<String>[
      if (setLabel.isNotEmpty) '**সেট:** $setLabel',
      '**বিষয়:** $subject',
      '**শ্রেণি:** $className',
      '**সময়:** $time',
      '**পূর্ণমান:** $totalMarks',
    ].join(' | '));
    buffer.writeln('\n---\n');

    var printed = 0;
    // A sheet with one type of question needs no declaration; see
    // [_declaresSections].
    final declares = _declaresSections(questions);
    for (var i = 0; i < sections.length; i++) {
      final kind = sections[i];
      final inSection = questions.where((q) => _sectionOf(q) == kind).toList();
      if (inSection.isEmpty) continue;

      if (printed > 0) buffer.writeln('---\n');
      printed++;

      if (declares) buffer.writeln('### ${_sectionHeading(kind, i)}\n');
      switch (kind) {
        case PaperSection.cq:
          for (int j = 0; j < inSection.length; j++) {
            final q = inSection[j];
            buffer.writeln(
                '**${j + 1}.** ${latexToPlainText(q.paperStemText.trim())}');
            if (_hasStemImage(q, imageSize)) {
              buffer.writeln('![উদ্দীপক চিত্র](${_stemImageUrlOf(q)})');
            }
            buffer.writeln();
            for (final sq in q.cqSubQuestions) {
              buffer.writeln('- **(${sq.label})** ${sq.text} `[${sq.mark}]`');
            }
            buffer.writeln();
          }
          break;

        case PaperSection.mcq:
          const bengaliLetters = ['ক', 'খ', 'গ', 'ঘ'];
          HighSchoolQuestion? previousMcq;
          for (int j = 0; j < inSection.length; j++) {
            final q = inSection[j];
            final mcq = q.mcqData;
            if (mcq == null) continue;

            // The shared intro, once, over the first question of its group.
            if (q.opensMcqStemGroup(previousMcq)) {
              buffer.writeln('> ${stemWithNumbers(q.mcqStemText, mcqStemRunNumbers(inSection, j))}\n');
              if (_hasStemImage(q, imageSize)) {
                buffer.writeln('![উদ্দীপক চিত্র](${_stemImageUrlOf(q)})\n');
              }
            }
            previousMcq = q;

            buffer.writeln('**${j + 1}.** ${q.paperQuestionText}');
            for (int opt = 0; opt < mcq.options.length; opt++) {
              final l = opt < bengaliLetters.length
                  ? bengaliLetters[opt]
                  : '${opt + 1}';
              buffer.writeln('- ($l) ${mcq.options[opt]}');
            }
            buffer.writeln();
          }
          break;

        case PaperSection.rq:
          for (int j = 0; j < inSection.length; j++) {
            final data = inSection[j].shortData;
            if (data == null || data.text.trim().isEmpty) continue;
            buffer
                .writeln('**${j + 1}.** ${data.text.trim()} `[${data.mark}]`');
          }
          buffer.writeln();
          break;
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 5. JSON Format (.json)
  // ─────────────────────────────────────────────────────────────────────────

  static String generateJson({
    required String schoolName,
    required String examName,
    required String subject,
    required String className,
    required String time,
    required String totalMarks,
    required List<HighSchoolQuestion> questions,
  }) {
    final data = {
      'exam_info': {
        'school_name': schoolName,
        'exam_name': examName,
        'subject': subject,
        'class': className,
        'time': time,
        'total_marks': totalMarks,
        'generated_at': DateTime.now().toIso8601String(),
        'platform': 'Pi-QBank',
      },
      'questions': questions.map((q) => q.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // File I/O & Sharing Helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// A file name that keeps the script the paper is written in.
  ///
  /// The old filter was `[^\w\.-]`, and Dart's `\w` is ASCII-only: every Bengali
  /// letter in `পদার্থবিজ্ঞান.html` became an underscore, so the whole name
  /// collapsed to `________________.html` and each export overwrote the last.
  /// Only the characters a file system actually rejects are replaced now — the
  /// readers' own script is left alone.
  static String safeFileName(String name) {
    final cleaned = name
        // Path separators, the Windows-reserved set and control characters.
        .replaceAll(RegExp(r'[\\/:*?"<>|\u0000-\u001F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceFirst(RegExp(r'^[. ]+'), '')
        .replaceFirst(RegExp(r'[. ]+$'), '');
    return cleaned.isEmpty ? 'document' : cleaned;
  }

  static Future<File> saveFile({
    required String content,
    required String fileName,
    List<int>? bytes,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final sanitizedName = safeFileName(fileName);
    final file = File('${tempDir.path}/$sanitizedName');
    if (bytes != null) {
      await file.writeAsBytes(bytes);
    } else {
      await file.writeAsString(content, encoding: utf8);
    }
    return file;
  }

  static Future<void> openExportedFile(BuildContext context, File file) async {
    try {
      final result = await OpenFile.open(file.path);
      if (result.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ফাইলটি সরাসরি ওপেন করা যায়নি: ${result.message}'),
            backgroundColor: Colors.amber.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ত্রুটি: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  static Future<void> shareExportedFile(File file, {String? text}) async {
    await Share.shareXFiles(
      [XFile(file.path)],
      text: text ?? 'Pi-QBank Question Paper',
    );
  }

  static void copyToClipboard(
    BuildContext context,
    String text, {
    String message = 'প্রশ্নপত্রের টেক্সট সফলভাবে কপি করা হয়েছে!',
  }) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  static String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  /// Element text for the HTML and Word writers: escaped, typeset when asked,
  /// and carrying the writer's own line breaks.
  ///
  /// A question typed over several lines — the `i. … ii. … iii. …` form of an
  /// MCQ, or a short question with a list in it — has to print the way it was
  /// written. HTML folds a newline into a space, so the breaks came out as a
  /// single run-on paragraph; `<br>` is what the browser wants instead, and Word
  /// reads the same markup. The PDF never had the problem: the pdf package
  /// breaks a span on '\n' by itself.
  static String _htmlText(String input, {bool latex = false}) {
    final body = latex ? latexToHtml(_escapeXml(input)) : _escapeXml(input);
    return body.replaceAll('\n', '<br>');
  }
}

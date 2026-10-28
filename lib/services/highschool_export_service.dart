import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
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

  /// Three questions per row for compact MCQ papers.
  tripleColumn,
}

extension QuestionLayoutMetrics on QuestionLayout {
  /// How many MCQs sit side by side.
  int get mcqColumns => switch (this) {
        QuestionLayout.single => 1,
        QuestionLayout.doubleColumn => 2,
        QuestionLayout.tripleColumn => 3,
      };

  bool get isDouble => this == QuestionLayout.doubleColumn;

  String get label => switch (this) {
        QuestionLayout.single => 'এক কলাম',
        QuestionLayout.doubleColumn => 'দুই কলাম',
        QuestionLayout.tripleColumn => 'তিন কলাম',
      };

  String get description => switch (this) {
        QuestionLayout.single =>
          'প্রতি সারিতে একটি MCQ — প্রশ্ন ও অপশন সরল দেখা যায়',
        QuestionLayout.doubleColumn =>
          'প্রতি সারিতে দুটি MCQ — কম পেজ, ছোট প্রশ্নপত্র',
        QuestionLayout.tripleColumn =>
          'প্রতি সারিতে তিনটি MCQ — খুব কম পেজে ছাপা যায়',
      };
}

/// Optional answer sheet printed after the generated MCQ paper.
enum McqAnswerSheetStyle {
  none,
  omr,
  serialAnswer,
}

extension McqAnswerSheetStyleLabels on McqAnswerSheetStyle {
  String get label => switch (this) {
        McqAnswerSheetStyle.none => 'বন্ধ',
        McqAnswerSheetStyle.omr => 'OMR বুদবুদ',
        McqAnswerSheetStyle.serialAnswer => 'নম্বর + উত্তর ঘর',
      };

  String get description => switch (this) {
        McqAnswerSheetStyle.none => 'কোনো আলাদা MCQ উত্তরপত্র নয়',
        McqAnswerSheetStyle.omr => 'ক–ঘ বৃত্তে টিক বা চিহ্ন দেওয়ার গ্রিড',
        McqAnswerSheetStyle.serialAnswer =>
          'প্রশ্ন নম্বরের পাশে হাতে উত্তর লেখার ঘর',
      };
}

/// The paper stock a sheet is laid out on.
enum PaperSize { a4, letter, legal, a5 }

extension PaperSizeMetrics on PaperSize {
  String get label => switch (this) {
        PaperSize.a4 => 'A4',
        PaperSize.letter => 'Letter',
        PaperSize.legal => 'Legal',
        PaperSize.a5 => 'A5',
      };

  double get widthMm => switch (this) {
        PaperSize.a4 => 210,
        PaperSize.letter => 215.9,
        PaperSize.legal => 215.9,
        PaperSize.a5 => 148,
      };

  double get heightMm => switch (this) {
        PaperSize.a4 => 297,
        PaperSize.letter => 279.4,
        PaperSize.legal => 355.6,
        PaperSize.a5 => 210,
      };

  /// The margin down each side of the sheet. A5 is narrow enough that the A4
  /// gutter would leave too little room for a line of Bengali text.
  double get sidePaddingPt => this == PaperSize.a5 ? 20 : 28;

  String get widthCss => '${_mm(widthMm)}mm';
  String get heightCss => '${_mm(heightMm)}mm';
  String get cssSize => '$widthCss $heightCss';

  static String _mm(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
}

/// How the body of the sheet lines up.
enum PaperTextAlign { left, center, right, justify }

extension PaperTextAlignLabels on PaperTextAlign {
  String get label => switch (this) {
        PaperTextAlign.left => 'বাম',
        PaperTextAlign.center => 'মাঝ',
        PaperTextAlign.right => 'ডান',
        PaperTextAlign.justify => 'সমান্তরাল',
      };

  String get css => name;
}

/// How an MCQ option's letter is written.
enum McqOptionStyle { circle, parentheses, dot, closeParenthesis }

extension McqOptionStyleLabels on McqOptionStyle {
  String get label => switch (this) {
        McqOptionStyle.circle => '○',
        McqOptionStyle.parentheses => '()',
        McqOptionStyle.dot => '.',
        McqOptionStyle.closeParenthesis => ')',
      };

  String prefix(String letter) => switch (this) {
        McqOptionStyle.circle => '$letter ○',
        McqOptionStyle.parentheses => '($letter)',
        McqOptionStyle.dot => '$letter.',
        McqOptionStyle.closeParenthesis => '$letter)',
      };
}

/// The print-settings panel's choices that are not already named arguments of
/// [HighSchoolExportService.generateHtml].
///
/// The defaults reproduce the sheet as it was before the panel existed, so a
/// caller that does not pass these settings gets the same HTML it used to.
class PaperPrintSettings {
  const PaperPrintSettings({
    this.paperSize = PaperSize.a4,
    this.textAlign = PaperTextAlign.left,
    this.pageNumbers = false,
    this.optionStyle = McqOptionStyle.parentheses,
    this.columnDivider = true,
    this.questionGap = 0,
    this.columnGap = 22,
    this.showSchool = true,
    this.showExam = true,
    this.showSubject = true,
    this.showClass = true,
    this.showSet = true,
    this.showInstructions = true,
    this.showChapter = false,
    this.showSubjectCode = false,
    this.showStudentInfo = false,
    this.showObtainedMarks = false,
    this.showQuestionInfo = false,
    this.showImportant = false,
    this.editingMode = false,
    this.showLogo = false,
    this.showHeader = false,
    this.showFooter = false,
    this.showWatermark = false,
    this.showAddress = false,
    this.chapter = '',
    this.subjectCode = '',
    this.address = '',
    this.headerNote = '',
    this.watermarkText = '',
    this.logoDataUri = '',
  });

  final PaperSize paperSize;
  final PaperTextAlign textAlign;
  final bool pageNumbers;
  final McqOptionStyle optionStyle;
  final bool columnDivider;
  final double questionGap;
  final double columnGap;

  final bool showSchool;
  final bool showExam;
  final bool showSubject;
  final bool showClass;
  final bool showSet;
  final bool showInstructions;
  final bool showChapter;
  final bool showSubjectCode;
  final bool showStudentInfo;
  final bool showObtainedMarks;
  final bool showQuestionInfo;
  final bool showImportant;

  /// Starts the preview with the sheet editable, the same state the toolbar's
  /// edit button switches on.
  final bool editingMode;

  final bool showLogo;
  final bool showHeader;
  final bool showFooter;
  final bool showWatermark;
  final bool showAddress;

  final String chapter;
  final String subjectCode;
  final String address;

  /// An extra line the panel's A button adds under the exam title.
  final String headerNote;

  final String watermarkText;

  /// A `data:image/...;base64,...` URI for the school logo, or empty.
  final String logoDataUri;

  /// A cheap value that moves whenever the sheet would change.
  ///
  /// The live preview reloads only when its signature moves; without this the
  /// panel's switches would update the export but leave the pane on the old
  /// sheet.
  String get signature => [
        paperSize.name,
        textAlign.name,
        pageNumbers,
        optionStyle.name,
        columnDivider,
        questionGap,
        columnGap,
        showSchool,
        showExam,
        showSubject,
        showClass,
        showSet,
        showInstructions,
        showChapter,
        showSubjectCode,
        showStudentInfo,
        showObtainedMarks,
        showQuestionInfo,
        showImportant,
        editingMode,
        showLogo,
        showHeader,
        showFooter,
        showWatermark,
        showAddress,
        chapter,
        subjectCode,
        address,
        headerNote,
        watermarkText,
        logoDataUri,
      ].join('~');
}

/// A Bangla face a paper can be printed in.
///
/// The PDF stands apart: it sets Bangla through SutonnyMJ, a Bijoy-ANSI face
/// with a text pipeline of its own, so this choice reaches the HTML sheet and
/// the Word file, not the PDF.
///
/// [family] is the name a stylesheet asks for. [google] is the Google Fonts
/// family that supplies it over the network when the machine reading the file
/// does not have it installed; [asset] is the copy the app *ships*, which the
/// sheet carries inside itself (see [HighSchoolExportService.preloadPaperFonts]).
/// A face with neither is one the reading machine has to have — Nirmala UI is
/// Windows' own, and cannot be handed out. Every stack ends in Hind Siliguri,
/// which is always fetched, so the paper prints in something readable either
/// way.
///
/// A shipped copy is not a nicety. A phone has no Kalpurush to fall back on and
/// no way to install one, so a paper set in it came out in whatever face the
/// phone happened to have — right on the teacher's laptop, wrong on the student's
/// phone, from one and the same file.
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
  // SIL Open Font License 1.0, so the app may carry it (see the licence in the
  // font's own name table). OFL says the licence travels with the font, which
  // assets/fonts/LICENSE-Kalpurush.txt holds.
  kalpurush('কলপুরুষ (Kalpurush)', 'Kalpurush',
      asset: 'assets/fonts/Kalpurush.ttf'),
  // Not carried: a face the app does not ship can only be used where it is
  // installed, which the picker marks.
  solaimanLipi('সলাইমানলিপি (SolaimanLipi)', 'SolaimanLipi'),
  nirmalaUi('নির্মলা ইউআই (Nirmala UI)', 'Nirmala UI');

  const PaperFont(this.label, this.family, {this.google = '', this.asset = ''});

  /// What the picker shows the reader.
  final String label;

  /// The face's own name, without quotes — the first name in every stack and
  /// the name a Word file asks for.
  final String family;

  /// The Google Fonts family query for this face, or empty when the sheet cannot
  /// fetch it.
  final String google;

  /// The TTF the app ships for this face, or empty when it ships none. Read as
  /// an asset; declared in pubspec.yaml as part of `assets/fonts/`.
  final String asset;

  /// Whether reading the file means downloading this face.
  bool get isWebFont => google.isNotEmpty;

  /// Whether the app carries the face and can write it into the file.
  bool get isBundled => asset.isNotEmpty;

  /// Whether the paper can only come out right on a machine that already has
  /// this face. Only such a face is worth marking in the picker.
  bool get needsInstalling => !isWebFont && !isBundled;

  /// The code points a shipped Bengali face is used for.
  ///
  /// The embedded copy is restricted to them — Bengali itself, the danda a
  /// Bengali sentence often ends with, and the joiners that shape conjuncts.
  /// Everything else keeps the face it has today: Latin (including a `\` in a
  /// set difference, or a `C:\Users\…` path) stays with the Latin face exactly
  /// as the named stack and the PDF's Helvetica do, and every maths symbol stays
  /// with the `.m` class.
  static const String bengaliCodePoints =
      'U+0964-0965, U+0980-09FF, U+200C-200D, U+25CC';

  /// The private name the *embedded* copy is declared under.
  ///
  /// A name no machine has, on purpose: a document's `@font-face` shadows an
  /// installed font of the same name, and this sheet has to draw the same face
  /// with and without the face installed. It also lets the rule carry a
  /// Bengali-only `unicode-range` without a reader wondering which of two
  /// Kalpurush a Latin word came from.
  String get embeddedFamily => 'Pi-QBank $family';

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
  String get cssStack => _stack(embedded: false);

  /// The same stack for a sheet that carries the face itself, which asks for the
  /// embedded copy *first* — the copy is the only one a phone has.
  ///
  /// That does not undo the rule above: the embedded face is declared for
  /// Bengali only (see [bengaliCodePoints]), so a Latin run is not one it can
  /// draw and still falls through to `sans-serif`. The face's own name stays in
  /// the list behind it, for a letter the shipped copy happens to miss.
  String get embeddedStack => _stack(embedded: true);

  String _stack({required bool embedded}) => [
        if (embedded) "'$embeddedFamily'",
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

    return '<img class="paper-image" src="$src" alt="উদ্দীপক চিত্র" '
        'contenteditable="false" draggable="true" '
        'data-base-max-width="${_trimNum(maxW)}" '
        'data-base-max-height="${_trimNum(maxH)}" data-base-unit="$unit" '
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
  // The face the sheet carries
  // ─────────────────────────────────────────────────────────────────────────

  /// The shipped faces, as data URIs, filled by [preloadPaperFonts].
  static final Map<PaperFont, String> _embeddedFaces = {};

  /// The print settings of the sheet being written.
  ///
  /// [generateHtml] is synchronous and the writers below only run from it, so
  /// one field carries the panel's choices through the nested helpers instead
  /// of threading another parameter through every one of them.
  static PaperPrintSettings _print = const PaperPrintSettings();

  /// Whether [font]'s face is in hand and can be written into a sheet.
  static bool carriesPaperFont(PaperFont font) =>
      _embeddedFaces.containsKey(font);

  /// Load the faces the app ships so a sheet can carry them.
  ///
  /// The work is done once and a second call returns immediately. Failing is not
  /// fatal: a face that could not be read is left un-embedded and the sheet asks
  /// for it by name, which is all it could do before the app carried a copy.
  ///
  /// Callers that write or show a sheet wait for this ([generateHtml] itself
  /// stays synchronous, and simply leaves the face out when it has not arrived).
  static Future<void> preloadPaperFonts() async {
    for (final font in PaperFont.values) {
      if (!font.isBundled || _embeddedFaces.containsKey(font)) continue;
      try {
        final bytes = await rootBundle.load(font.asset);
        _embeddedFaces[font] = _fontDataUri(bytes.buffer.asUint8List());
      } catch (_) {
        // Left out; the file names the face instead.
      }
    }
  }

  /// The `data:` URI a stylesheet embeds the face with.
  static String _fontDataUri(Uint8List bytes) =>
      'data:font/ttf;base64,${base64Encode(bytes)}';

  /// Fill the cache without touching the asset bundle — for tests that hand in
  /// the bytes themselves.
  @visibleForTesting
  static void cachePaperFontBytes(PaperFont font, Uint8List bytes) {
    _embeddedFaces[font] = _fontDataUri(bytes);
  }

  /// The `@font-face` block [font] is written into a sheet with, indented to sit
  /// with the rules around it, or empty when the sheet does not carry the face.
  ///
  /// The face goes into the file itself rather than by name because the machines
  /// that need it most cannot fetch it and cannot install it: a phone reading the
  /// file, and a school computer that never had the Bangla typing tools.
  ///
  /// It is declared under a name of its own ([PaperFont.embeddedFamily]) and
  /// only for Bengali ([PaperFont.bengaliCodePoints]), so Latin text and maths
  /// symbols keep the faces they have in the rest of the sheet.
  static String _paperFontBlock(PaperFont font) {
    final data = _embeddedFaces[font];
    if (data == null) return '';
    return '''
    /* The face this sheet is printed in, carried in the file itself: a phone has
       no Kalpurush to fall back on, and the reader of an exported file rarely
       installed one. Bengali only, so the Latin and the maths keep their faces. */
    @font-face {
      font-family: '${font.embeddedFamily}';
      src: url($data) format('truetype');
      font-display: swap;
      unicode-range: ${PaperFont.bengaliCodePoints};
    }
''';
  }

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
  static final RegExp _stemNumbersRef =
      RegExp(r'\(([0-9\u09E6-\u09EF][0-9\u09E6-\u09EF\s,ওএবং\-–—]*)\)'
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
  static List<int> mcqStemRunNumbers(List<HighSchoolQuestion> mcqs, int start) {
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
      return intro.replaceAll(
          stemNumbersPlaceholder, _joinStemNumbers(numbers, bengali: true));
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
        ? '$number'.split('').map((d) => bengaliDigits[int.parse(d)]).join()
        : '$number';

    if (numbers.length == 1) return show(numbers.first);
    final head = numbers.take(numbers.length - 1).map(show).join(', ');
    return bengali
        ? '$head ও ${show(numbers.last)}'
        : '$head and ${show(numbers.last)}';
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
    StemImageSize imageSize = StemImageSize.small,
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
          for (int j = 0; j < inSection.length; j++) {
            final q = inSection[j];
            final mcq = q.mcqData;
            if (mcq == null) continue;
            final prev = j > 0 ? inSection[j - 1] : null;
            final opensStem = q.opensMcqStemGroup(prev);
            final sharesStem = q.sharesMcqStemWith(prev);
            // A shared উদ্দীপক is written once, over the first question of the
            // group, in every export format alike.
            if (opensStem) {
              buffer.writeln(stemWithNumbers(
                  q.mcqStemText, mcqStemRunNumbers(inSection, j)));
              if (_hasStemImage(q, imageSize)) {
                buffer.writeln('   [চিত্র: ${_stemImageUrlOf(q)}]');
              }
              buffer.writeln();
            }
            buffer.writeln('${j + 1}. ${q.paperQuestionText}');
            final alreadyPrintedStem = opensStem ||
                (sharesStem &&
                    prev != null &&
                    _hasStemImage(prev, imageSize) &&
                    prev.stemImageUrl.trim() == q.stemImageUrl.trim());
            if (!alreadyPrintedStem && _hasStemImage(q, imageSize)) {
              buffer.writeln('   [চিত্র: ${_stemImageUrlOf(q)}]');
            }
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
            final q = inSection[j];
            final data = q.shortData;
            if (data == null || data.text.trim().isEmpty) continue;
            final markStr = data.mark > 0 ? ' [${data.mark}]' : '';
            buffer.writeln('${j + 1}. ${data.text.trim()}$markStr');
            if (_hasStemImage(q, imageSize)) {
              buffer.writeln('   [চিত্র: ${_stemImageUrlOf(q)}]');
            }
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
    StemImageSize imageSize = StemImageSize.small,
    List<String> setLabels = const [],
    List<PaperSection> sectionOrder = PaperSection.defaultOrder,
    QuestionLayout cqLayout = QuestionLayout.single,
    QuestionLayout mcqLayout = QuestionLayout.doubleColumn,
    QuestionLayout rqLayout = QuestionLayout.single,

    /// The face the document is set in, as in the HTML sheet; see [PaperFont].
    PaperFont font = PaperFont.kalpurush,
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
      width: ${100 / cqLayout.mcqColumns}%;
      vertical-align: top;
      padding: 0pt 4pt 8pt 0pt;
    }
    .mcq-col-cell {
      width: ${100 / mcqLayout.mcqColumns}%;
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
      width: ${100 / rqLayout.mcqColumns}%;
      vertical-align: top;
      padding: 0pt 4pt 0pt 0pt;
    }
    .rq-item {
      display: flex;
      justify-content: space-between;
      align-items: flex-start;
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
          _writeWordRqSection(
              buffer, inSection, heading, rqLayout, imageBytes, imageSize);
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
    String questionCell(int index, HighSchoolQuestion q) {
      final mcq = q.mcqData;
      if (mcq == null) return '<td class="mcq-col-cell"></td>';
      // The last question actually printed decides whether this one has already
      // had its intro.
      final prev = index > 1 ? mcqs[index - 2] : null;
      final opensStem = q.opensMcqStemGroup(prev);
      final sharesStem = q.sharesMcqStemWith(prev);

      final alreadyPrintedStem = opensStem ||
          (sharesStem &&
              prev != null &&
              _hasStemImage(prev, imageSize) &&
              prev.stemImageUrl.trim() == q.stemImageUrl.trim());
      final questionImageHtml =
          (!alreadyPrintedStem && _hasStemImage(q, imageSize))
              ? _stemImageMarkup(q,
                  bytes: imageBytes, size: imageSize, usePoints: true)
              : '';

      return '''
    <td class="mcq-col-cell">
      ${opensStem ? '<div class="mcq-stem">${_htmlText(stemWithNumbers(q.mcqStemText, mcqStemRunNumbers(mcqs, index - 1)), latex: true)}${_stemImageMarkup(q, bytes: imageBytes, size: imageSize, usePoints: true)}</div>' : ''}
      <div class="mcq-question"><b>$index.</b> ${_htmlText(q.paperQuestionText)}</div>
      $questionImageHtml
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
    Map<String, Uint8List>? imageBytes,
    StemImageSize imageSize,
  ) {
    buffer.write('''
  ${_wordSectionTitle(heading)}
  <div style="font-size:10pt; font-style:italic; margin-bottom:8pt; text-align:center;">[সংক্ষেপে উত্তর দাও]</div>
''');

    String rqCell(int index) {
      final q = shorts[index];
      final data = q.shortData;
      if (data == null || data.text.trim().isEmpty) return '';
      final imageHtml = _stemImageMarkup(q,
          bytes: imageBytes, size: imageSize, usePoints: true);
      return '''
    <div class="rq-item">
      <div style="flex:1;">
        <span>${index + 1}. ${_htmlText(data.text)}</span>
        $imageHtml
      </div>
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

    /// The instruction the CQ block carries — "যেকোনো ৫ টি প্রশ্নের উত্তর
    /// দাও". Empty leaves the paper without one.
    String cqInstruction = '',
    List<String> setLabels = const [],
    List<PaperSection> sectionOrder = PaperSection.defaultOrder,
    StemImageSize imageSize = StemImageSize.small,
    QuestionLayout cqLayout = QuestionLayout.single,
    QuestionLayout mcqLayout = QuestionLayout.doubleColumn,
    QuestionLayout rqLayout = QuestionLayout.single,
    McqAnswerSheetStyle mcqAnswerSheetStyle = McqAnswerSheetStyle.none,
    double fontStep = 0,
    Map<String, Uint8List>? imageBytes,

    /// The face the sheet is set in. Fetched from Google Fonts when it is a web
    /// font, and fallen back on when it is not; see [PaperFont].
    PaperFont font = PaperFont.kalpurush,

    /// The choices the print-settings panel adds on top of the arguments above:
    /// paper stock, header toggles, watermark, page numbers, and so on. The
    /// defaults keep the sheet exactly as it was before the panel existed.
    PaperPrintSettings printSettings = const PaperPrintSettings(),

    /// Lay the sheet out for a desktop-width window instead of the device's own
    /// width. The live preview asks for this; see [desktopViewport] below.
    bool desktopMode = false,

    /// Use the compact toolbar arrangement for the Android embedded preview.
    bool compactToolbar = false,

    /// Keep the editor toolbar in the generated document. The browser app
    /// moves these controls into its own settings rail.
    bool includeToolbar = true,
  }) {
    _print = printSettings;

    // The page box. Page numbers need a foot of room for the margin box; the
    // sheet itself keeps its own side padding either way.
    final pageMargin = _print.pageNumbers ? '0 0 10mm 0' : '0';
    final pageNumberRule = _print.pageNumbers
        ? ' @bottom-center { content: "পৃষ্ঠা " counter(page, bengali);'
            ' font-size: 9pt; color: #64748b; }'
        : '';

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
      if (cqLayout.mcqColumns > 1) PaperSection.cq,
      if (rqLayout.mcqColumns > 1) PaperSection.rq,
      if (mcqLayout.mcqColumns > 1) PaperSection.mcq,
    };
    final mergeCqAndShort = cqLayout.mcqColumns > 1 && rqLayout.mcqColumns > 1;

    // A face the app ships goes into the file, so the sheet prints the same on a
    // phone as on the machine it was written on; see [_paperFontBlock]. The
    // stylesheet asks for the embedded copy by name when there is one, and for
    // the face itself when there is not.
    final carriesFont = carriesPaperFont(font);
    final paperFontBlock = _paperFontBlock(font);
    final bodyStack = carriesFont ? font.embeddedStack : font.cssStack;

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

    final previewFontOptions = [
      for (final option in PaperFont.values)
        '<option value="${_escapeXml(option.cssStack)}" ${option == font ? 'selected' : ''}>${_escapeXml(option.label)}</option>',
    ].join();
    final previewFontStepOptions = [
      for (var step = -3; step <= 6; step++)
        '<option value="$step" ${fontStep.round() == step ? 'selected' : ''}>${step == 0 ? 'স্বাভাবিক' : '${step > 0 ? '+' : ''}$step pt'}</option>',
    ].join();
    final previewImageOptions = [
      for (final option in StemImageSize.values)
        '<option value="${option.name}" ${option == imageSize ? 'selected' : ''}>${_escapeXml(option.label)}</option>',
    ].join();
    final previewAnswerSheetOptions = [
      for (final option in McqAnswerSheetStyle.values)
        '<option value="${option.name}" ${option == mcqAnswerSheetStyle ? 'selected' : ''}>${_escapeXml(option.label)}</option>',
    ].join();
    final hasMcq = questions.any((q) => q.isMcq);
    final previewAnswerSheetControl = '''
      <div class="toolbar-group answer-group">
        <span class="toolbar-group-label">MCQ উত্তরপত্র</span>
        <select class="preview-select" id="previewAnswerSheet" aria-label="MCQ উত্তরপত্র">
          $previewAnswerSheetOptions
        </select>
        ${hasMcq ? '' : '<input class="preview-number answer-item-count" id="answerItemCount" type="number" min="1" max="200" value="30" aria-label="MCQ উত্তর আইটেম সংখ্যা" title="MCQ না থাকলে উত্তর আইটেম সংখ্যা">'}
      </div>''';

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
$paperFontBlock    :root {
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
      font-family: $bodyStack;
      background: var(--bg);
      color: var(--text);
      line-height: 1.6;
      padding: 24px;
    }
    .no-print-toolbar {
      max-width: 210mm;
      margin: 0 auto 20px auto;
      display: flex;
      flex-direction: column;
      align-items: stretch;
      gap: 12px;
      background: white;
      padding: 14px 20px;
      border-radius: 12px;
      box-shadow: 0 4px 12px rgba(0,0,0,0.06);
    }
    .toolbar-hidden .no-print-toolbar { display: none !important; }
    .toolbar-brand {
      width: 100%;
      font-size: 14px;
      text-align: center;
      white-space: nowrap;
    }
    .toolbar-actions {
      display: grid;
      grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
      grid-template-areas:
        "column column"
        "demo image"
        "typography answer"
        "options edit"
        "print print";
      align-items: center;
      gap: 8px;
      flex: 1;
      min-width: 0;
      width: 100%;
      max-width: none;
      align-self: center;
    }
    .toolbar-group {
      display: flex;
      align-items: center;
      gap: 6px;
      min-width: 0;
      flex-wrap: wrap;
      padding: 5px 7px;
      border: 1px solid #e2e8f0;
      border-radius: 10px;
      background: #f8fafc;
    }
    .demo-menu-wrap { position: relative; grid-area: demo; }
    .demo-menu {
      position: static;
      display: flex;
      align-items: center;
      gap: 4px;
      padding: 0;
      border: 0;
      border-radius: 10px;
      background: transparent;
      box-shadow: none;
    }
    .demo-menu[hidden] { display: flex; }
    .demo-menu button {
      display: inline-flex;
      width: auto;
      padding: 7px 10px;
      border: 1px solid #cbd5e1;
      border-radius: 7px;
      background: white;
      color: var(--text);
      text-align: center;
      cursor: pointer;
      font-size: 12px;
    }
    .demo-menu button:hover { background: #eef2ff; color: var(--primary); }
    .demo-menu button.selected {
      border-color: var(--primary);
      background: #ede9fe;
      color: var(--primary);
      font-weight: 700;
    }
    .toolbar-group-label {
      color: var(--muted);
      font-size: 11px;
      white-space: nowrap;
      text-align: center;
    }
    .column-group { grid-area: column; justify-content: space-between; }
    .column-control {
      display: flex;
      align-items: center;
      gap: 4px;
    }
    .column-buttons { display: flex; gap: 3px; }
    .column-choice {
      width: 28px;
      height: 28px;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 2px;
      padding: 4px;
      border: 1px solid transparent;
      border-radius: 7px;
      background: #e5e7eb;
      cursor: pointer;
    }
    .column-choice:hover { border-color: #a5b4fc; }
    .column-choice.active {
      background: #ede9fe;
      border-color: var(--primary);
      box-shadow: 0 0 0 1px #c4b5fd;
    }
    .column-choice i {
      display: block;
      width: 5px;
      height: 15px;
      border-radius: 2px;
      background: #9ca3af;
    }
    .column-choice.active i { background: var(--primary); }
    .btn {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
      padding: 10px 18px;
      font-size: 14px;
      font-weight: 600;
      border-radius: 8px;
      border: none;
      cursor: pointer;
      text-decoration: none;
      text-align: center;
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
      .editing .paper-image {
        cursor: pointer;
      }
      .editing .paper-image.image-selected {
        outline: 2px solid #6366f1;
        outline-offset: 3px;
      }
      .editing .paper-image:hover {
        outline: 1px dashed #a5b4fc;
        outline-offset: 2px;
      }
    }
    .edit-hint { font-size: 12px; color: var(--muted); }
    .edit-hint[hidden] { display: none; }
    .preview-select {
      border: 1px solid #cbd5e1;
      border-radius: 8px;
      background: white;
      color: var(--text);
      padding: 9px 10px;
      font-size: 13px;
      min-width: 0;
      max-width: 100%;
      text-align: center;
      text-align-last: center;
    }
    .preview-range {
      width: 100px;
      accent-color: var(--primary);
    }
    .preview-number {
      width: 58px;
      border: 1px solid #cbd5e1;
      border-radius: 8px;
      padding: 8px 6px;
      font-size: 13px;
      text-align: center;
    }
    .demo-question {
      margin: 0;
      padding: 0;
      border: 0;
      background: transparent;
    }
    .image-group { grid-area: answer; }
    .image-group .preview-select { width: 82px; }
    .image-group .preview-range { width: 72px; }
    .typography-group { grid-area: typography; }
    .typography-group .preview-select { flex: 1 1 86px; width: 86px; }
    .answer-group { grid-area: image; }
    .print-options { grid-area: options; }
    #editBtn { grid-area: edit; }
    #printBtn { grid-area: print; }
    .desktop-toolbar .no-print-toolbar {
      display: grid;
      grid-template-columns: 1fr;
      gap: 8px;
    }
    .desktop-toolbar .toolbar-brand {
      width: 100%;
      padding-top: 0;
      text-align: center;
    }
    .desktop-toolbar .toolbar-actions {
      grid-template-columns: repeat(2, minmax(0, 1fr));
      width: 100%;
      max-width: none;
      justify-self: stretch;
    }
    .compact-toolbar .no-print-toolbar {
      display: grid;
      grid-template-columns: 1fr;
    }
    .compact-toolbar .toolbar-brand { width: 100%; }
    .compact-toolbar .toolbar-actions {
      grid-template-columns: repeat(2, minmax(0, 1fr));
      width: 100%;
      max-width: none;
      justify-self: stretch;
    }
    @media screen and (max-width: 700px) {
      .no-print-toolbar {
        display: grid;
        grid-template-columns: 1fr;
      }
      .toolbar-brand { width: 100%; }
      .toolbar-actions {
        grid-template-columns: repeat(2, minmax(0, 1fr));
        grid-template-areas:
          "column column"
          "demo image"
          "typography answer"
          "options edit"
          "print print";
        width: 100%;
        max-width: none;
        justify-self: stretch;
      }
    }
    @media screen and (max-width: 600px) {
      .toolbar-actions {
        grid-template-columns: 1fr;
        grid-template-areas:
          "demo"
          "column"
          "image"
          "typography"
          "answer"
          "options"
          "edit"
          "print";
      }
      .toolbar-group { width: 100%; justify-content: space-between; }
      .column-group { align-items: flex-start; flex-wrap: wrap; }
      .column-control { flex: 1 1 auto; justify-content: space-between; }
      .btn { justify-content: center; width: 100%; }
    }

    #quickFixBtn { grid-area: quick; }
    .quick-fix-panel { display: none; }
    .toolbar-actions.quick-fix-open .quick-fix-panel { display: contents; }
    .toolbar-actions {
      grid-template-areas:
        "column column"
        "demo quick"
        "print print";
    }
    .toolbar-actions.quick-fix-open {
      grid-template-areas:
        "column column"
        "demo quick"
        "typography image"
        "answer options"
        "edit edit"
        "print print";
    }
    @media screen and (max-width: 600px) {
      .toolbar-actions {
        grid-template-areas:
          "demo"
          "column"
          "quick"
          "print";
      }
      .toolbar-actions.quick-fix-open {
        grid-template-areas:
          "demo"
          "column"
          "quick"
          "typography"
          "image"
          "answer"
          "options"
          "edit"
          "print";
      }
    }

    /* The sheet *is* an A4 page: the same 210×297mm canvas the PDF export uses,
       the same 18pt at the head and 40pt down each side, and a foot of 18px.
       Same paper, same text width, so a line that wraps here wraps the same way
       in the PDF: the canvas on screen is what the printer produces. */
    .paper-sheet {
      width: ${_print.paperSize.widthCss};
      max-width: 100%;
      min-height: ${_print.paperSize.heightCss};
      margin: 0 auto;
      background: white;
      padding: 18pt ${_print.paperSize.sidePaddingPt.round()}pt 18px;
      border-radius: 8px;
      box-shadow: 0 4px 24px rgba(0,0,0,0.08);
      zoom: var(--paper-scale, 1);
      text-align: ${_print.textAlign.css};
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
    .header-note { font-size: ${_cssFontSize(12, fontStep)}; color: var(--muted); text-align: center; margin-top: 2px; }
    /* The optional branding band above the masthead. */
    .brand-header {
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 10px;
      padding-bottom: 6px;
      margin-bottom: 6px;
      border-bottom: 1px solid var(--border);
      text-align: left;
    }
    .brand-header-text {
      display: flex;
      flex-direction: column;
      font-size: ${_cssFontSize(11, fontStep)};
      color: var(--muted);
    }
    .brand-logo {
      max-height: 44px;
      max-width: 130px;
      object-fit: contain;
    }
    .brand-logo-row {
      display: flex;
      justify-content: center;
      margin-bottom: 4px;
    }
    .school-address {
      text-align: center;
      font-size: ${_cssFontSize(11, fontStep)};
      color: var(--muted);
      margin-bottom: 3px;
    }
    .student-info {
      display: flex;
      flex-wrap: wrap;
      justify-content: space-between;
      gap: 4px 14px;
      font-size: ${_cssFontSize(11, fontStep)};
      color: var(--muted);
      padding: 4px 0 2px;
    }
    .obtained-marks {
      text-align: right;
      font-size: ${_cssFontSize(11, fontStep)};
      color: var(--muted);
      padding: 2px 0;
    }
    .question-info {
      font-size: ${_cssFontSize(10, fontStep)};
      color: var(--muted);
      margin-top: 1px;
    }
    .important-star {
      color: #d97706;
      margin-right: 3px;
    }
    /* A fixed watermark repeats on every printed page. */
    .watermark {
      position: fixed;
      top: 50%;
      left: 50%;
      transform: translate(-50%, -50%) rotate(-32deg);
      font-size: 70px;
      font-weight: 800;
      color: rgba(15, 23, 42, 0.06);
      white-space: nowrap;
      pointer-events: none;
      z-index: 0;
      user-select: none;
    }
    .brand-footer {
      margin-top: 14pt;
      padding-top: 5px;
      border-top: 1px solid var(--border);
      text-align: center;
      font-size: ${_cssFontSize(10, fontStep)};
      color: var(--muted);
    }
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
    /* The CQ instruction rides inside the bar, on a line of its own between
       the two rules — the bar is the one band on the sheet that states what
       the paper wants, so the instruction belongs there rather than in a
       block of its own further down. */
    .meta-note {
      width: 100%;
      text-align: center;
      font-weight: 400;
      font-style: italic;
      font-size: ${_cssFontSize(12, fontStep)};
      padding: 0;
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
    /* Mixed papers make the MCQ block especially easy to scan: the dashed
       rules mark where that section starts and ends without boxing each item. */
    .mcq-section-separator.top {
      border-top: 1px dashed var(--border);
    }
    .mcq-section-separator.bottom {
      border-bottom: 1px dashed var(--border);
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
      margin-bottom: ${(10 + _print.questionGap).round()}px;
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
    .cq-grid {${cqLayout.mcqColumns > 1 ? '\n      margin-top: 5pt;\n      column-count: ${cqLayout.mcqColumns};\n      column-gap: ${_print.columnGap.round()}px;\n      column-rule: ${_print.columnDivider ? '1px solid var(--border)' : 'none'};' : ''}
    }
    /* A merged CQ + short-question run: one continuous pair of columns, so the
       short questions begin exactly where the creative questions run out —
       mid-column or at the head of the next one. The gap above the run sits on
       the container, not on the heading inside it, so both columns start level. */
    .flow-grid {${mergeCqAndShort ? '\n      margin-top: 5pt;\n      column-count: 2;\n      column-gap: ${_print.columnGap.round()}px;\n      column-rule: ${_print.columnDivider ? '1px solid var(--border)' : 'none'};' : ''}
    }
    .mcq-grid {${mcqLayout.mcqColumns > 1 ? '\n      margin-top: 5pt;\n      column-count: ${mcqLayout.mcqColumns};\n      column-gap: ${_print.columnGap.round()}px;\n      column-rule: ${_print.columnDivider ? '1px solid var(--border)' : 'none'};' : ''}
    }
    /* The card is the question and nothing else: no padding, no margin of its
       own and no rule under it. */
    .mcq-card {
      ${_print.questionGap > 0 ? 'margin-bottom: ${_print.questionGap.round()}px;' : ''}
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
      grid-template-columns: ${mcqLayout == QuestionLayout.single ? '1fr 1fr' : '1fr'};
      /* No gap between the rows of options, so they sit as one tight stack
         under their question. The columns keep a small gutter, 6px, and the
         indent under the question number is 8px. Both are read back by the
         fitting script, which measures the room with `paddingLeft` and the
         gutter with `columnGap`, so they may be changed here alone. */
      gap: 0 6px;
      padding-left: 6px;
      font-size: ${_cssFontSize(15, fontStep)};
    }
    .mcq-answer-sheet {
      break-before: page;
      page-break-before: always;
      margin-top: 18pt;
      border-top: 1px solid var(--border);
      padding-top: 12pt;
    }
    .answer-sheet-title {
      text-align: center;
      font-size: ${_cssFontSize(18, fontStep)};
      font-weight: 700;
    }
    .omr-grid {
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      gap: 14px;
    }
    .omr-column {
      border: 1px solid #cbd5e1;
      padding: 8px 10px;
    }
    .omr-row {
      display: flex;
      align-items: center;
      gap: 8px;
      min-height: 28px;
      font-size: ${_cssFontSize(13, fontStep)};
    }
    .omr-number {
      width: 24px;
      font-weight: 700;
    }
    .omr-bubble {
      width: 22px;
      height: 22px;
      border: 1px solid #334155;
      border-radius: 50%;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      font-size: 11px;
    }
    .serial-answer-table {
      width: auto;
      max-width: none;
      display: table;
      margin-left: auto;
      margin-right: auto;
      border-collapse: collapse;
      table-layout: fixed;
      font-size: ${_cssFontSize(13, fontStep)};
    }
    .serial-answer-table th,
    .serial-answer-table td {
      border: 1px solid #94a3b8;
      height: 6.5mm;
      width: 6.5mm;
      min-width: 6.5mm;
      padding: 3px 2px;
      text-align: center;
    }
    .serial-answer-table th { font-weight: 700; }
    .serial-answer-table td { height: 6.5mm; }
    .serial-answer-table + .serial-answer-table { margin-top: 8px; }
    @media screen and (max-width: 700px) {
      .omr-grid { grid-template-columns: repeat(2, 1fr); }
    }
    .rq-grid {${rqLayout.mcqColumns > 1 ? '\n      margin-top: 5pt;\n      column-count: ${rqLayout.mcqColumns};\n      column-gap: ${_print.columnGap.round()}px;\n      column-rule: ${_print.columnDivider ? '1px solid var(--border)' : 'none'};' : ''}
    }
    /* Short questions are a single line each, as in the PDF: no padding and no
       gap of their own — the line box is the whole of the row, and the mark is
       held at the right edge by the flex row. A one-line row stays whole:
       breaking inside it would gain nothing for the column balance and could cut
       a question in half. */
    .rq-item {
      display: flex;
      justify-content: space-between;
      align-items: flex-start;
      gap: 8px;
      font-size: ${_cssFontSize(15, fontStep)};
      ${_print.questionGap > 0 ? 'margin-bottom: ${_print.questionGap.round()}px;' : ''}
      page-break-inside: avoid;
      break-inside: avoid;
    }
    .rq-content {
      flex: 1;
    }
    .rq-mark { font-weight: 400; white-space: nowrap; color: var(--muted); }

    @page { size: ${_print.paperSize.label}; margin: $pageMargin;$pageNumberRule }

    @media print {
      body { background: white; padding: 0; }
      .no-print-toolbar, #imageEditorFloat { display: none !important; }
      /* No margin on the page box: the sheet carries the page's own margins, so
         a printed page breaks where the exported PDF page breaks. */
      .paper-sheet {
        width: auto;
        max-width: none;
        min-height: 0;
        box-shadow: none;
        border-radius: 0;
        padding: 18pt ${_print.paperSize.sidePaddingPt.round()}pt 18px;
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
  <style id="runtimePrintStyle">@page { size: ${_print.paperSize.label} portrait; margin: $pageMargin;$pageNumberRule }</style>
</head>
<body class="${compactToolbar ? 'compact-toolbar' : desktopMode ? 'desktop-toolbar' : ''}${includeToolbar ? '' : ' toolbar-hidden'}${_print.editingMode ? ' editing' : ''}">
  <div class="no-print-toolbar">
    <div class="toolbar-brand"><b>Pi-QBank</b> প্রশ্নপত্র প্রিভিউ</div>
    <div class="toolbar-actions">
      <span class="edit-hint" id="editHint"${_print.editingMode ? '' : ' hidden'}>যা লিখবেন সেটাই প্রিন্ট হবে</span>
      <div class="toolbar-group demo-menu-wrap">
        <button class="btn btn-outline" id="demoQuestionBtn">➕ ডেমো প্রশ্ন</button>
        <div class="demo-menu" id="demoQuestionMenu">
          <button data-demo-type="cq">CQ</button>
          <button data-demo-type="mcq">MCQ</button>
          <button data-demo-type="rq">RQ</button>
        </div>
      </div>
      <div class="toolbar-group column-group">
        <span class="toolbar-group-label">কলাম</span>
        <div class="column-control"><span class="toolbar-group-label">CQ</span><div class="column-buttons">
          <button class="column-choice ${cqLayout.mcqColumns == 1 ? 'active' : ''}" data-column-kind="cq" data-columns="1" title="CQ এক কলাম"><i></i></button>
          <button class="column-choice ${cqLayout.mcqColumns == 2 ? 'active' : ''}" data-column-kind="cq" data-columns="2" title="CQ দুই কলাম"><i></i><i></i></button>
          <button class="column-choice ${cqLayout.mcqColumns == 3 ? 'active' : ''}" data-column-kind="cq" data-columns="3" title="CQ তিন কলাম"><i></i><i></i><i></i></button>
        </div></div>
        <div class="column-control"><span class="toolbar-group-label">MCQ</span><div class="column-buttons">
          <button class="column-choice ${mcqLayout.mcqColumns == 1 ? 'active' : ''}" data-column-kind="mcq" data-columns="1" title="MCQ এক কলাম"><i></i></button>
          <button class="column-choice ${mcqLayout.mcqColumns == 2 ? 'active' : ''}" data-column-kind="mcq" data-columns="2" title="MCQ দুই কলাম"><i></i><i></i></button>
          <button class="column-choice ${mcqLayout.mcqColumns == 3 ? 'active' : ''}" data-column-kind="mcq" data-columns="3" title="MCQ তিন কলাম"><i></i><i></i><i></i></button>
        </div></div>
        <div class="column-control"><span class="toolbar-group-label">RQ</span><div class="column-buttons">
          <button class="column-choice ${rqLayout.mcqColumns == 1 ? 'active' : ''}" data-column-kind="rq" data-columns="1" title="RQ এক কলাম"><i></i></button>
          <button class="column-choice ${rqLayout.mcqColumns == 2 ? 'active' : ''}" data-column-kind="rq" data-columns="2" title="RQ দুই কলাম"><i></i><i></i></button>
          <button class="column-choice ${rqLayout.mcqColumns == 3 ? 'active' : ''}" data-column-kind="rq" data-columns="3" title="RQ তিন কলাম"><i></i><i></i><i></i></button>
        </div></div>
      </div>
      <button class="btn btn-outline quick-fix-toggle" id="quickFixBtn" aria-expanded="false">⚡ Quick Fix</button>
      <div class="quick-fix-panel">
      <div class="toolbar-group image-group">
        <span class="toolbar-group-label">ছবির আকার</span>
        <select class="preview-select" id="previewImagePreset" aria-label="ছবির আকার">
          $previewImageOptions
        </select>
        <input class="preview-range" id="imageSizeEditor" type="range" min="25" max="200" step="1" value="100" disabled aria-label="ছবির আকার শতাংশ">
        <input class="preview-number" id="imageSizeCustom" type="number" min="25" max="200" step="1" value="100" disabled aria-label="ছবির আকার শতাংশ">
        <span>%</span>
      </div>
      <div class="toolbar-group typography-group">
        <span class="toolbar-group-label">লেখার আকার</span>
        <select class="preview-select" id="previewFontStep" aria-label="লেখার আকার">
          $previewFontStepOptions
        </select>
        <span class="toolbar-group-label">ফন্ট</span>
        <select class="preview-select" id="previewFont" aria-label="ফন্ট">
          $previewFontOptions
        </select>
      </div>
      $previewAnswerSheetControl
      <div class="toolbar-group print-options">
        <select class="preview-select" id="printPaperSize" aria-label="কাগজের আকার">
          <option value="A4" ${_print.paperSize == PaperSize.a4 ? 'selected' : ''}>A4</option>
          <option value="Letter" ${_print.paperSize == PaperSize.letter ? 'selected' : ''}>Letter</option>
          <option value="Legal" ${_print.paperSize == PaperSize.legal ? 'selected' : ''}>Legal</option>
          <option value="A3">A3</option>
          <option value="A5" ${_print.paperSize == PaperSize.a5 ? 'selected' : ''}>A5</option>
        </select>
        <select class="preview-select" id="printOrientation" aria-label="প্রিন্ট দিক">
          <option value="portrait">পোর্ট্রেট</option>
          <option value="landscape">ল্যান্ডস্কেপ</option>
        </select>
        <select class="preview-select" id="printScale" aria-label="প্রিন্ট স্কেল">
          <option value="50">50%</option>
          <option value="75">75%</option>
          <option value="90">90%</option>
          <option value="100" selected>100%</option>
          <option value="110">110%</option>
          <option value="125">125%</option>
          <option value="150">150%</option>
        </select>
        <select class="preview-select" id="printMargin" aria-label="প্রিন্ট মার্জিন">
          <option value="0">মার্জিন নেই</option>
          <option value="8mm">স্বাভাবিক মার্জিন</option>
          <option value="15mm">বড় মার্জিন</option>
        </select>
      </div>
      <button class="btn btn-outline" id="editBtn">${_print.editingMode ? '✅ এডিট শেষ' : '✏️ লাইভ এডিট'}</button>
      </div>
      <button class="btn btn-primary" id="printBtn">🖨️ প্রিন্ট করুন</button>
    </div>
  </div>

  <div class="paper-sheet"${_print.editingMode ? ' contenteditable="true"' : ''}>
    ${_print.showWatermark && _print.watermarkText.trim().isNotEmpty ? '<div class="watermark">${_escapeXml(_print.watermarkText.trim())}</div>' : ''}
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
        imageBytes: imageBytes,
        cqInstruction: cqInstruction,
        mcqAnswerSheetStyle: mcqAnswerSheetStyle,
      );
    }

    buffer.write('''
  </div>

  <div id="imageEditorFloat" style="display:none; position:fixed; bottom:16px; left:50%; transform:translateX(-50%); background:white; border:1px solid #cbd5e1; border-radius:10px; padding:8px 14px; box-shadow:0 4px 16px rgba(0,0,0,0.18); z-index:1000; align-items:center; gap:8px; font-size:13px;">
    <span style="color:#475569; font-weight:600;">ছবির আকার:</span>
    <input type="range" id="floatImageSize" min="25" max="200" step="1" value="100" style="width:120px;">
    <input type="number" id="floatImageSizeCustom" min="25" max="200" step="1" value="100" style="width:52px; text-align:center; border:1px solid #cbd5e1; border-radius:6px; padding:4px;">
    <span>%</span>
    <input type="text" id="floatImageUrl" placeholder="নতুন ছবির URL" aria-label="নতুন ছবির URL" style="width:190px; border:1px solid #cbd5e1; border-radius:6px; padding:4px 6px; font-size:12px;">
    <button id="floatImageApply" title="নতুন ছবি বসান" style="background:#e0e7ff; border:1px solid #c7d2fe; border-radius:6px; padding:4px 8px; cursor:pointer; color:#4338ca;">বসান</button>
    <button id="floatImageDelete" title="নির্বাচিত ছবি মুছুন" style="background:#fee2e2; border:1px solid #fecaca; border-radius:6px; padding:4px 8px; cursor:pointer; color:#dc2626;">🗑️</button>
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
        if (!on) {
          if (selectedImage) {
            selectedImage.classList.remove('image-selected');
            selectedImage = null;
          }
          var floatEditor = document.getElementById('imageEditorFloat');
          if (floatEditor) floatEditor.style.display = 'none';
          var floatUrl = document.getElementById('floatImageUrl');
          if (floatUrl) { floatUrl.disabled = true; floatUrl.value = ''; }
        }
        var imageSize = document.getElementById('imageSizeEditor');
        var imageSizeCustom = document.getElementById('imageSizeCustom');
        if (imageSize) imageSize.disabled = !on || !selectedImage;
        if (imageSizeCustom) imageSizeCustom.disabled = !on || !selectedImage;
      }

      function isEditing() {
        return document.body.classList.contains('editing');
      }

      function formatSelection(command, value) {
        if (!isEditing()) return;
        document.execCommand(command, false, value || null);
        relayoutSoon();
      }

      function changeSelectionFontSize(delta) {
        if (!isEditing()) return;
        var selection = window.getSelection();
        if (!selection || selection.rangeCount === 0 || selection.isCollapsed) return;
        var range = selection.getRangeAt(0);
        var parent = range.commonAncestorContainer.nodeType === 3
            ? range.commonAncestorContainer.parentElement
            : range.commonAncestorContainer;
        var current = parseFloat(getComputedStyle(parent).fontSize) || 16;
        var span = document.createElement('span');
        span.style.fontSize = Math.max(8, Math.min(48, current + Number(delta || 0))) + 'px';
        try {
          range.surroundContents(span);
        } catch (error) {
          document.execCommand('fontSize', false, delta > 0 ? '5' : '2');
        }
        relayoutSoon();
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

      var selectedImage = null;
      var selectedDemoType = 'cq';

      function nextQuestionNumber() {
        var set = document.querySelector('.paper-set');
        if (!set) return 1;
        var nodes = set.querySelectorAll('*');
        var max = 0;
        var bengaliDigits = '০১২৩৪৫৬৭৮৯';
        var numberPattern = /([0-9০-৯]+)\\s*[.)]/g;
        for (var i = 0; i < nodes.length; i++) {
          var text = nodes[i].textContent || '';
          var match;
          numberPattern.lastIndex = 0;
          while ((match = numberPattern.exec(text)) !== null) {
            var latin = match[1].replace(/[০-৯]/g, function (digit) {
              return String(bengaliDigits.indexOf(digit));
            });
            max = Math.max(max, Number(latin) || 0);
          }
        }
        return max + 1;
      }

      function addDemoQuestion(type) {
        var set = document.querySelector('.paper-set');
        if (!set) return;
        var demo = document.createElement('div');
        demo.className = 'demo-question';
        var number = nextQuestionNumber();
        if (type === 'mcq') {
          demo.innerHTML = '<b>' + number + '. </b>নিচের কোনটি সঠিক?<br>' +
              '<span>(ক) প্রথম বিকল্প</span> &nbsp; ' +
              '<span>(খ) দ্বিতীয় বিকল্প</span> &nbsp; ' +
              '<span>(গ) তৃতীয় বিকল্প</span> &nbsp; ' +
              '<span>(ঘ) চতুর্থ বিকল্প</span>';
        } else if (type === 'rq') {
          demo.innerHTML = '<b>' + number + '. </b>সংক্ষেপে উত্তর দাও।';
        } else {
          demo.innerHTML = '<b>' + number + '. </b>এখানে উদ্দীপক লিখুন।<br>' +
              '<span>(ক) প্রথম উপ-প্রশ্ন লিখুন।</span><br>' +
              '<span>(খ) দ্বিতীয় উপ-প্রশ্ন লিখুন।</span><br>' +
              '<span>(গ) তৃতীয় উপ-প্রশ্ন লিখুন।</span><br>' +
              '<span>(ঘ) চতুর্থ উপ-প্রশ্ন লিখুন।</span>';
        }
        var answerSheet = set.querySelector('.mcq-answer-sheet');
        if (answerSheet) set.insertBefore(demo, answerSheet);
        else set.appendChild(demo);
        document.getElementById('demoQuestionMenu').hidden = true;
        setEditing(true);
        demo.focus();
      }

      var pageNumbersOn = ${_print.pageNumbers ? 'true' : 'false'};

      function setPrintOptions() {
        var paper = document.getElementById('printPaperSize');
        var orientation = document.getElementById('printOrientation');
        var scale = document.getElementById('printScale');
        var margin = document.getElementById('printMargin');
        var style = document.getElementById('runtimePrintStyle');
        if (!style) return;
        var paperSize = paper ? paper.value : 'A4';
        var paperScale = scale ? Number(scale.value) : 100;
        document.documentElement.dataset.paperSize = paperSize;
        document.documentElement.style.setProperty('--paper-scale',
            String(paperScale / 100));
        var pageMargin = margin ? margin.value : '0';
        if (pageNumbersOn && pageMargin === '0') pageMargin = '0 0 10mm 0';
        style.textContent = '@page { size: ' + paperSize + ' ' +
            (orientation ? orientation.value : 'portrait') + '; margin: ' +
            pageMargin + ';' + (pageNumbersOn
                ? ' @bottom-center { content: "পৃষ্ঠা " counter(page, bengali); font-size: 9pt; color: #64748b; }'
                : '') + ' }';
      }

      function setPreviewImagePreset(value) {
        var scales = { hidden: 0, small: 0.72, medium: 1, large: 1.35 };
        var scale = Object.prototype.hasOwnProperty.call(scales, value)
            ? scales[value] : 1;
        var images = document.querySelectorAll('.paper-image');
        for (var i = 0; i < images.length; i++) {
          var image = images[i];
          if (scale === 0) {
            image.style.display = 'none';
            continue;
          }
          image.style.display = 'block';
          image.style.maxWidth = (Number(image.dataset.baseMaxWidth) * scale) +
              image.dataset.baseUnit;
          image.style.maxHeight = (Number(image.dataset.baseMaxHeight) * scale) +
              image.dataset.baseUnit;
        }
        relayoutSoon();
      }

      function setPreviewFontStep(value) {
        var scale = 1 + (Number(value) || 0) * 0.05;
        var sheets = document.querySelectorAll('.paper-sheet');
        for (var i = 0; i < sheets.length; i++) sheets[i].style.zoom = String(scale);
        relayoutSoon();
      }

      function setPreviewFont(value) {
        var sheets = document.querySelectorAll('.paper-sheet');
        for (var i = 0; i < sheets.length; i++) sheets[i].style.fontFamily = value;
        relayoutSoon();
      }

      function rebuildManualAnswerSheet() {
        var countInput = document.getElementById('answerItemCount');
        var count = countInput ? Math.max(1, Math.min(200, Number(countInput.value) || 1)) : 0;
        var sheets = document.querySelectorAll('[data-manual-answer-sheet="true"]');
        var letters = ['ক', 'খ', 'গ', 'ঘ'];
        for (var s = 0; s < sheets.length; s++) {
          var sheet = sheets[s];
          var omrGrid = sheet.querySelector('.omr-grid');
          if (omrGrid) {
            omrGrid.innerHTML = '';
            var columns = [[], [], [], []];
            var rowsPerColumn = Math.ceil(count / 4);
            for (var n = 1; n <= count; n++) {
              columns[Math.min(3, Math.floor((n - 1) / rowsPerColumn))].push(n);
            }
            for (var c = 0; c < columns.length; c++) {
              var column = document.createElement('div');
              column.className = 'omr-column';
              for (var r = 0; r < columns[c].length; r++) {
                var row = document.createElement('div');
                row.className = 'omr-row';
                row.innerHTML = '<span class="omr-number">' + columns[c][r] + '</span>' +
                    letters.map(function (letter) {
                      return '<span class="omr-bubble">' + letter + '</span>';
                    }).join('');
                column.appendChild(row);
              }
              omrGrid.appendChild(column);
            }
          }
          var serial = sheet.querySelector('.answer-sheet-serial');
          if (serial) {
            serial.innerHTML = '';
            for (var start = 1; start <= count; start += 30) {
              var end = Math.min(count, start + 29);
              var table = document.createElement('table');
              table.className = 'serial-answer-table';
              table.style.width = ((end - start) * 6.5) + 'mm';
              table.innerHTML = '<tbody><tr></tr><tr class="serial-answer-row"></tr></tbody>';
              var heads = table.querySelector('tr');
              var answers = table.querySelector('.serial-answer-row');
              for (var number = start; number <= end; number++) {
                var head = document.createElement('th');
                head.textContent = number;
                heads.appendChild(head);
                answers.appendChild(document.createElement('td'));
              }
              serial.appendChild(table);
            }
          }
        }
      }

      function setPreviewAnswerSheet(value) {
        rebuildManualAnswerSheet();
        var sheets = document.querySelectorAll('.mcq-answer-sheet');
        for (var i = 0; i < sheets.length; i++) {
          var sheet = sheets[i];
          sheet.style.display = value === 'none' ? 'none' : '';
          var variants = sheet.querySelectorAll('[data-answer-style]');
          for (var j = 0; j < variants.length; j++) {
            variants[j].style.display = variants[j].getAttribute('data-answer-style') === value
                ? '' : 'none';
          }
        }
        relayoutSoon();
      }

      function setPreviewColumns(kind, value) {
        var count = Math.max(1, Math.min(3, Number(value) || 1));
        var grids = document.querySelectorAll('.' + kind + '-grid');
        for (var i = 0; i < grids.length; i++) {
          grids[i].style.columnCount = String(count);
        }
        // CQ and RQ can share one continuous two-column flow. In that case
        // either control updates the shared flow instead of doing nothing.
        if ((kind === 'cq' || kind === 'rq') &&
            document.querySelector('.flow-grid')) {
          document.querySelector('.flow-grid').style.columnCount = String(count);
        }
      }

      function removeSelectedImage() {
        if (!selectedImage) return;
        selectedImage.remove();
        selectedImage = null;
        var imageSize = document.getElementById('imageSizeEditor');
        var imageSizeCustom = document.getElementById('imageSizeCustom');
        if (imageSize) imageSize.disabled = true;
        if (imageSizeCustom) imageSizeCustom.disabled = true;
        var floatEditor = document.getElementById('imageEditorFloat');
        if (floatEditor) floatEditor.style.display = 'none';
        var floatUrl = document.getElementById('floatImageUrl');
        if (floatUrl) { floatUrl.disabled = true; floatUrl.value = ''; }
        relayoutSoon();
      }
      function selectImage(image) {
        if (!isEditing()) return;
        if (selectedImage) selectedImage.classList.remove('image-selected');
        selectedImage = image;
        selectedImage.classList.add('image-selected');
        var imageSize = document.getElementById('imageSizeEditor');
        var imageSizeCustom = document.getElementById('imageSizeCustom');
        if (imageSize) {
          imageSize.disabled = false;
          imageSize.value = '100';
        }
        if (imageSizeCustom) {
          imageSizeCustom.disabled = false;
          imageSizeCustom.value = '100';
        }
        var floatEditor = document.getElementById('imageEditorFloat');
        var floatSize = document.getElementById('floatImageSize');
        var floatCustom = document.getElementById('floatImageSizeCustom');
        if (floatEditor) floatEditor.style.display = 'flex';
        if (floatSize) { floatSize.disabled = false; floatSize.value = '100'; }
        if (floatCustom) { floatCustom.disabled = false; floatCustom.value = '100'; }
        var floatUrl = document.getElementById('floatImageUrl');
        if (floatUrl) { floatUrl.disabled = false; floatUrl.value = ''; }
      }

      function resizeSelectedImage(value) {
        if (!selectedImage || value === '') return;
        var percent = Math.max(25, Math.min(200, Number(value) || 100));
        selectedImage.style.maxWidth = 'none';
        selectedImage.style.maxHeight = 'none';
        selectedImage.style.width = percent + '%';
        selectedImage.style.height = 'auto';
        var imageSize = document.getElementById('imageSizeEditor');
        var imageSizeCustom = document.getElementById('imageSizeCustom');
        if (imageSize) imageSize.value = String(percent);
        if (imageSizeCustom) imageSizeCustom.value = String(percent);
        var floatSize = document.getElementById('floatImageSize');
        var floatCustom = document.getElementById('floatImageSizeCustom');
        if (floatSize) floatSize.value = String(percent);
        if (floatCustom) floatCustom.value = String(percent);
      }

      function wireEditor() {
        // The browser edition renders this same toolbar as a native settings
        // rail outside the iframe. Keep one source of truth by routing those
        // commands through the editor functions below.
        window.addEventListener('message', function (event) {
          var data = event.data || {};
          if (!data || data.source !== 'pi-qbank-web-settings') return;
          if (data.action === 'demo') {
            addDemoQuestion(data.value || 'cq');
          } else if (data.action === 'columns') {
            var choices = document.querySelectorAll('[data-column-kind="' + data.kind + '"]');
            for (var ci = 0; ci < choices.length; ci++) {
              var choice = choices[ci];
              var active = choice.getAttribute('data-columns') === String(data.value);
              choice.classList.toggle('active', active);
            }
            setPreviewColumns(data.kind, data.value);
          } else if (data.action === 'quickFix') {
            var quick = document.getElementById('quickFixBtn');
            if (quick) quick.click();
          } else if (data.action === 'edit') {
            var edit = document.getElementById('editBtn');
            if (edit) edit.click();
          } else if (data.action === 'print') {
            var print = document.getElementById('printBtn');
            if (print) print.click();
          } else if (data.action === 'imagePreset') {
            setPreviewImagePreset(data.value || 'small');
          } else if (data.action === 'imageSize') {
            resizeSelectedImage(data.value || 100);
          } else if (data.action === 'fontStep') {
            setPreviewFontStep(data.value || 0);
          } else if (data.action === 'font') {
            setPreviewFont(data.value || '');
          } else if (data.action === 'answerSheet') {
            setPreviewAnswerSheet(data.value || 'none');
          } else if (data.action === 'answerCount') {
            var answerCount = document.getElementById('answerItemCount');
            if (answerCount) {
              answerCount.value = String(data.value || 30);
              answerCount.dispatchEvent(new Event('input'));
            }
          } else if (data.action === 'format') {
            formatSelection(data.command, data.value);
          } else if (data.action === 'fontSizeDelta') {
            changeSelectionFontSize(data.value);
          } else if (data.action === 'toggle') {
            var toggles = document.querySelectorAll(data.selector || '');
            for (var ti = 0; ti < toggles.length; ti++) {
              toggles[ti].style.display = data.value ? '' : 'none';
            }
          } else if (data.action === 'printOption') {
            var option = document.getElementById(data.id);
            if (option) option.value = data.value;
            setPrintOptions();
          }
        });
        var quickFixButton = document.getElementById('quickFixBtn');
        var toolbarActions = document.querySelector('.toolbar-actions');
        if (quickFixButton && toolbarActions) {
          quickFixButton.addEventListener('click', function () {
            var open = toolbarActions.classList.toggle('quick-fix-open');
            quickFixButton.setAttribute('aria-expanded', String(open));
            quickFixButton.textContent = open ? '✕ Close Quick Fix' : '⚡ Quick Fix';
          });
        }
        var button = document.getElementById('editBtn');
        if (button) {
          button.addEventListener('click', function () {
            setEditing(!isEditing());
          });
        }
        var demoButton = document.getElementById('demoQuestionBtn');
        var demoMenu = document.getElementById('demoQuestionMenu');
        if (demoButton) demoButton.addEventListener('click', function () {
          addDemoQuestion(selectedDemoType);
        });
        if (demoMenu) {
          var demoChoices = demoMenu.querySelectorAll('[data-demo-type]');
          for (var d = 0; d < demoChoices.length; d++) {
            demoChoices[d].addEventListener('click', function () {
              selectedDemoType = this.getAttribute('data-demo-type');
              for (var option = 0; option < demoChoices.length; option++) {
                demoChoices[option].classList.toggle(
                    'selected', demoChoices[option] === this);
              }
            });
          }
          var defaultDemoChoice = demoMenu.querySelector('[data-demo-type="cq"]');
          if (defaultDemoChoice) defaultDemoChoice.classList.add('selected');
        }
        var orientation = document.getElementById('printOrientation');
        var paper = document.getElementById('printPaperSize');
        var scale = document.getElementById('printScale');
        var margin = document.getElementById('printMargin');
        if (paper) paper.addEventListener('change', setPrintOptions);
        if (orientation) orientation.addEventListener('change', setPrintOptions);
        if (scale) scale.addEventListener('change', setPrintOptions);
        if (margin) margin.addEventListener('change', setPrintOptions);
        var imagePreset = document.getElementById('previewImagePreset');
        if (imagePreset) imagePreset.addEventListener('change', function () {
          setPreviewImagePreset(imagePreset.value);
        });
        var fontStep = document.getElementById('previewFontStep');
        if (fontStep) fontStep.addEventListener('change', function () {
          setPreviewFontStep(fontStep.value);
        });
        var font = document.getElementById('previewFont');
        if (font) font.addEventListener('change', function () {
          setPreviewFont(font.value);
        });
        var answerSheet = document.getElementById('previewAnswerSheet');
        if (answerSheet) answerSheet.addEventListener('change', function () {
          setPreviewAnswerSheet(answerSheet.value);
        });
        var answerItemCount = document.getElementById('answerItemCount');
        if (answerItemCount) answerItemCount.addEventListener('input', function () {
          rebuildManualAnswerSheet();
          if (answerSheet) setPreviewAnswerSheet(answerSheet.value);
        });
        var columnChoices = document.querySelectorAll('[data-column-kind]');
        for (var c = 0; c < columnChoices.length; c++) {
          columnChoices[c].addEventListener('click', function () {
            var kind = this.getAttribute('data-column-kind');
            var count = this.getAttribute('data-columns');
            var siblings = this.parentNode.querySelectorAll('.column-choice');
            for (var s = 0; s < siblings.length; s++) siblings[s].classList.remove('active');
            this.classList.add('active');
            setPreviewColumns(kind, count);
          });
        }
        var imageSize = document.getElementById('imageSizeEditor');
        if (imageSize) imageSize.addEventListener('input', function () {
          resizeSelectedImage(imageSize.value);
        });
        var imageSizeCustom = document.getElementById('imageSizeCustom');
        if (imageSizeCustom) imageSizeCustom.addEventListener('input', function () {
          resizeSelectedImage(imageSizeCustom.value);
        });
        var floatImageSize = document.getElementById('floatImageSize');
        if (floatImageSize) floatImageSize.addEventListener('input', function () {
          resizeSelectedImage(floatImageSize.value);
          var fc = document.getElementById('floatImageSizeCustom');
          if (fc) fc.value = floatImageSize.value;
        });
        var floatImageSizeCustom = document.getElementById('floatImageSizeCustom');
        if (floatImageSizeCustom) floatImageSizeCustom.addEventListener('input', function () {
          resizeSelectedImage(floatImageSizeCustom.value);
          var fr = document.getElementById('floatImageSize');
          if (fr) fr.value = floatImageSizeCustom.value;
        });
        var floatImageDelete = document.getElementById('floatImageDelete');
        if (floatImageDelete) floatImageDelete.addEventListener('click', function () {
          removeSelectedImage();
        });
        var floatImageApply = document.getElementById('floatImageApply');
        var floatImageUrl = document.getElementById('floatImageUrl');
        function applyImageUrl() {
          if (!selectedImage || !floatImageUrl) return;
          var next = floatImageUrl.value.trim();
          if (!next) return;
          selectedImage.setAttribute('src', next);
          selectedImage.style.maxWidth = 'none';
          selectedImage.style.maxHeight = 'none';
          floatImageUrl.value = '';
          relayoutSoon();
        }
        if (floatImageApply) floatImageApply.addEventListener('click', applyImageUrl);
        if (floatImageUrl) floatImageUrl.addEventListener('keydown', function (event) {
          if (event.key === 'Enter') { applyImageUrl(); event.preventDefault(); }
        });
        document.addEventListener('click', function (event) {
          var image = event.target;
          if (image && image.classList && image.classList.contains('paper-image')) {
            selectImage(image);
          }
          var menu = document.getElementById('demoQuestionMenu');
          var demoButton = document.getElementById('demoQuestionBtn');
          if (menu && !menu.hidden && image !== demoButton &&
              !(image && image.closest && image.closest('#demoQuestionMenu'))) {
            menu.hidden = true;
          }
        });
        // Double-clicking an image jumps to the replacement field, so swapping
        // the picture is one click away instead of hidden in the toolbar.
        document.addEventListener('dblclick', function (event) {
          var image = event.target;
          if (image && image.classList && image.classList.contains('paper-image') && isEditing()) {
            selectImage(image);
            var urlInput = document.getElementById('floatImageUrl');
            if (urlInput) urlInput.focus();
          }
        });
        // One listener on the document rather than one per sheet: a split
        // makes a sheet that was not there when this ran, and the delegate does
        // not care which sheet the typing landed in.
        document.addEventListener('input', function (event) {
          var node = event.target;
          if (node && node.closest && node.closest('.paper-sheet')) relayoutSoon();
        });
        // Delete/Backspace removes the selected image as one unit, so an
        // image that no longer belongs is gone with a single keypress instead
        // of leaving a stray cursor behind.
        document.addEventListener('keydown', function (event) {
          if (!isEditing() || !selectedImage) return;
          if (event.key === 'Delete' || event.key === 'Backspace') {
            removeSelectedImage();
            event.preventDefault();
          }
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

      /* Print the current HTML page, including any live edits. */
      var printBtn = document.getElementById('printBtn');
      if (printBtn) {
        printBtn.addEventListener('click', function () {
          window.print();
        });
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
    Map<String, Uint8List>? imageBytes,
    String cqInstruction = '',
    required McqAnswerSheetStyle mcqAnswerSheetStyle,
  }) {
    final logo = _print.showLogo && _print.logoDataUri.trim().isNotEmpty
        ? '<img class="brand-logo" src="${_print.logoDataUri}" alt="লোগো">'
        : '';
    final headerAddress =
        _print.showAddress && _print.address.trim().isNotEmpty
            ? '<span>${_escapeXml(_print.address.trim())}</span>'
            : '';
    // The masthead already carries the school name; the band is the letterhead
    // — a logo and the address — so it does not repeat it.
    final brandHeader = _print.showHeader && (logo.isNotEmpty || headerAddress.isNotEmpty)
        ? '<div class="brand-header">$logo'
            '${headerAddress.isNotEmpty ? '<div class="brand-header-text">$headerAddress</div>' : ''}'
            '</div>'
        : logo.isNotEmpty
            ? '<div class="brand-logo-row">$logo</div>'
            : '';
    final addressLine = _print.showAddress &&
            _print.address.trim().isNotEmpty &&
            !_print.showHeader
        ? '<div class="school-address">${_escapeXml(_print.address.trim())}</div>'
        : '';
    final footerText = _print.showAddress && _print.address.trim().isNotEmpty
        ? _print.address.trim()
        : (_print.showSchool ? schoolName.trim() : '');
    final footerBand = _print.showFooter && footerText.isNotEmpty
        ? '<div class="brand-footer">${_escapeXml(footerText)}</div>'
        : '';

    buffer.write('''
    <div class="paper-set">
      <div class="set-head">
        $brandHeader
        ${_print.showSchool && schoolName.trim().isNotEmpty ? '<div class="school-title">${_escapeXml(schoolName)}</div>' : ''}
        $addressLine
        ${_print.showExam && examName.trim().isNotEmpty ? '<div class="exam-title">${_escapeXml(examName)}</div>' : ''}
        ${_print.headerNote.trim().isNotEmpty ? '<div class="header-note">${_escapeXml(_print.headerNote.trim())}</div>' : ''}

        <div class="meta-bar">
          ${_print.showSet && setLabel.isNotEmpty ? '<div>সেট: ${_escapeXml(setLabel)}</div>' : ''}
          ${_print.showSubject ? '<div>বিষয়: ${_escapeXml(subject)}</div>' : ''}
          ${_print.showClass ? '<div>শ্রেণি: ${_escapeXml(className)}</div>' : ''}
          <div>সময়: ${_escapeXml(time)}</div>
          <div>পূর্ণমান: ${_escapeXml(totalMarks)}</div>
          ${_print.showSubjectCode && _print.subjectCode.trim().isNotEmpty ? '<div>বিষয় কোড: ${_escapeXml(_print.subjectCode.trim())}</div>' : ''}
          ${_print.showChapter && _print.chapter.trim().isNotEmpty ? '<div>অধ্যায়: ${_escapeXml(_print.chapter.trim())}</div>' : ''}
          ${_print.showInstructions && cqInstruction.trim().isNotEmpty ? '<div class="meta-note">[ ${_escapeXml(cqInstruction.trim())} ]</div>' : ''}
        </div>
        ${_print.showStudentInfo ? '''
        <div class="student-info">
          <span>শিক্ষার্থীর নাম: ................................................</span>
          <span>রোল: ................</span>
          <span>শ্রেণি: ................</span>
        </div>''' : ''}
        ${_print.showObtainedMarks ? '<div class="obtained-marks">প্রাপ্ত নম্বর: ................</div>' : ''}
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
          imageBytes: imageBytes,
        );
        i++;
        continue;
      }

      // MCQ keeps its in-flow heading, while dashed edges mark only the
      // boundaries that touch neighboring question sections.
      final declarationInFlow = twoColumnBlocks.contains(kind);
      final hasPreviousSection = sections
          .take(i)
          .any((section) => questions.any((q) => _sectionOf(q) == section));
      final hasNextSection = sections
          .skip(i + 1)
          .any((section) => questions.any((q) => _sectionOf(q) == section));
      final mcqClasses = <String>[
        if (hasPreviousSection) 'top',
        if (hasNextSection) 'bottom',
      ];
      final wrapMcq =
          kind == PaperSection.mcq && declares && mcqClasses.isNotEmpty;
      if (wrapMcq) {
        buffer.write(
            '    <div class="mcq-section-separator ${mcqClasses.join(' ')}">\n');
      }
      switch (kind) {
        case PaperSection.cq:
          _writeHtmlCqSection(buffer, inSection, heading, imageSize,
              imageBytes: imageBytes, declarationInFlow: declarationInFlow);
          break;
        case PaperSection.mcq:
          _writeHtmlMcqSection(buffer, inSection, heading, imageSize,
              imageBytes: imageBytes, declarationInFlow: declarationInFlow);
          break;
        case PaperSection.rq:
          _writeHtmlRqSection(buffer, inSection, heading, imageSize,
              imageBytes: imageBytes, declarationInFlow: declarationInFlow);
          break;
      }
      if (wrapMcq) buffer.write('    </div>\n');
    }

    buffer.write('''
    </div>
''');

    if (questions.any((q) => q.isMcq)) {
      _writeHtmlMcqAnswerSheet(
        buffer,
        questions.where((q) => q.isMcq).toList(),
        mcqAnswerSheetStyle,
      );
    } else {
      _writeHtmlManualMcqAnswerSheet(buffer);
    }
    if (footerBand.isNotEmpty) buffer.write(footerBand);
  }

  static void _writeHtmlManualMcqAnswerSheet(StringBuffer buffer) {
    buffer.write('''
    <section class="mcq-answer-sheet" data-manual-answer-sheet="true" style="display:none;">
      <div class="answer-sheet-title">MCQ উত্তরপত্র</div>
      <div class="answer-sheet-variant answer-sheet-omr" data-answer-style="omr" style="display:none;">
        <div class="omr-grid"></div>
      </div>
      <div class="answer-sheet-variant answer-sheet-serial" data-answer-style="serialAnswer" style="display:none;"></div>
    </section>
''');
  }

  /// Adds an optional answer sheet after one generated paper set.
  static void _writeHtmlMcqAnswerSheet(
    StringBuffer buffer,
    List<HighSchoolQuestion> mcqs,
    McqAnswerSheetStyle style,
  ) {
    if (mcqs.isEmpty) return;
    final visible = style == McqAnswerSheetStyle.none ? 'display:none;' : '';
    buffer.write('''
    <section class="mcq-answer-sheet" style="$visible">
      <div class="answer-sheet-title">MCQ উত্তরপত্র</div>
''');

    final omrVisible = style == McqAnswerSheetStyle.omr ? '' : 'display:none;';
    buffer.write(
        '<div class="answer-sheet-variant answer-sheet-omr" data-answer-style="omr" style="$omrVisible">');
    {
      const letters = ['ক', 'খ', 'গ', 'ঘ'];
      final columns = <List<int>>[[], [], [], []];
      final rowsPerColumn =
          (mcqs.length + columns.length - 1) ~/ columns.length;
      for (var i = 0; i < mcqs.length; i++) {
        final column = (i ~/ rowsPerColumn).clamp(0, columns.length - 1);
        columns[column].add(i + 1);
      }
      buffer.write('<div class="omr-grid">');
      for (final column in columns) {
        buffer.write('<div class="omr-column">');
        for (final number in column) {
          buffer.write('''
        <div class="omr-row"><span class="omr-number">$number</span>
          ${letters.map((letter) => '<span class="omr-bubble">$letter</span>').join()}
        </div>
''');
        }
        buffer.write('</div>');
      }
      buffer.write('</div>');
    }

    final serialVisible =
        style == McqAnswerSheetStyle.serialAnswer ? '' : 'display:none;';
    buffer.write(
        '<div class="answer-sheet-variant answer-sheet-serial" data-answer-style="serialAnswer" style="$serialVisible">');
    {
      const columnsPerTable = 30;
      for (var start = 0; start < mcqs.length; start += columnsPerTable) {
        final end = (start + columnsPerTable).clamp(0, mcqs.length);
        buffer.write(
            '<table class="serial-answer-table" style="width:${(end - start) * 6.5}mm"><tbody><tr>');
        for (var i = start; i < end; i++) {
          buffer.write('<th>${i + 1}</th>');
        }
        buffer.write('</tr><tr class="serial-answer-row">');
        for (var i = start; i < end; i++) {
          buffer.write('<td></td>');
        }
        buffer.write('</tr></tbody></table>');
      }
      buffer.write('</div>');
    }
    buffer.write('</section>');
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
    Map<String, Uint8List>? imageBytes,
  }) {
    buffer.write('''
    <div class="flow-grid">
''');
    _writeHtmlFlowPart(buffer, questions, first, firstHeading, imageSize,
        imageBytes: imageBytes);
    _writeHtmlFlowPart(buffer, questions, second, secondHeading, imageSize,
        imageBytes: imageBytes);
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
    StemImageSize imageSize, {
    Map<String, Uint8List>? imageBytes,
  }) {
    final inSection = questions.where((q) => _sectionOf(q) == kind).toList();
    if (inSection.isEmpty) return;

    _writeHtmlDeclaration(buffer, heading, inFlow: true);
    if (kind == PaperSection.cq) {
      _writeHtmlCqCards(buffer, inSection, imageSize, imageBytes: imageBytes);
    } else {
      _writeHtmlRqItems(buffer, inSection, imageSize, imageBytes: imageBytes);
    }
  }

  /// The সৃজনশীল প্রশ্ন block: its declaration, then one bordered card per
  /// question.
  static void _writeHtmlCqSection(
    StringBuffer buffer,
    List<HighSchoolQuestion> cqs,
    String heading,
    StemImageSize imageSize, {
    Map<String, Uint8List>? imageBytes,
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
    _writeHtmlCqCards(buffer, cqs, imageSize, imageBytes: imageBytes);
    buffer.write('''
    </div>
''');
  }

  /// The CQ cards, with no container: the block or the merged flow supplies the
  /// columns.
  static void _writeHtmlCqCards(
    StringBuffer buffer,
    List<HighSchoolQuestion> cqs,
    StemImageSize imageSize, {
    Map<String, Uint8List>? imageBytes,
  }) {
    for (int i = 0; i < cqs.length; i++) {
      final q = cqs[i];
      final index = i + 1;
      buffer.write('''
    <div class="cq-card" title="${_idTooltip(q)}">
      <div class="cq-stem">
        ${_importantStar(q)}<b>$index.</b> ${_htmlText(q.paperStemText, latex: true)}
      </div>
      ${_questionInfoMarkup(q)}
      ${_stemImageMarkup(q, bytes: imageBytes, size: imageSize, usePoints: false)}
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
    Map<String, Uint8List>? imageBytes,
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
    for (int i = 0; i < mcqs.length; i++) {
      final q = mcqs[i];
      final mcq = q.mcqData;
      final index = i + 1;
      if (mcq == null) continue;

      final prev = i > 0 ? mcqs[i - 1] : null;
      final opensStem = q.opensMcqStemGroup(prev);
      final sharesStem = q.sharesMcqStemWith(prev);

      final alreadyPrintedStem = opensStem ||
          (sharesStem &&
              prev != null &&
              _hasStemImage(prev, imageSize) &&
              prev.stemImageUrl.trim() == q.stemImageUrl.trim());
      final questionImageHtml =
          (!alreadyPrintedStem && _hasStemImage(q, imageSize))
              ? _stemImageMarkup(q,
                  bytes: imageBytes, size: imageSize, usePoints: false)
              : '';

      buffer.write('''
      <div class="mcq-card" title="${_idTooltip(q)}">
        <div class="mcq-head">
''');
      if (opensStem) {
        buffer.write('''
          <div class="mcq-stem">${_htmlText(stemWithNumbers(q.mcqStemText, mcqStemRunNumbers(mcqs, i)), latex: true)}${_stemImageMarkup(q, bytes: imageBytes, size: imageSize, usePoints: false)}</div>
''');
      }
      buffer.write('''
          <div class="mcq-question">${_importantStar(q)}<b>$index.</b> ${_htmlText(q.paperQuestionText)}</div>
          ${_questionInfoMarkup(q)}
          $questionImageHtml
        </div>
        <div class="mcq-options" data-fit="1">
''');
      final options = mcq.options;
      for (int opt = 0; opt < options.length; opt++) {
        final l =
            opt < bengaliLetters.length ? bengaliLetters[opt] : '${opt + 1}';
        buffer.write('''
          <div>${_print.optionStyle.prefix(l)} ${_htmlText(options[opt])}</div>
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

  /// The gold star the important-question toggle prints beside a marked row.
  static String _importantStar(HighSchoolQuestion q) =>
      _print.showImportant && q.isImportant
          ? '<span class="important-star">★</span>'
          : '';

  /// The small chapter/board line the question-info toggle adds under a row.
  static String _questionInfoMarkup(HighSchoolQuestion q) {
    if (!_print.showQuestionInfo) return '';
    final parts = <String>[
      if (q.chapterName.trim().isNotEmpty)
        'অধ্যায়: ${_escapeXml(q.chapterName.trim())}',
      if (q.boardYearTag.trim().isNotEmpty) _escapeXml(q.boardYearTag.trim()),
    ];
    if (parts.isEmpty) return '';
    return '<div class="question-info">[${parts.join(' · ')}]</div>';
  }

  /// The সংক্ষিপ্ত প্রশ্ন block.
  static void _writeHtmlRqSection(
    StringBuffer buffer,
    List<HighSchoolQuestion> shorts,
    String heading,
    StemImageSize imageSize, {
    Map<String, Uint8List>? imageBytes,
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
    _writeHtmlRqItems(buffer, shorts, imageSize, imageBytes: imageBytes);
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
    StemImageSize imageSize, {
    Map<String, Uint8List>? imageBytes,
  }) {
    for (int i = 0; i < shorts.length; i++) {
      final q = shorts[i];
      final data = q.shortData;
      if (data == null || data.text.trim().isEmpty) continue;
      final imageHtml = _stemImageMarkup(q,
          bytes: imageBytes, size: imageSize, usePoints: false);
      buffer.write('''
        <div class="rq-item" title="${_idTooltip(q)}">
          <div class="rq-content">
            <div>${_importantStar(q)}<b>${i + 1}.</b> ${_htmlText(data.text)}</div>
            ${_questionInfoMarkup(q)}
            $imageHtml
          </div>
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
    StemImageSize imageSize = StemImageSize.small,
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
          for (int j = 0; j < inSection.length; j++) {
            final q = inSection[j];
            final mcq = q.mcqData;
            if (mcq == null) continue;

            final prev = j > 0 ? inSection[j - 1] : null;
            final opensStem = q.opensMcqStemGroup(prev);
            final sharesStem = q.sharesMcqStemWith(prev);

            // The shared intro, once, over the first question of its group.
            if (opensStem) {
              buffer.writeln(
                  '> ${stemWithNumbers(q.mcqStemText, mcqStemRunNumbers(inSection, j))}\n');
              if (_hasStemImage(q, imageSize)) {
                buffer.writeln('![উদ্দীপক চিত্র](${_stemImageUrlOf(q)})\n');
              }
            }

            buffer.writeln('**${j + 1}.** ${q.paperQuestionText}');
            final alreadyPrintedStem = opensStem ||
                (sharesStem &&
                    prev != null &&
                    _hasStemImage(prev, imageSize) &&
                    prev.stemImageUrl.trim() == q.stemImageUrl.trim());
            if (!alreadyPrintedStem && _hasStemImage(q, imageSize)) {
              buffer.writeln('![প্রশ্ন চিত্র](${_stemImageUrlOf(q)})\n');
            }

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
            final q = inSection[j];
            final data = q.shortData;
            if (data == null || data.text.trim().isEmpty) continue;
            buffer
                .writeln('**${j + 1}.** ${data.text.trim()} `[${data.mark}]`');
            if (_hasStemImage(q, imageSize)) {
              buffer.writeln(
                  '![সংক্ষিপ্ত প্রশ্ন চিত্র](${_stemImageUrlOf(q)})\n');
            }
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

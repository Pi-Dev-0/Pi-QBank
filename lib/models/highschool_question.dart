import 'dart:convert';
import '../utils/math_text.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CQ Sub-question model
// ─────────────────────────────────────────────────────────────────────────────

class CqSubQuestion {
  final String label;
  final int mark;
  final String text;

  const CqSubQuestion({
    required this.label,
    required this.mark,
    required this.text,
  });

  factory CqSubQuestion.fromJson(Map<String, dynamic> json) {
    return CqSubQuestion(
      label: json['label'] as String? ?? '',
      mark: (json['mark'] as num?)?.toInt() ?? 0,
      text: json['text'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'mark': mark,
        'text': text,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// MCQ sub-question model
// ─────────────────────────────────────────────────────────────────────────────

class McqQuestion {
  final String text;
  final List<String> options;
  final String correctAns;

  const McqQuestion({
    required this.text,
    required this.options,
    required this.correctAns,
  });

  factory McqQuestion.fromJson(Map<String, dynamic> json) {
    return McqQuestion(
      text: json['text'] as String? ?? '',
      options: List<String>.from(json['options'] as List? ?? []),
      correctAns: json['correct_ans'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        'options': options,
        'correct_ans': correctAns,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// Short question (SQ) model
//
// A short answer question is a single prompt. Its text lives in `stem_text`
// like any other question — there is no stem, no sub-questions and no options,
// so `sub_questions_json` is unused and stays empty.
//
// The mark is per question and stored in its own `short_mark` column, because
// short questions are worth 1 mark in some papers and 2 in others.
// ─────────────────────────────────────────────────────────────────────────────

class ShortQuestion {
  final String text;
  final int mark;

  static const int defaultMark = 1;

  const ShortQuestion({required this.text, this.mark = defaultMark});

  factory ShortQuestion.fromJson(Map<String, dynamic> json) {
    return ShortQuestion(
      text: json['text'] as String? ?? '',
      mark: (json['mark'] as num?)?.toInt() ?? defaultMark,
    );
  }

  Map<String, dynamic> toJson() => {'text': text, 'mark': mark};
}

// ─────────────────────────────────────────────────────────────────────────────
// Chapter info helper
// ─────────────────────────────────────────────────────────────────────────────

class ChapterInfo {
  final String chapterNumber;
  final String chapterName;

  const ChapterInfo({required this.chapterNumber, required this.chapterName});

  factory ChapterInfo.fromJson(Map<String, dynamic> json) => ChapterInfo(
        chapterNumber: json['chapter_number'] as String? ?? '',
        chapterName: json['chapter_name'] as String? ?? '',
      );

  @override
  bool operator ==(Object other) =>
      other is ChapterInfo && other.chapterNumber == chapterNumber;

  @override
  int get hashCode => chapterNumber.hashCode;

  @override
  String toString() => 'অধ্যায় $chapterNumber: $chapterName';
}

/// Order two chapter labels the way a textbook reads them: `1`, `2`, `2.2`,
/// `3`, `10`.
///
/// A chapter number is a label, not an integer. "2.2 চক্রবৃদ্ধি মুনাফা" is a
/// section inside chapter 2, so `int.tryParse` gave up on it and the `?? 0` that
/// used to stand in for the failure printed the section *ahead* of chapter 1.
/// Labels that are not numbers at all sort after every number rather than in
/// front of them, alphabetically among themselves.
int compareChapterNumbers(String a, String b) {
  final left = double.tryParse(a.trim());
  final right = double.tryParse(b.trim());
  if (left != null && right != null) return left.compareTo(right);
  if (left != null) return -1;
  if (right != null) return 1;
  return a.compareTo(b);
}

// ─────────────────────────────────────────────────────────────────────────────
// Main HighSchool Question model
// ─────────────────────────────────────────────────────────────────────────────

class HighSchoolQuestion {
  final String id;
  final String className;
  final String subject;
  final String chapterNumber;
  final String chapterName;
  final String questionType; // 'CQ' | 'MCQ' | 'RQ'
  final String stemText;
  final String stemImageUrl;

  /// The shared-উদ্দীপক label, from the `stem_group` column.
  ///
  /// An MCQ that prints under an intro shared with its neighbour can say so
  /// outright instead of leaving the sheet to guess: every row of the run
  /// carries the same label here. Consecutive MCQs agreeing on a non-empty label
  /// are one run whatever their wording or figure says, so two intros that
  /// happen to read alike ("নিচের উদ্দীপকটি পড়…") stay two intros. Empty for
  /// every other type, and for a run filed without one.
  final String stemGroup;

  /// For CQ:  List<CqSubQuestion>
  /// For MCQ: McqQuestion
  /// RQ does not use this — its payload stays empty.
  final dynamic subQuestionsData;

  final String boardYearTag;

  /// Marks for a short question (SQ), from the `short_mark` column.
  /// Ignored for CQ/MCQ. Defaults to 1 when the column is empty.
  final int shortMark;

  // Runtime state (not from API)
  bool isSelected;

  /// Which set this question belongs to when a paper is printed as two
  /// variants ("ক" / "খ").
  ///
  /// Runtime state, not stored in the sheet: sets describe one generated paper,
  /// not the question itself. Empty means "the only set".
  String setLabel;

  /// True for a question typed into the picker by hand.
  ///
  /// Runtime state like [isSelected] and [setLabel]: it records where the row
  /// came from, not what the question is, so it never reaches the sheet. The
  /// picker badges such a row so it is clear which questions came from the bank
  /// and which were written on the spot.
  bool isManual;

  /// True for a row that came from the bank and was corrected in the picker.
  ///
  /// Runtime state as well: an edit changes what *this* paper prints and nothing
  /// else, so the sheet keeps the row it came from and no write permission is
  /// needed. [id] is inherited, so the card still points at the row it was
  /// fixed from.
  bool isEdited;

  /// True when the reader marked this row as important for the paper.
  ///
  /// Runtime state like [isSelected]: the star belongs to the paper being
  /// built, not to the bank row, and the sheet only prints it while the
  /// print-settings panel's important-question switch is on.
  bool isImportant;

  HighSchoolQuestion({
    required this.id,
    required this.className,
    required this.subject,
    required this.chapterNumber,
    required this.chapterName,
    required this.questionType,
    required this.stemText,
    required this.stemImageUrl,
    this.stemGroup = '',
    required this.subQuestionsData,
    required this.boardYearTag,
    this.shortMark = ShortQuestion.defaultMark,
    this.isSelected = false,
    this.setLabel = '',
    this.isManual = false,
    this.isEdited = false,
    this.isImportant = false,
  });

  /// A question typed into the picker instead of read from the sheet.
  ///
  /// Everything the sheet would have supplied has to be given here: the class
  /// and subject the paper is being built for, the chapter the question is filed
  /// under, and the payload its type expects — [subQuestions] for a CQ,
  /// [options] with [correctAnswer] for an MCQ, [shortMark] for a short
  /// question.
  ///
  /// [text] is the উদ্দীপক for a CQ, the question itself for an MCQ or a short
  /// question. [stem] is the MCQ's own উদ্দীপক — the intro and figure shared
  /// with the question printed under it, kept separately because an MCQ's
  /// payload is its question, not its intro. Both are optional: most questions
  /// have no intro of their own.
  ///
  /// Typed text is run through [normaliseTypedFractions] exactly as a fetched
  /// row is, so a hand-typed `1/2` prints as `½` like everything else.
  ///
  /// The id is generated and prefixed `manual`, so a hand-typed row can never
  /// collide with a sheet row.
  factory HighSchoolQuestion.manual({
    required String className,
    required String subject,
    required String chapterNumber,
    required String chapterName,
    required String questionType,
    String text = '',
    String stem = '',
    String stemImageUrl = '',
    List<CqSubQuestion> subQuestions = const [],
    List<String> options = const [],
    String correctAnswer = '',
    int shortMark = ShortQuestion.defaultMark,
  }) {
    final assembled = _assemble(
      questionType: questionType,
      text: text,
      stem: stem,
      subQuestions: subQuestions,
      options: options,
      correctAnswer: correctAnswer,
      shortMark: shortMark,
    );
    final type = questionType.toUpperCase();

    return HighSchoolQuestion(
      id: _nextManualId(),
      className: className,
      subject: subject,
      chapterNumber: chapterNumber.trim(),
      chapterName: chapterName.trim(),
      // `SHORT` and `RQ` both mean a short question; the sheet spells it `RQ`.
      questionType: type == 'SHORT' ? 'RQ' : type,
      stemText: assembled.stemText,
      stemImageUrl: stemImageUrl,
      subQuestionsData: assembled.payload,
      boardYearTag: '',
      shortMark: assembled.mark,
      // Typed by hand for this paper, so it starts selected: the reason it was
      // typed was to print it.
      isSelected: true,
      isManual: true,
    );
  }

  /// [original] with the reader's corrections applied.
  ///
  /// The same payload a hand-typed question takes, but everything that
  /// identifies the row is inherited instead: its id, class, subject, board tag,
  /// and its place in the paper ([isSelected], [setLabel]). The sheet therefore
  /// keeps the row it came from — an edit changes what *this* paper prints and
  /// nothing else — while the card still points at the row it was fixed from.
  /// [isEdited] is set so the picker can say so.
  factory HighSchoolQuestion.edited({
    required HighSchoolQuestion original,
    required String chapterNumber,
    required String chapterName,
    String text = '',
    String stem = '',
    String stemImageUrl = '',
    List<CqSubQuestion> subQuestions = const [],
    List<String> options = const [],
    String correctAnswer = '',
    int shortMark = ShortQuestion.defaultMark,
  }) {
    final assembled = _assemble(
      questionType: original.questionType,
      text: text,
      stem: stem,
      subQuestions: subQuestions,
      options: options,
      correctAnswer: correctAnswer,
      shortMark: shortMark,
    );

    return HighSchoolQuestion(
      id: original.id,
      className: original.className,
      subject: original.subject,
      chapterNumber: chapterNumber.trim(),
      chapterName: chapterName.trim(),
      questionType: original.questionType,
      stemText: assembled.stemText,
      stemImageUrl: stemImageUrl,
      // A corrected row stays in the উদ্দীপক run it was filed into, so the
      // intro keeps printing once over the group it belongs to.
      stemGroup: original.stemGroup,
      subQuestionsData: assembled.payload,
      boardYearTag: original.boardYearTag,
      shortMark: assembled.mark,
      isSelected: original.isSelected,
      setLabel: original.setLabel,
      isManual: original.isManual,
      isEdited: true,
      isImportant: original.isImportant,
    );
  }

  /// The stem, payload and mark a typed payload resolves to, whatever the type.
  ///
  /// Shared by [HighSchoolQuestion.manual] and [HighSchoolQuestion.edited], so a
  /// correction is normalised exactly like a first typing: fractions folded, the
  /// blanks dropped, marks never below one.
  static ({String stemText, dynamic payload, int mark}) _assemble({
    required String questionType,
    String text = '',
    String stem = '',
    List<CqSubQuestion> subQuestions = const [],
    List<String> options = const [],
    String correctAnswer = '',
    int shortMark = ShortQuestion.defaultMark,
  }) {
    final type = questionType.toUpperCase();
    final typed = normaliseTypedFractions(text.trim());
    final typedStem = normaliseTypedFractions(stem.trim());
    final mark = shortMark < 1 ? 1 : shortMark;

    if (type == 'CQ') {
      return (
        stemText: typed,
        mark: mark,
        payload: [
          for (final sq in subQuestions)
            CqSubQuestion(
              label: sq.label,
              mark: sq.mark < 1 ? 1 : sq.mark,
              text: normaliseTypedFractions(sq.text.trim()),
            ),
        ],
      );
    }
    if (type == 'MCQ') {
      // The intro goes to the stem, where the group logic and the figure look
      // for it; the question itself and its options are the payload.
      return (
        stemText: typedStem,
        mark: mark,
        payload: McqQuestion(
          text: typed,
          options: [
            for (final o in options)
              if (o.trim().isNotEmpty) normaliseTypedFractions(o.trim()),
          ],
          correctAns: correctAnswer.trim(),
        ),
      );
    }
    // A short question is its text: no stem, no sub-questions, no options.
    return (
      stemText: typed,
      mark: mark,
      payload: ShortQuestion(text: typed, mark: mark),
    );
  }

  /// Serial behind the ids of hand-typed questions.
  ///
  /// A timestamp alone is not enough: two questions saved from the same sheet
  /// within the same millisecond would share an id, and the picker keys its
  /// expand/collapse state on the id.
  static int _manualSerial = 0;

  static String _nextManualId() =>
      'manual-${DateTime.now().microsecondsSinceEpoch}-${_manualSerial++}';

  bool get isCq => questionType.toUpperCase() == 'CQ';
  bool get isMcq => questionType.toUpperCase() == 'MCQ';

  /// Short answer question (RQ / সংক্ষিপ্ত প্রশ্ন).
  bool get isShort =>
      questionType.toUpperCase() == 'RQ' ||
      questionType.toUpperCase() == 'SHORT';

  /// [stemText] as it should be printed.
  ///
  /// The sheet stores a question's source twice: in [boardYearTag], and again
  /// pasted onto the end of the stem in brackets. A question paper prints
  /// neither, and the second copy is what left "মাদ্রাসা বোর্ড ২০১৮" sitting at
  /// the end of a CQ stem.
  ///
  /// Two shapes turn up in the data:
  ///
  ///   * spelled out — `… পরামর্শ নিলেন। [মাদ্রাসা বোর্ড ২০১৮]`, where the
  ///     bracket repeats [boardYearTag] exactly;
  ///   * abbreviated — `[দি.বো.'১৭]`, which never matches the tag column
  ///     character for character, so an equality test alone misses it.
  ///
  /// A *trailing* bracket is therefore dropped when it is the tag itself, or
  /// when it reads as a source marker: short, free of sentence punctuation, and
  /// naming a board, school or college. Anything else is left exactly as
  /// written, so a stem is never clipped for any other reason.
  String get paperStemText => _withoutSourceMarker(stemText);

  /// The MCQ question line as it should be printed.
  ///
  /// An MCQ keeps its question in the sub-question payload rather than in
  /// [stemText], so a source marker can ride there instead. Trimmed the same
  /// way, and for the same reason.
  String get paperQuestionText {
    final mcq = mcqData;
    if (mcq == null) return '';
    return _withoutSourceMarker(mcq.text);
  }

  /// The উদ্দীপক an MCQ shares with the questions printed under it, as printed.
  ///
  /// An MCQ keeps its own line in the sub-question payload and borrows
  /// [stemText] — and [stemImageUrl] — for the intro and figure above it:
  /// "নিচের তথ্য থেকে ২৬ ও ২৭ নং প্রশ্নের উত্তর দাও।". Two questions written
  /// under one intro therefore carry the same text — and, when the intro has a
  /// figure, the same [mcqStemImageUrl] — which is what [opensMcqStemGroup]
  /// reads, unless the rows were filed with a [mcqStemGroup] label that says it
  /// outright. Empty for every other type, and for an MCQ that has no intro of
  /// its own.
  String get mcqStemText => isMcq ? paperStemText.trim() : '';

  /// The figure that belongs to the উদ্দীপক, as printed.
  ///
  /// An intro is a wording *and* the figure printed under it, so the figure is
  /// read off [stemImageUrl] the way the wording is read off [stemText]. Empty
  /// for every other type, and for an intro that carries no figure.
  String get mcqStemImageUrl => isMcq ? stemImageUrl.trim() : '';

  /// The shared-উদ্দীপক label an MCQ was filed with, as read from the sheet.
  ///
  /// This is the explicit form of [mcqStemText]: instead of the writers working
  /// out whether two questions print under one intro by comparing what they say,
  /// the sheet says it. Every row of the run carries the same label in the
  /// `stem_group` column. Empty for every other type, and for a run filed
  /// without a label — the grouping then falls back on the wording and figure,
  /// as it did before the column existed.
  String get mcqStemGroup => isMcq ? stemGroup.trim() : '';

  /// True when this question prints the উদ্দীপক itself.
  ///
  /// That is: it has one, and the question before it in the paper does not carry
  /// the same one. A shared intro prints once, over the first of the questions
  /// it introduces — numbering the intro would be wrong when it belongs to two
  /// questions, and printing it twice is worse. The question before it is the
  /// only thing that knows whether the group has already been opened, which is
  /// why the caller passes it in rather than this getter guessing.
  bool opensMcqStemGroup(HighSchoolQuestion? previous) =>
      mcqStemText.isNotEmpty && !sharesMcqStemWith(previous);

  /// True when [previous] already printed this question's উদ্দীপক, so all this
  /// one has to do is follow it.
  ///
  /// A run filed with a [mcqStemGroup] label is one run outright: the intro
  /// prints over the first of the rows, whatever the rows' wording or figure
  /// says. That is the whole point of the label — two intros that happen to read
  /// alike ("নিচের উদ্দীপকটি পড়…" over two different stimuli, or the same text
  /// with a figure URL rewritten) are told apart by the sheet rather than
  /// guessed at. A label, once filed, is never second-guessed in the other
  /// direction either: rows that disagree on it — including a row that carries
  /// none beside one that does — do not share, so a question the sheet never
  /// put in a run cannot be swallowed into one. A different *wording* still
  /// opens its own intro inside a labelled run, so a row carrying text the run
  /// has not printed yet is printed rather than lost.
  ///
  /// Only when neither row filed a label does the intro itself decide: the same
  /// wording, and — when the intro has a figure — the same figure. A question
  /// that carries no figure of its own follows on the wording alone, which is
  /// how a run written under one figure is filed. A question that *does* carry
  /// one joins only an intro carrying the same figure, so the second figure of
  /// a pair is never dropped from the paper.
  ///
  /// The mirror of [opensMcqStemGroup], and the reason a two-set shuffle moves
  /// whole groups rather than single questions: a question that shares an intro
  /// must not be moved away from the one that printed it. A question with no
  /// intro of its own shares nothing, however the question before it reads.
  bool sharesMcqStemWith(HighSchoolQuestion? previous) {
    if (previous == null || mcqStemText.isEmpty) return false;
    if (previous.mcqStemText != mcqStemText) return false;
    final group = mcqStemGroup;
    final previousGroup = previous.mcqStemGroup;
    if (group.isNotEmpty || previousGroup.isNotEmpty) {
      return group == previousGroup;
    }
    return mcqStemImageUrl.isEmpty ||
        previous.mcqStemImageUrl == mcqStemImageUrl;
  }

  /// Words that appear in this sheet only as the source of a question.
  static const _sourceWords = <String>[
    'বোর্ড',
    'বো.',
    'কলেজ',
    'মাদ্রাসা',
    'বিদ্যালয়',
    'স্কুল',
  ];

  /// [text] with a trailing `[source]` marker removed, if it ends in one.
  String _withoutSourceMarker(String text) {
    final trimmed = text.trimRight();
    if (!trimmed.endsWith(']')) return text;

    final open = trimmed.lastIndexOf('[');
    if (open < 0) return text;

    final marker = trimmed.substring(open + 1, trimmed.length - 1).trim();
    if (!_readsAsSource(marker)) return text;

    return trimmed.substring(0, open).trimRight();
  }

  bool _readsAsSource(String marker) {
    // A source marker is a label, not a sentence: anything long, or holding
    // sentence punctuation, is part of the question and stays.
    if (marker.isEmpty || marker.length > 48) return false;
    if (marker.contains('।') || marker.contains('?')) return false;

    // No source on the row means nothing to trim, whatever the brackets say.
    final tag = boardYearTag.trim();
    if (tag.isEmpty) return false;

    if (marker == tag) return true;
    return _sourceWords.any(marker.contains);
  }

  /// Parsed CQ sub-questions (returns empty list for MCQ)
  List<CqSubQuestion> get cqSubQuestions {
    if (!isCq) return [];
    if (subQuestionsData is List<CqSubQuestion>) {
      return subQuestionsData as List<CqSubQuestion>;
    }
    return [];
  }

  /// Parsed MCQ data (returns null for CQ)
  McqQuestion? get mcqData {
    if (!isMcq) return null;
    if (subQuestionsData is McqQuestion) {
      return subQuestionsData as McqQuestion;
    }
    return null;
  }

  /// The short question, read from [stemText] and [shortMark].
  ///
  /// RQ rows carry their text in `stem_text`; `sub_questions_json` is unused.
  /// A legacy payload there is still honoured so rows written by an older
  /// uploader keep rendering.
  ShortQuestion? get shortData {
    if (!isShort) return null;

    final candidates = <String>[
      stemText,
      if (subQuestionsData is ShortQuestion)
        (subQuestionsData as ShortQuestion).text,
      if (subQuestionsData is Map)
        ShortQuestion.fromJson(
                Map<String, dynamic>.from(subQuestionsData as Map))
            .text,
      if (subQuestionsData is String) subQuestionsData as String,
    ];

    for (final c in candidates) {
      if (c.trim().isNotEmpty) {
        return ShortQuestion(text: c, mark: shortMark);
      }
    }
    return null;
  }

  /// Total marks for this question
  int get totalMarks {
    if (isCq) {
      return cqSubQuestions.fold(0, (sum, sq) => sum + sq.mark);
    }
    if (isShort) {
      return shortData?.mark ?? 1;
    }
    return 1; // MCQ = 1 mark each
  }

  ChapterInfo get chapterInfo =>
      ChapterInfo(chapterNumber: chapterNumber, chapterName: chapterName);

  /// Apply [normaliseTypedFractions] to the text inside a parsed sub-question blob.
  ///
  /// The blob is a `List<CqSubQuestion>`, a `McqQuestion`, a `ShortQuestion`,
  /// or null, depending on the question type.
  static dynamic _normaliseSubQuestionText(dynamic parsed) {
    if (parsed is List<CqSubQuestion>) {
      return [
        for (final sq in parsed)
          CqSubQuestion(
            label: sq.label,
            mark: sq.mark,
            text: normaliseTypedFractions(sq.text),
          ),
      ];
    }
    if (parsed is McqQuestion) {
      return McqQuestion(
        text: normaliseTypedFractions(parsed.text),
        options: [for (final o in parsed.options) normaliseTypedFractions(o)],
        correctAns: parsed.correctAns,
      );
    }
    return parsed;
  }

  factory HighSchoolQuestion.fromJson(Map<String, dynamic> json) {
    final qType = (json['question_type'] as String? ?? 'CQ').toUpperCase();
    dynamic parsed;

    final rawSub = json['sub_questions_json'];

    if (qType == 'CQ') {
      if (rawSub is List) {
        parsed = rawSub
            .map((e) => CqSubQuestion.fromJson(e as Map<String, dynamic>))
            .toList();
      } else if (rawSub is String) {
        try {
          final decoded = jsonDecode(rawSub) as List;
          parsed = decoded
              .map((e) => CqSubQuestion.fromJson(e as Map<String, dynamic>))
              .toList();
        } catch (_) {
          parsed = <CqSubQuestion>[];
        }
      } else {
        parsed = <CqSubQuestion>[];
      }
    } else if (qType == 'RQ' || qType == 'SHORT') {
      // Short answer question: the text is in stem_text. sub_questions_json
      // is not used; a legacy payload there is still parsed as a fallback.
      final stem = json['stem_text'] as String? ?? '';
      ShortQuestion? legacy;
      if (rawSub is Map) {
        legacy = ShortQuestion.fromJson(Map<String, dynamic>.from(rawSub));
      } else if (rawSub is String && rawSub.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(rawSub);
          legacy = decoded is Map
              ? ShortQuestion.fromJson(Map<String, dynamic>.from(decoded))
              : ShortQuestion(text: rawSub);
        } catch (_) {
          legacy = ShortQuestion(text: rawSub);
        }
      }
      parsed = ShortQuestion(
          text: stem.trim().isNotEmpty ? stem : (legacy?.text ?? ''),
          mark: _readShortMark(json));
    } else {
      // MCQ
      if (rawSub is Map<String, dynamic>) {
        parsed = McqQuestion.fromJson(rawSub);
      } else if (rawSub is String) {
        try {
          parsed =
              McqQuestion.fromJson(jsonDecode(rawSub) as Map<String, dynamic>);
        } catch (_) {
          parsed = null;
        }
      } else {
        parsed = null;
      }
    }

    // Bare `1/2` becomes `½` here, once, so the preview and every export format
    // show the same thing. See [normaliseTypedFractions].
    final stemText =
        normaliseTypedFractions(json['stem_text'] as String? ?? '');
    parsed = _normaliseSubQuestionText(parsed);

    return HighSchoolQuestion(
      id: json['id'] as String? ?? '',
      className: json['class'] as String? ?? '',
      subject: json['subject'] as String? ?? '',
      chapterNumber: json['chapter_number'] as String? ?? '',
      chapterName: json['chapter_name'] as String? ?? '',
      questionType: qType,
      stemText: stemText,
      stemImageUrl: json['stem_image_url'] as String? ?? '',
      stemGroup: (json['stem_group'] as String? ?? '').trim(),
      subQuestionsData: parsed,
      boardYearTag: json['board_year_tag'] as String? ?? '',
      shortMark: _readShortMark(json),
    );
  }

  /// `short_mark` arrives as a number, a numeric string (the Sheet stores
  /// everything as text) or nothing at all. Anything below 1 is treated as
  /// unset so a blank column falls back to the default.
  static int _readShortMark(Map<String, dynamic> json) {
    final raw = json['short_mark'];
    if (raw == null) return ShortQuestion.defaultMark;

    final n = raw is num ? raw.toInt() : int.tryParse(raw.toString().trim());
    if (n == null || n < 1) return ShortQuestion.defaultMark;
    return n;
  }

  Map<String, dynamic> toJson() {
    dynamic subJson;
    if (isCq) {
      subJson = cqSubQuestions.map((e) => e.toJson()).toList();
    } else if (isShort) {
      // No sub-questions: the text already lives in stem_text.
      subJson = <dynamic>[];
    } else {
      subJson = mcqData?.toJson();
    }

    return {
      'id': id,
      'class': className,
      'subject': subject,
      'chapter_number': chapterNumber,
      'chapter_name': chapterName,
      'question_type': questionType,
      'stem_text': stemText,
      'stem_image_url': stemImageUrl,
      'sub_questions_json': subJson,
      'board_year_tag': boardYearTag,
      'short_mark': isShort ? shortMark : '',
      'stem_group': stemGroup,
    };
  }
}

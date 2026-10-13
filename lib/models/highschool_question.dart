import 'dart:convert';

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
// Short question (RQ) model
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

  /// For CQ:  List<CqSubQuestion>
  /// For MCQ: McqQuestion
  /// RQ does not use this — its payload stays empty.
  final dynamic subQuestionsData;

  final String boardYearTag;

  /// Marks for a short question (RQ), from the `short_mark` column.
  /// Ignored for CQ/MCQ. Defaults to 1 when the column is empty.
  final int shortMark;

  // Runtime state (not from API)
  bool isSelected;

  HighSchoolQuestion({
    required this.id,
    required this.className,
    required this.subject,
    required this.chapterNumber,
    required this.chapterName,
    required this.questionType,
    required this.stemText,
    required this.stemImageUrl,
    required this.subQuestionsData,
    required this.boardYearTag,
    this.shortMark = ShortQuestion.defaultMark,
    this.isSelected = false,
  });

  bool get isCq => questionType.toUpperCase() == 'CQ';
  bool get isMcq => questionType.toUpperCase() == 'MCQ';

  /// Short answer question (RQ / সংক্ষিপ্ত প্রশ্ন).
  bool get isShort =>
      questionType.toUpperCase() == 'RQ' ||
      questionType.toUpperCase() == 'SHORT';

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

    return HighSchoolQuestion(
      id: json['id'] as String? ?? '',
      className: json['class'] as String? ?? '',
      subject: json['subject'] as String? ?? '',
      chapterNumber: json['chapter_number'] as String? ?? '',
      chapterName: json['chapter_name'] as String? ?? '',
      questionType: qType,
      stemText: json['stem_text'] as String? ?? '',
      stemImageUrl: json['stem_image_url'] as String? ?? '',
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
    };
  }
}

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
      mark:  (json['mark'] as num?)?.toInt() ?? 0,
      text:  json['text']  as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'label': label,
    'mark':  mark,
    'text':  text,
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
    'text':        text,
    'options':     options,
    'correct_ans': correctAns,
  };
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
    chapterName:   json['chapter_name']   as String? ?? '',
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
  final String questionType; // 'CQ' | 'MCQ'
  final String stemText;
  final String stemImageUrl;

  /// For CQ: List<CqSubQuestion>
  /// For MCQ: McqQuestion
  final dynamic subQuestionsData;

  final String boardYearTag;

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
    this.isSelected = false,
  });

  bool get isCq => questionType.toUpperCase() == 'CQ';
  bool get isMcq => questionType.toUpperCase() == 'MCQ';

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

  /// Total marks for this question
  int get totalMarks {
    if (isCq) {
      return cqSubQuestions.fold(0, (sum, sq) => sum + sq.mark);
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
    } else {
      // MCQ
      if (rawSub is Map<String, dynamic>) {
        parsed = McqQuestion.fromJson(rawSub);
      } else if (rawSub is String) {
        try {
          parsed = McqQuestion.fromJson(
            jsonDecode(rawSub) as Map<String, dynamic>);
        } catch (_) {
          parsed = null;
        }
      } else {
        parsed = null;
      }
    }

    return HighSchoolQuestion(
      id:            json['id']             as String? ?? '',
      className:     json['class']          as String? ?? '',
      subject:       json['subject']        as String? ?? '',
      chapterNumber: json['chapter_number'] as String? ?? '',
      chapterName:   json['chapter_name']   as String? ?? '',
      questionType:  qType,
      stemText:      json['stem_text']      as String? ?? '',
      stemImageUrl:  json['stem_image_url'] as String? ?? '',
      subQuestionsData: parsed,
      boardYearTag:  json['board_year_tag'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    dynamic subJson;
    if (isCq) {
      subJson = cqSubQuestions.map((e) => e.toJson()).toList();
    } else {
      subJson = mcqData?.toJson();
    }

    return {
      'id':               id,
      'class':            className,
      'subject':          subject,
      'chapter_number':   chapterNumber,
      'chapter_name':     chapterName,
      'question_type':    questionType,
      'stem_text':        stemText,
      'stem_image_url':   stemImageUrl,
      'sub_questions_json': subJson,
      'board_year_tag':   boardYearTag,
    };
  }
}

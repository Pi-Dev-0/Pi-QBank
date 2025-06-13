class SubQuestion {
  final String label;
  final String text;
  final int marks;

  SubQuestion({required this.label, required this.text, required this.marks});

  factory SubQuestion.fromJson(Map<String, dynamic> json) {
    return SubQuestion(
      label: json['label'] as String,
      text: json['text'] as String,
      marks: json['marks'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'text': text,
      'marks': marks,
    };
  }
}

class SrojonshilQuestion {
  final int questionNumber;
  final String stem;
  final List<SubQuestion> subQuestions;

  SrojonshilQuestion({
    required this.questionNumber,
    required this.stem,
    required this.subQuestions,
  });

  factory SrojonshilQuestion.fromJson(Map<String, dynamic> json) {
    var list = json['sub_questions'] as List;
    List<SubQuestion> subQuestionsList =
        list.map((i) => SubQuestion.fromJson(i)).toList();

    return SrojonshilQuestion(
      questionNumber: json['question_number'] as int,
      stem: json['stem'] as String,
      subQuestions: subQuestionsList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'question_number': questionNumber,
      'stem': stem,
      'sub_questions': subQuestions.map((e) => e.toJson()).toList(),
    };
  }

  // Helper to convert to a displayable string format
  String toDisplayString() {
    String display =
        '$questionNumber. $stem\n\n'; // Added an extra newline for a gap
    for (var sq in subQuestions) {
      display += '${sq.label}) ${sq.text} (${sq.marks} নম্বর)\n';
    }
    return display.trim();
  }
}

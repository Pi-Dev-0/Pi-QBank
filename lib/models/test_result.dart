
class TestResult {
  final String testId;
  final String testType;
  final DateTime timestamp;
  final int score;
  final int totalQuestions;
  final int timeTakenInSeconds;
  final String language;
  final List<Map<String, dynamic>> questionsAndAnswers; // {question, correctAnswer, userAnswer, isCorrect}
  final List<String> imagePaths; // Paths of the images used

  TestResult({
    required this.testId,
    required this.testType,
    required this.timestamp,
    required this.score,
    required this.totalQuestions,
    required this.timeTakenInSeconds,
    required this.language,
    required this.questionsAndAnswers,
    required this.imagePaths,
  });

  Map<String, dynamic> toJson() {
    return {
      'testId': testId,
      'testType': testType,
      'timestamp': timestamp.toIso8601String(),
      'score': score,
      'totalQuestions': totalQuestions,
      'timeTakenInSeconds': timeTakenInSeconds,
      'language': language,
      'questionsAndAnswers': questionsAndAnswers,
      'imagePaths': imagePaths,
    };
  }

  factory TestResult.fromJson(Map<String, dynamic> json) {
    return TestResult(
      testId: json['testId'],
      testType: json['testType'],
      timestamp: DateTime.parse(json['timestamp']),
      score: json['score'],
      totalQuestions: json['totalQuestions'],
      timeTakenInSeconds: json['timeTakenInSeconds'],
      language: json['language'],
      questionsAndAnswers: (json['questionsAndAnswers'] as List)
          .map((qaJson) => Map<String, dynamic>.from(qaJson))
          .toList(),
      imagePaths: List<String>.from(json['imagePaths']),
    );
  }
}

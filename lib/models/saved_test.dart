import 'package:image_picker/image_picker.dart';

class SavedTest {
  final String id;
  final String testType;
  final int numberOfQuestions;
  final int testTimeInMinutes;
  final List<String> imagePaths;
  final String aiResponse;
  final String language;
  final DateTime savedDate;

  SavedTest({
    required this.id,
    required this.testType,
    required this.numberOfQuestions,
    required this.testTimeInMinutes,
    required this.imagePaths,
    required this.aiResponse,
    required this.language,
    required this.savedDate,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'testType': testType,
        'numberOfQuestions': numberOfQuestions,
        'testTimeInMinutes': testTimeInMinutes,
        'imagePaths': imagePaths,
        'aiResponse': aiResponse,
        'language': language,
        'savedDate': savedDate.toIso8601String(),
      };

  factory SavedTest.fromJson(Map<String, dynamic> json) => SavedTest(
        id: json['id'],
        testType: json['testType'],
        numberOfQuestions: json['numberOfQuestions'],
        testTimeInMinutes: json['testTimeInMinutes'],
        imagePaths: List<String>.from(json['imagePaths']),
        aiResponse: json['aiResponse'],
        language: json['language'],
        savedDate: DateTime.parse(json['savedDate']),
      );

  // Helper to convert image paths back to XFile for test pages
  List<XFile> get selectedImages {
    return imagePaths.map((path) => XFile(path)).toList();
  }
}
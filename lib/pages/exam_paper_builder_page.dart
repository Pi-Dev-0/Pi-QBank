import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/app_config.dart';
import 'package:pi_qbank/widgets/api_key_dialog.dart';
import '../widgets/custom_app_bar.dart';
import 'package:bijoy_helper/bijoy_helper.dart' as bh; // Added for Bijoy conversion
import '../models/srojonshil_question.dart';

class ExamPaperBuilderPage extends StatefulWidget {
  const ExamPaperBuilderPage({super.key});

  @override
  State<ExamPaperBuilderPage> createState() => _ExamPaperBuilderPageState();
}

class _ExamPaperBuilderPageState extends State<ExamPaperBuilderPage>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // Form controllers
  final TextEditingController _examTimeController = TextEditingController();
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _instituteController = TextEditingController();
  final TextEditingController _totalMarksController = TextEditingController();
  final TextEditingController _directionsController = TextEditingController();

  // Question count controllers
  final TextEditingController _creativeSrojonshilCountController =
      TextEditingController();
  final TextEditingController _shortSangkhiptoCountController =
      TextEditingController();
  final TextEditingController _mcqCountController = TextEditingController();

  // Question type checkboxes
  bool _creativeSrojonshil = false;
  bool _shortSangkhipto = false;
  bool _mcqMultipleChoice = false;

  // Image lists for each question type
  final List<File> _creativeSrojonshilImages = [];
  final List<File> _shortSangkhiptoImages = [];
  final List<File> _mcqImages = [];

  // Generated questions
  List<SrojonshilQuestion> _creativeSrojonshilQuestions = [];
  List<String> _shortSangkhiptoQuestions = [];
  List<String> _mcqQuestions = [];

  // Generated answers
  List<String> _shortSangkhiptoAnswers = [];
  List<String> _mcqAnswers = [];

  bool _isGenerating = false;

  // Helper function for Bijoy conversion
  String unicodeToBijoy(String unicodeText) {
    return bh.unicodeToBijoy(unicodeText);
  }

  // Color scheme
  static const Color primaryColor = Color(0xFF4285F4); // Google Blue
  static const Color secondaryColor = Color(0xFF0F9D58); // Google Green
  static const Color accentColor = Color(0xFFDB4437); // Google Red
  static const Color successColor = Color(0xFF0F9D58); // Google Green
  static const Color backgroundColor = Color(0xFFF8F9FA);
  static const Color cardColor = Colors.white;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    _animationController.forward();

    // Set default values
    _examTimeController.text = '৩ ঘন্টা';
    _directionsController.text =
        'নির্দেশনা: সব প্রশ্নের উত্তর দিতে হবে। প্রতিটি প্রশ্নের উত্তর আলাদা খাতায় লিখতে হবে।';

    // Set default question counts
    _creativeSrojonshilCountController.text = '1';
    _shortSangkhiptoCountController.text = '1';
    _mcqCountController.text = '1';
  }

  Future<void> _pickImages(String questionType) async {
    final List<XFile> images = await _picker.pickMultiImage();
    if (images.isNotEmpty) {
      setState(() {
        List<File> imageFiles =
            images.map((image) => File(image.path)).toList();
        switch (questionType) {
          case 'creative':
            _creativeSrojonshilImages.addAll(imageFiles);
            break;
          case 'short':
            _shortSangkhiptoImages.addAll(imageFiles);
            break;
          case 'mcq':
            _mcqImages.addAll(imageFiles);
            break;
        }
      });
    }
  }

  void _removeImage(String questionType, int index) {
    setState(() {
      switch (questionType) {
        case 'creative':
          _creativeSrojonshilImages.removeAt(index);
          break;
        case 'short':
          _shortSangkhiptoImages.removeAt(index);
          break;
        case 'mcq':
          _mcqImages.removeAt(index);
          break;
      }
    });
  }

  Future<Map<String, dynamic>> _generateQuestionsAndAnswersFromImages(
      List<File> images, String questionType, int count) async { // Added count parameter
    String? apiKey =
        await getApiKey(); // Try to get API key from SharedPreferences

    if (apiKey == null || apiKey.isEmpty) {
      // If not found in SharedPreferences, use the default from AppConfig
      apiKey = AppConfig.geminiApiKey;
    }

    if (apiKey.isEmpty) {
      throw Exception('API Key not set. Please enter your API key.');
    }

    final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$apiKey');

    List<String> questions = [];
    List<String> answers = [];

    String prompt = '';
    switch (questionType) {
      case 'creative':
        prompt =
            '''এই ছবি থেকে বাংলায় $countটি সৃজনশীল প্রশ্ন তৈরি করুন। প্রতিটি প্রশ্ন নিম্নলিখিত JSON ফরম্যাটে হবে:
[
  {
    "question_number": 1,
    "stem": "(একটি ছোট অনুচ্ছেদ বা তথ্য)",
    "sub_questions": [
      {
        "label": "ক",
        "text": "জ্ঞানমূলক প্রশ্ন",
        "marks": 1
      },
      {
        "label": "খ",
        "text": "অনুধাবনমূলক প্রশ্ন",
        "marks": 2
      },
      {
        "label": "গ",
        "text": "প্রয়োগমূলক প্রশ্ন",
        "marks": 3
      },
      {
        "label": "ঘ",
        "text": "উচ্চতর দক্ষতামূলক প্রশ্ন",
        "marks": 4
      }
    ]
  }
]
শুধুমাত্র JSON অ্যারে আউটপুট করুন, অন্য কোন টেক্সট বা ব্যাখ্যা নয়।''';
        break;
      case 'short':
        prompt =
            '''এই ছবি থেকে বাংলায় $countটি সংক্ষিপ্ত প্রশ্ন এবং তার উত্তর তৈরি করুন। প্রতিটি প্রশ্ন ২-৫ নম্বরের হবে এবং উত্তর ৫০-১০০ শব্দের মধ্যে হওয়া উচিত।
ফরম্যাট:
প্রশ্ন: [প্রশ্ন]
উত্তর: [উত্তর]

প্রতিটি প্রশ্ন ও উত্তর আলাদাভাবে ক্রমিক নম্বর দিয়ে শুরু করুন (যেমন: ১. প্রশ্ন: [প্রশ্ন]\nউত্তর: [উত্তর], ২. প্রশ্ন: [প্রশ্ন]\nউত্তর: [উত্তর])। প্রশ্ন ও উত্তর বাংলায় লিখুন।''';
        break;
      case 'mcq':
        prompt =
            '''এই ছবি থেকে বাংলায় $countটি বহুনির্বাচনি প্রশ্ন (MCQ) তৈরি করুন। প্রতিটি প্রশ্নে:
১. প্রশ্ন
২. চারটি অপশন (ক, খ, গ, ঘ)
৩. সঠিক উত্তর নির্দেশ করুন

ফরম্যাট:
প্রশ্ন: [প্রশ্ন]
ক) [অপশন ক]
খ) [অপশন খ]
গ) [অপশন গ]
ঘ) [অপশন ঘ]
সঠিক উত্তর: [সঠিক অপশন, যেমন ক)]

প্রতিটি প্রশ্ন আলাদাভাবে ক্রমিক নম্বর দিয়ে শুরু করুন (যেমন: ১. প্রশ্ন: [প্রশ্ন]..., ২. প্রশ্ন: [প্রশ্ন]...)। প্রশ্ন, অপশন এবং সঠিক উত্তর সব বাংলায় লিখুন।''';
        break;
    }

    for (File image in images) {
      try {
        final imageBytes = await image.readAsBytes();
        final base64Image = base64Encode(imageBytes);

        List<Map<String, dynamic>> contents = [];
        contents.add({
          "role": "user",
          "parts": [
            {
              "inline_data": {"mime_type": "image/jpeg", "data": base64Image}
            },
            {"text": prompt}
          ]
        });

        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({"contents": contents}),
        );

        if (response.statusCode == 200) {
          final jsonResponse = json.decode(response.body);
          if (jsonResponse['candidates'] != null &&
              jsonResponse['candidates'].isNotEmpty) {
            final reply = jsonResponse['candidates'][0]['content']['parts'][0]['text'];
            debugPrint('Raw API Reply (Diagnostic): $reply');

            if (questionType == 'creative') {
              try {
                String jsonString = reply.trim();
                debugPrint('Diagnostic: JSON string before markdown removal: $jsonString');
                // Remove markdown code block fences if present
                if (jsonString.startsWith('```json') && jsonString.endsWith('```')) {
                  jsonString = jsonString.substring(7, jsonString.length - 3).trim();
                  debugPrint('Diagnostic: JSON string after markdown removal: $jsonString');
                } else {
                  debugPrint('Diagnostic: No markdown fences found.');
                }

                // Attempt to parse the JSON
                final List<dynamic> jsonList = json.decode(jsonString);
                _creativeSrojonshilQuestions = jsonList.map((e) => SrojonshilQuestion.fromJson(e)).toList();
                debugPrint('Diagnostic: Successfully parsed ${_creativeSrojonshilQuestions.length} creative questions.');
                return {'questions': [], 'answers': []}; // Creative questions are handled directly
              } catch (e) {
                debugPrint('Error parsing creative questions JSON: $e');
                debugPrint('Diagnostic: Failed JSON string: $reply'); // Print the problematic reply
                _creativeSrojonshilQuestions = []; // Clear on error
                return {'questions': [], 'answers': []};
              }
            } else {
              // This block handles 'short' and 'mcq' question types
              List<String> rawQuestions = [];
              // Use Bengali numerals in regex
              final questionStartRegex = RegExp(r'[০-৯]+\.', dotAll: true);

              final startMatches = questionStartRegex.allMatches(reply).toList();

              debugPrint('Diagnostic: Number of question start matches: ${startMatches.length}');

              if (startMatches.isEmpty) {
                debugPrint('No question start matches found in reply with diagnostic regex.');
                return {'questions': [], 'answers': []};
              }

              for (int i = 0; i < startMatches.length; i++) {
                final start = startMatches[i].start;
                int end;
                if (i + 1 < startMatches.length) {
                  end = startMatches[i + 1].start;
                } else {
                  end = reply.length; // Last question goes to the end of the reply
                }
                String qText = reply.substring(start, end).trim();
                debugPrint('Diagnostic: Extracted $questionType qText: $qText');
                rawQuestions.add(qText);
              }

              for (String qText in rawQuestions) {
                if (questionType == 'short') {
                  final questionMatch =
                      RegExp(r'প্রশ্ন:\s*(.*?)\nউত্তর:\s*(.*)', dotAll: true)
                          .firstMatch(qText);
                  if (questionMatch != null) {
                    questions.add(questionMatch.group(1)!.trim());
                    answers.add(questionMatch.group(2)!.trim());
                  } else {
                    questions.add(qText);
                    answers.add('উত্তর পাওয়া যায়নি');
                  }
                } else if (questionType == 'mcq') {
                  final questionMatch =
                      RegExp(r'প্রশ্ন:\s*(.*?)\n(.*?)\nসঠিক উত্তর:\s*(.*)', dotAll: true)
                          .firstMatch(qText);
                  if (questionMatch != null) {
                    questions.add(
                        '${questionMatch.group(1)!.trim()}\n${questionMatch.group(2)!.trim()}');
                    answers.add(questionMatch.group(3)!.trim());
                  } else {
                    questions.add(qText);
                    answers.add('সঠিক উত্তর পাওয়া যায়নি');
                  }
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Error generating question from image: $e');
      }
    }

    return {'questions': questions, 'answers': answers};
  }

  Future<void> _generateQuestions() async {
    setState(() {
      _isGenerating = true;
    });

    try {
      if (_creativeSrojonshil && _creativeSrojonshilImages.isNotEmpty) {
        final int count = int.tryParse(_creativeSrojonshilCountController.text) ?? 1;
        // _creativeSrojonshilQuestions is populated directly within _generateQuestionsAndAnswersFromImages
        await _generateQuestionsAndAnswersFromImages(
            _creativeSrojonshilImages, 'creative', count); // Pass count
      } else {
        _creativeSrojonshilQuestions = [];
      }

      if (_shortSangkhipto && _shortSangkhiptoImages.isNotEmpty) {
        final int count = int.tryParse(_shortSangkhiptoCountController.text) ?? 1;
        final result = await _generateQuestionsAndAnswersFromImages(
            _shortSangkhiptoImages, 'short', count); // Pass count
        _shortSangkhiptoQuestions = result['questions']!;
        _shortSangkhiptoAnswers = result['answers']!;
      } else {
        _shortSangkhiptoQuestions = [];
        _shortSangkhiptoAnswers = [];
      }

      if (_mcqMultipleChoice && _mcqImages.isNotEmpty) {
        final int count = int.tryParse(_mcqCountController.text) ?? 1;
        final result = await _generateQuestionsAndAnswersFromImages(
            _mcqImages, 'mcq', count); // Pass count
        _mcqQuestions = result['questions']!;
        _mcqAnswers = result['answers']!;
      } else {
        _mcqQuestions = [];
        _mcqAnswers = [];
      }

      if (!mounted) return;
      if (_hasGeneratedQuestions()) {
        _showSuccessSnackBar('প্রশ্ন সফলভাবে তৈরি হয়েছে!');
      } else {
        _showErrorSnackBar('প্রশ্ন তৈরি করা যায়নি।');
      }
      debugPrint('Creative Questions: ${_creativeSrojonshilQuestions.length}');
      debugPrint('Short Questions: ${_shortSangkhiptoQuestions.length}');
      debugPrint('MCQ Questions: ${_mcqQuestions.length}');
      debugPrint('Has Generated Questions: ${_hasGeneratedQuestions()}');
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar('ত্রুটি: $e');
    } finally {
      setState(() {
        _isGenerating = false;
      });
    }
  }


  Future<void> _generateQuestionPDF() async {
    final pdf = pw.Document();

    // Load SutonnyMJ font
    final fontData = await rootBundle.load('assets/fonts/SutonnyMJ Regular.ttf');
    final font = pw.Font.ttf(fontData);
    final boldFont = font;

    pdf.addPage(
      pw.MultiPage(
        theme: pw.ThemeData.withFont(
          base: font,
          bold: boldFont,
        ),
        build: (pw.Context context) {
          return [
            // Header
            pw.Center(
              child: pw.Column(
                children: [
                  pw.Text(
                    unicodeToBijoy(_instituteController.text),
                    style: pw.TextStyle(
                        fontSize: 18, fontWeight: pw.FontWeight.bold, font: boldFont),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Text(
                    unicodeToBijoy('বিষয়: ${_subjectController.text}'),
                    style: pw.TextStyle(
                        fontSize: 16, fontWeight: pw.FontWeight.bold, font: boldFont),
                  ),
                  pw.SizedBox(height: 5),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(unicodeToBijoy('সময়: ${_examTimeController.text}'), style: pw.TextStyle(font: font)),
                      pw.Text(unicodeToBijoy('পূর্ণমান: ${_totalMarksController.text}'), style: pw.TextStyle(font: font)),
                    ],
                  ),
                  pw.SizedBox(height: 20),
                ],
              ),
            ),

            // Directions
            if (_directionsController.text.isNotEmpty) ...[
              pw.Center(
                child: pw.Text(
                  unicodeToBijoy(_directionsController.text),
                  style:
                      pw.TextStyle(fontSize: 12, fontStyle: pw.FontStyle.italic, font: font),
                ),
              ),
              pw.SizedBox(height: 20),
            ],

            // Creative Questions
            if (_creativeSrojonshil &&
                _creativeSrojonshilQuestions.isNotEmpty) ...[
              pw.Center(
                child: pw.Text(
                  unicodeToBijoy('সৃজনশীল প্রশ্ন'),
                  style:
                      pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, font: boldFont),
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Column(
                children: [
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: List.generate(
                            (_creativeSrojonshilQuestions.length / 2).ceil(),
                            (index) {
                              final question = _creativeSrojonshilQuestions[index];
                              return pw.Container(
                                margin: pw.EdgeInsets.only(bottom: 20),
                                child: pw.Column(
                                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                                  children: [
                                    pw.Text(
                                      unicodeToBijoy('${question.questionNumber}. ${question.stem}'),
                                      style: pw.TextStyle(fontSize: 12, font: boldFont),
                                    ),
                                    pw.SizedBox(height: 5),
                                    ...question.subQuestions.map(
                                      (subQ) => pw.Row(
                                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                        children: [
                                          pw.Expanded(
                                            child: pw.Text(
                                              unicodeToBijoy('${subQ.label}) ${subQ.text}'),
                                              style: pw.TextStyle(fontSize: 12, font: font),
                                            ),
                                          ),
                                          pw.Text(
                                            unicodeToBijoy('(${subQ.marks})'),
                                            style: pw.TextStyle(fontSize: 12, font: font),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      pw.SizedBox(width: 20), // Space between columns
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: List.generate(
                            _creativeSrojonshilQuestions.length ~/ 2,
                            (index) {
                              final actualIndex = (_creativeSrojonshilQuestions.length / 2).ceil() + index;
                              final question = _creativeSrojonshilQuestions[actualIndex];
                              return pw.Container(
                                margin: pw.EdgeInsets.only(bottom: 20),
                                child: pw.Column(
                                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                                  children: [
                                    pw.Text(
                                      unicodeToBijoy('${question.questionNumber}. ${question.stem}'),
                                      style: pw.TextStyle(fontSize: 12, font: boldFont),
                                    ),
                                    pw.SizedBox(height: 5),
                                    ...question.subQuestions.map(
                                      (subQ) => pw.Row(
                                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                        children: [
                                          pw.Expanded(
                                            child: pw.Text(
                                              unicodeToBijoy('${subQ.label}) ${subQ.text}'),
                                              style: pw.TextStyle(fontSize: 12, font: font),
                                            ),
                                          ),
                                          pw.Text(
                                            unicodeToBijoy('(${subQ.marks})'),
                                            style: pw.TextStyle(fontSize: 12, font: font),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],

            // Short Questions
            if (_shortSangkhipto && _shortSangkhiptoQuestions.isNotEmpty) ...[
              pw.Center(
                child: pw.Text(
                  unicodeToBijoy('সংক্ষিপ্ত প্রশ্ন'),
                  style:
                      pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, font: boldFont),
                ),
              ),
              pw.SizedBox(height: 10),
              ...List.generate(
                _shortSangkhiptoQuestions.length,
                (index) => pw.Container(
                  margin: pw.EdgeInsets.only(bottom: 15),
                  child: pw.Text(
                    unicodeToBijoy('${index + 1}. ${_shortSangkhiptoQuestions[index]}'),
                    style: pw.TextStyle(fontSize: 12, font: font),
                  ),
                ),
              ),
            ],

            // MCQ Questions
            if (_mcqMultipleChoice && _mcqQuestions.isNotEmpty) ...[
              pw.Center(
                child: pw.Text(
                  unicodeToBijoy('বহুনির্বাচনি প্রশ্ন'),
                  style:
                      pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, font: boldFont),
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Column(
                children: [
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: List.generate(
                            (_mcqQuestions.length / 2).ceil(),
                            (index) => pw.Container(
                              margin: pw.EdgeInsets.only(bottom: 15),
                              child: pw.Text(
                                unicodeToBijoy('${index + 1}. ${_mcqQuestions[index]}'),
                                style: pw.TextStyle(fontSize: 12, font: font),
                              ),
                            ),
                          ),
                        ),
                      ),
                      pw.SizedBox(width: 20), // Space between columns
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: List.generate(
                            _mcqQuestions.length ~/ 2,
                            (index) {
                              final actualIndex = (_mcqQuestions.length / 2).ceil() + index;
                              return pw.Container(
                                margin: pw.EdgeInsets.only(bottom: 15),
                                child: pw.Text(
                                  unicodeToBijoy('${actualIndex + 1}. ${_mcqQuestions[actualIndex]}'),
                                  style: pw.TextStyle(fontSize: 12, font: font),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  Future<void> _generateAnswerPDF() async {
    final answersPdf = pw.Document();

    // Load SutonnyMJ font
    final fontData = await rootBundle.load('assets/fonts/SutonnyMJ Regular.ttf');
    final font = pw.Font.ttf(fontData);
    final boldFont = font;

    answersPdf.addPage(
      pw.MultiPage(
        theme: pw.ThemeData.withFont(
          base: font,
          bold: boldFont,
        ),
        build: (pw.Context context) {
          return [
            pw.Center(
              child: pw.Column(
                children: [
                  pw.Text(
                    unicodeToBijoy(_instituteController.text),
                    style: pw.TextStyle(
                        fontSize: 18, fontWeight: pw.FontWeight.bold, font: boldFont),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Text(
                    unicodeToBijoy('বিষয়: ${_subjectController.text}'),
                    style: pw.TextStyle(
                        fontSize: 16, fontWeight: pw.FontWeight.bold, font: boldFont),
                  ),
                  pw.SizedBox(height: 20),
                  pw.Text(
                    unicodeToBijoy('উত্তরপত্র'),
                    style: pw.TextStyle(
                        fontSize: 20, fontWeight: pw.FontWeight.bold, font: boldFont),
                  ),
                  pw.SizedBox(height: 20),
                ],
              ),
            ),
            if (_shortSangkhipto && _shortSangkhiptoAnswers.isNotEmpty) ...[
              pw.Center(
                child: pw.Text(
                  unicodeToBijoy('সংক্ষিপ্ত প্রশ্নের উত্তর'),
                  style:
                      pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, font: boldFont),
                ),
              ),
              pw.SizedBox(height: 10),
              ...List.generate(
                _shortSangkhiptoAnswers.length,
                (index) => pw.Container(
                  margin: pw.EdgeInsets.only(bottom: 15),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        unicodeToBijoy('প্রশ্ন ${index + 1}.'),
                        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, font: font),
                      ),
                      pw.Text(
                        unicodeToBijoy(_shortSangkhiptoAnswers[index]),
                        style: pw.TextStyle(fontSize: 12, font: font),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (_mcqMultipleChoice && _mcqAnswers.isNotEmpty) ...[
              pw.SizedBox(height: 20),
              pw.Text(
                unicodeToBijoy('বহুনির্বাচনি প্রশ্নের উত্তর'),
                style:
                    pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, font: boldFont),
              ),
              pw.SizedBox(height: 10),
              ...List.generate(
                _mcqAnswers.length,
                (index) => pw.Container(
                  margin: pw.EdgeInsets.only(bottom: 15),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        unicodeToBijoy('প্রশ্ন ${index + 1}.'),
                        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, font: font),
                      ),
                      pw.Text(
                        unicodeToBijoy(_mcqAnswers[index]),
                        style: pw.TextStyle(fontSize: 12, font: font),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => answersPdf.save(),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: accentColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildGradientCard({required Widget child, List<Color>? colors}) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors ?? [cardColor, cardColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildCustomTextField({
    required TextEditingController controller,
    required String labelText,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    bool required = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: '$labelText${required ? ' *' : ''}',
          prefixIcon: Icon(icon, color: primaryColor),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: primaryColor, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: accentColor, width: 2),
          ),
          filled: true,
          fillColor: Colors.grey.shade50,
          labelStyle: TextStyle(color: Colors.grey.shade700),
        ),
        validator: validator,
        keyboardType: keyboardType,
        maxLines: maxLines,
      ),
    );
  }

  Widget _buildQuestionTypeCard({
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool?) onChanged,
    required String questionType,
    required List<File> images,
    required IconData icon,
    required Color color,
    required TextEditingController countController,
  }) {
    return _buildGradientCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Transform.scale(
                  scale: 1.2,
                  child: Checkbox(
                    value: value,
                    onChanged: onChanged,
                    activeColor: color,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
            if (value) ...[
              const SizedBox(height: 20),
              _buildCustomTextField(
                controller: countController,
                labelText: 'প্রশ্নের সংখ্যা',
                icon: Icons.numbers,
                keyboardType: TextInputType.number,
                required: true,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'প্রশ্নের সংখ্যা প্রয়োজন';
                  }
                  if (int.tryParse(value) == null || int.parse(value) <= 0) {
                    return 'একটি বৈধ সংখ্যা লিখুন';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _pickImages(questionType),
                  icon: const Icon(Icons.add_photo_alternate),
                  label: const Text('ছবি যোগ করুন'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (images.isNotEmpty)
                SizedBox(
                  height: 120,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: images.length,
                    itemBuilder: (context, index) {
                      return Container(
                        margin: const EdgeInsets.only(right: 12),
                        child: Stack(
                          children: [
                            Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                image: DecorationImage(
                                  image: FileImage(images[index]),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            Positioned(
                              top: -8,
                              right: -8,
                              child: GestureDetector(
                                onTap: () => _removeImage(questionType, index),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: accentColor,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedButton({
    required String text,
    required VoidCallback? onPressed,
    required Color backgroundColor,
    required IconData icon,
    bool isLoading = false,
    double width = double.infinity,
  }) {
    return SizedBox(
      width: width,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Icon(icon),
        label: Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
          shadowColor: backgroundColor.withValues(alpha:0.3),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: const CustomAppBar(
        title: 'পরীক্ষার প্রশ্নপত্র তৈরি করুন',
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // API Key Section
                _buildGradientCard(
                  colors: [
                    primaryColor.withValues(alpha:0.1),
                    secondaryColor.withValues(alpha:0.1)
                  ],
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha:0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.vpn_key,
                              color: primaryColor, size: 24),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'API Key সেটআপ',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Gemini API key সেট করুন প্রশ্ন তৈরির জন্য',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () => showApiKeyDialog(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('সেট করুন'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Basic Information
                _buildGradientCard(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: primaryColor.withValues(alpha:0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.info_outline,
                                  color: primaryColor),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'মৌলিক তথ্য',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _buildCustomTextField(
                          controller: _instituteController,
                          labelText: 'প্রতিষ্ঠানের নাম',
                          icon: Icons.school,
                          required: true,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'প্রতিষ্ঠানের নাম প্রয়োজন';
                            }
                            return null;
                          },
                        ),
                        _buildCustomTextField(
                          controller: _subjectController,
                          labelText: 'বিষয়ের নাম',
                          icon: Icons.subject,
                          required: true,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'বিষয়ের নাম প্রয়োজন';
                            }
                            return null;
                          },
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: _buildCustomTextField(
                                controller: _totalMarksController,
                                labelText: 'মোট নম্বর',
                                icon: Icons.grade,
                                keyboardType: TextInputType.number,
                                required: true,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'মোট নম্বর প্রয়োজন';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildCustomTextField(
                                controller: _examTimeController,
                                labelText: 'পরীক্ষার সময়',
                                icon: Icons.access_time,
                              ),
                            ),
                          ],
                        ),
                        _buildCustomTextField(
                          controller: _directionsController,
                          labelText: 'পরীক্ষার্থীদের জন্য নির্দেশনা',
                          icon: Icons.description,
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Question Types Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: secondaryColor.withValues(alpha:0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.quiz, color: secondaryColor),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'প্রশ্নের ধরন নির্বাচন করুন',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Question Types
                _buildQuestionTypeCard(
                  title: 'সৃজনশীল প্রশ্ন',
                  subtitle: 'উদ্দীপক সহ ৪ ধাপের প্রশ্ন',
                  value: _creativeSrojonshil,
                  onChanged: (value) {
                    setState(() {
                      _creativeSrojonshil = value!;
                    });
                  },
                  questionType: 'creative',
                  images: _creativeSrojonshilImages,
                  icon: Icons.create,
                  color: primaryColor,
                  countController: _creativeSrojonshilCountController,
                ),
                const SizedBox(height: 16),

                _buildQuestionTypeCard(
                  title: 'সংক্ষিপ্ত প্রশ্ন',
                  subtitle: '২-৫ নম্বরের সংক্ষিপ্ত প্রশ্ন',
                  value: _shortSangkhipto,
                  onChanged: (value) {
                    setState(() {
                      _shortSangkhipto = value!;
                    });
                  },
                  questionType: 'short',
                  images: _shortSangkhiptoImages,
                  icon: Icons.short_text,
                  color: secondaryColor,
                  countController: _shortSangkhiptoCountController,
                ),
                const SizedBox(height: 16),

                _buildQuestionTypeCard(
                  title: 'বহুনির্বাচনি প্রশ্ন (MCQ)',
                  subtitle: '৪টি অপশন সহ MCQ প্রশ্ন',
                  value: _mcqMultipleChoice,
                  onChanged: (value) {
                    setState(() {
                      _mcqMultipleChoice = value!;
                    });
                  },
                  questionType: 'mcq',
                  images: _mcqImages,
                  icon: Icons.radio_button_checked,
                  color: accentColor,
                  countController: _mcqCountController,
                ),
                const SizedBox(height: 24),

                // Action Buttons
                _buildAnimatedButton(
                  text: 'প্রশ্ন তৈরি করুন',
                  onPressed: (_isGenerating || !_hasSelectedTypeWithImages())
                      ? null
                      : _generateQuestions,
                  backgroundColor: Color(0xFF6C63FF), //set color to violet
                  icon: Icons.auto_awesome,
                  isLoading: _isGenerating,
                ),
                if (_hasGeneratedQuestions()) ...[
                  const SizedBox(height: 16),
                  _buildAnimatedButton(
                    text: 'প্রশ্নপত্র PDF তৈরি করুন',
                    onPressed: (_hasGeneratedQuestions() &&
                            _formKey.currentState?.validate() == true)
                        ? _generateQuestionPDF
                        : null,
                    backgroundColor: primaryColor,
                    icon: Icons.picture_as_pdf,
                  ),
                  const SizedBox(height: 16),
                  _buildAnimatedButton(
                    text: 'উত্তরপত্র PDF তৈরি করুন',
                    onPressed: (_hasGeneratedQuestions() &&
                            _formKey.currentState?.validate() == true &&
                            (_shortSangkhiptoAnswers.isNotEmpty || _mcqAnswers.isNotEmpty))
                        ? _generateAnswerPDF
                        : null,
                    backgroundColor: secondaryColor,
                    icon: Icons.assignment_turned_in,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _showGeneratedQuestions,
                          icon: const Icon(Icons.preview),
                          label: const Text('প্রশ্ন দেখুন'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            foregroundColor: Color(0xFF6C63FF),
                            side: const BorderSide(color: Color(0xFF6C63FF)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saveTemplate,
                          icon: const Icon(Icons.save),
                          label: const Text('টেমপ্লেট সংরক্ষণ'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            foregroundColor: Color(0xFF6C63FF),
                            side: const BorderSide(color: Color(0xFF6C63FF)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _hasSelectedTypeWithImages() {
    return (_creativeSrojonshil && _creativeSrojonshilImages.isNotEmpty) ||
        (_shortSangkhipto && _shortSangkhiptoImages.isNotEmpty) ||
        (_mcqMultipleChoice && _mcqImages.isNotEmpty);
  }

  bool _hasGeneratedQuestions() {
    return _creativeSrojonshilQuestions.isNotEmpty ||
        _shortSangkhiptoQuestions.isNotEmpty ||
        _mcqQuestions.isNotEmpty;
  }

  void _showGeneratedQuestions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('তৈরি হওয়া প্রশ্নসমূহ'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_creativeSrojonshilQuestions.isNotEmpty) ...[
                  Text('সৃজনশীল প্রশ্ন:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  ...List.generate(
                    _creativeSrojonshilQuestions.length,
                    (index) {
                      final question = _creativeSrojonshilQuestions[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${question.questionNumber}. ${question.stem}',
                              style: const TextStyle(fontWeight: FontWeight.bold), // Bold for stem
                            ),
                            const SizedBox(height: 4), // Small gap after stem
                            ...question.subQuestions.map(
                              (subQ) => Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${subQ.label}) ${subQ.text}',
                                    ),
                                  ),
                                  Text(
                                    '(${subQ.marks})', // Just marks, no "নম্বর"
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  SizedBox(height: 16),
                ],
                if (_shortSangkhiptoQuestions.isNotEmpty) ...[
                  Text('সংক্ষিপ্ত প্রশ্ন:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  ...List.generate(
                    _shortSangkhiptoQuestions.length,
                    (index) => Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                          '${index + 1}. ${_shortSangkhiptoQuestions[index]}'),
                    ),
                  ),
                  SizedBox(height: 16),
                ],
                if (_mcqQuestions.isNotEmpty) ...[
                  Text('বহুনির্বাচনি প্রশ্ন:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  ...List.generate(
                    _mcqQuestions.length,
                    (index) => Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('${index + 1}. ${_mcqQuestions[index]}'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('বন্ধ করুন'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _editQuestions();
            },
            child: Text('সম্পাদনা করুন'),
          ),
        ],
      ),
    );
  }

  void _editQuestions() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('প্রশ্ন সম্পাদনা করুন'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  TabBar(
                    tabs: [
                      Tab(text: 'সৃজনশীল'),
                      Tab(text: 'সংক্ষিপ্ত'),
                      Tab(text: 'MCQ'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        // Creative Questions Edit
                        ListView.builder(
                          itemCount: _creativeSrojonshilQuestions.length,
                          itemBuilder: (context, index) => Card(
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: Column(
                                children: [
                                  TextFormField(
                                    initialValue: _creativeSrojonshilQuestions[index].toDisplayString(),
                                    maxLines: 5,
                                    readOnly: true, // Make it read-only for now
                                    decoration: const InputDecoration(
                                      labelText: 'সৃজনশীল প্রশ্ন (সম্পাদনা বর্তমানে সমর্থিত নয়)',
                                      border: OutlineInputBorder(),
                                    ),
                                    // onChanged: (value) {
                                    //   // Direct modification of SrojonshilQuestion object from string is complex
                                    //   // A more robust UI would be needed for editing structured data
                                    // },
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.delete,
                                            color: Colors.red),
                                        onPressed: () {
                                          setState(() {
                                            _creativeSrojonshilQuestions
                                                .removeAt(index);
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Short Questions Edit
                        ListView.builder(
                          itemCount: _shortSangkhiptoQuestions.length,
                          itemBuilder: (context, index) => Card(
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: Column(
                                children: [
                                  TextFormField(
                                    initialValue:
                                        _shortSangkhiptoQuestions[index],
                                    maxLines: 3,
                                    onChanged: (value) {
                                      _shortSangkhiptoQuestions[index] = value;
                                    },
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.delete,
                                            color: Colors.red),
                                        onPressed: () {
                                          setState(() {
                                            _shortSangkhiptoQuestions
                                                .removeAt(index);
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // MCQ Questions Edit
                        ListView.builder(
                          itemCount: _mcqQuestions.length,
                          itemBuilder: (context, index) => Card(
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: Column(
                                children: [
                                  TextFormField(
                                    initialValue: _mcqQuestions[index],
                                    maxLines: 4,
                                    onChanged: (value) {
                                      _mcqQuestions[index] = value;
                                    },
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.delete,
                                            color: Colors.red),
                                        onPressed: () {
                                          setState(() {
                                            _mcqQuestions.removeAt(index);
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('বন্ধ করুন'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                this.setState(() {}); // Refresh main UI
              },
              child: Text('সংরক্ষণ করুন'),
            ),
          ],
        ),
      ),
    );
  }

  void _saveTemplate() {
    // You can implement saving exam templates for reuse
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('টেমপ্লেট সংরক্ষণ'),
        content: TextFormField(
          decoration: InputDecoration(
            labelText: 'টেমপ্লেটের নাম',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('বাতিল'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('টেমপ্লেট সংরক্ষিত হয়েছে!')),
              );
            },
            child: Text('সংরক্ষণ'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _examTimeController.dispose();
    _subjectController.dispose();
    _instituteController.dispose();
    _totalMarksController.dispose();
    _directionsController.dispose();
    _creativeSrojonshilCountController.dispose();
    _shortSangkhiptoCountController.dispose();
    _mcqCountController.dispose();
    super.dispose();
  }
}

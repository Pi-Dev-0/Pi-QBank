import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/app_config.dart';
import 'short_test_page.dart';
import 'mcq_test_page.dart'; // Add this line
import 'short_question_page.dart'; // Add this line
import 'package:pi_qbank/widgets/custom_app_bar.dart';
import 'package:logger/logger.dart';

class PrepareShortTestPage extends StatefulWidget {
  const PrepareShortTestPage({super.key});

  @override
  State<PrepareShortTestPage> createState() => _PrepareShortTestPageState();
}

class _PrepareShortTestPageState extends State<PrepareShortTestPage> {
  final logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 5,
      lineLength: 50,
      colors: true,
      printEmojis: true,
      printTime: true,
    ),
  );

  String? _selectedTestType;
  int? _numberOfQuestions;
  int? _testTimeInMinutes;
  XFile? _selectedImage;
  String? _selectedImageMimeType; // New variable to store MIME type
  String _aiResponse = '';
  bool _isProcessingImage = false;
  String _selectedLanguage = 'English'; // Default language

  @override
  void initState() {
    super.initState();
  }

  Future<void> _pickImage() async {
    logger.i('PrepareShortTest - _pickImage called');
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1200,
        maxHeight: 1200,
      );

      if (image != null) {
        logger
            .i('PrepareShortTest - Image selected successfully: ${image.path}');
        final File file = File(image.path);
        if (await file.exists()) {
          setState(() {
            _selectedImage = image;
            _selectedImageMimeType = image.mimeType; // Store MIME type
            _aiResponse = '';
          });
        } else {
          throw Exception('Selected image file does not exist');
        }
      }
    } catch (e) {
      logger.e('PrepareShortTest - Error picking image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error selecting image: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _getAIInstructions(String testType) {
    final int questionsCount = _numberOfQuestions ?? 4;
    final String languageInstruction = _selectedLanguage == 'বাংলা'
        ? 'Generate questions in Bengali (Bangla) language. '
        : '';

    switch (testType) {
      case 'MCQ Test':
        return '''
${languageInstruction}Generate $questionsCount multiple choice questions about this image with 4 options each. 
Respond in the following JSON format:

{
  "questions": [
    {
      "question": "Question text?",
      "options": {
        "A": "Option A",
        "B": "Option B",
        "C": "Option C",
        "D": "Option D"
      },
      "correct_answer": "A"
    },
    ...
  ]
}
''';
      case 'Short Question':
        return '${languageInstruction}Generate $questionsCount short answer questions about this image that require brief explanations. Each answer should be 1-3 words.';
      case 'Fill In the Blanks':
        return '${languageInstruction}Generate $questionsCount fill-in-the-blank questions about this image. Format: Question with _____ for blanks, followed by the correct answer.';
      default:
        return '${languageInstruction}Generate questions about this image suitable for a test.';
    }
  }

  Future<void> _sendImageToGemini() async {
    logger.i('PrepareShortTest - Sending image to Gemini API');
    if (_selectedImage == null || _selectedTestType == null) return;

    setState(() {
      _isProcessingImage = true;
      logger.i('PrepareShortTest - Processing started');
      _aiResponse = 'Processing image...';
    });

    try {
      final String apiKey = AppConfig.geminiApiKey;
      final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$apiKey');

      // Create a single list of parts for the multimodal prompt
      List<Map<String, dynamic>> parts = [];

      final bytes = await _selectedImage!.readAsBytes();
      // Check image size before encoding and sending
      const int maxImageSize = 15 * 1024 * 1024; // 15 MB
      if (bytes.length > maxImageSize) {
        logger.w(
            'PrepareShortTest - Image size too large: ${bytes.length} bytes');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Selected image is too large. Please choose a smaller image (max 15MB).'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isProcessingImage = false;
        });
        return;
      }

      final base64Image = base64Encode(bytes);
      // Add the image part
      parts.add({
        "inline_data": {
          "mime_type": _selectedImageMimeType ?? 'image/jpeg',
          "data": base64Image
        }
      });

      // Add the text prompt part
      String prompt = _getAIInstructions(_selectedTestType!);
      parts.add({"text": prompt});

      // Create the contents list with a single entry for the user's multimodal turn
      List<Map<String, dynamic>> contents = [
        {"role": "user", "parts": parts}
      ];

      logger.i(
          'PrepareShortTest - Sending API request with test type: $_selectedTestType');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({"contents": contents}),
      );

      if (response.statusCode == 200) {
        logger.i('PrepareShortTest - API request successful');
        final jsonResponse = json.decode(response.body);
        if (jsonResponse['candidates'] != null &&
            jsonResponse['candidates'].isNotEmpty) {
          final reply =
              jsonResponse['candidates'][0]['content']['parts'][0]['text'];
          setState(() {
            _aiResponse = reply;
          });
        } else {
          throw Exception('Invalid response format or empty candidates');
        }
      } else {
        logger.e(
            'PrepareShortTest - API request failed with status: ${response.statusCode}');
        throw Exception(
            'Failed to get AI understanding. Status: ${response.statusCode}, Body: ${response.body}');
      }
    } catch (e) {
      logger.e('PrepareShortTest - Error in API request: $e');
      setState(() {
        _aiResponse = 'Error: ${e.toString()}';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error getting AI understanding: ${e.toString()}')),
      );
    } finally {
      setState(() {
        _isProcessingImage = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    logger.i('PrepareShortTest - Building UI');
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Prepare Short Test',
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                labelText: 'Test Type',
                prefixIcon: const Icon(Icons.assignment),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                  borderSide: BorderSide(color: Colors.grey[300]!, width: 1.0),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                  borderSide: BorderSide(
                      color: Theme.of(context).primaryColor, width: 2.0),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16.0, vertical: 12.0),
                filled: true,
                fillColor: Theme.of(context).inputDecorationTheme.fillColor ??
                    Colors.grey[100],
              ),
              value: _selectedTestType,
              hint: const Text('Select Test Type'),
              items: <String>[
                'MCQ Test',
                'Short Question',
                'Fill In the Blanks',
              ].map<DropdownMenuItem<String>>((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 10.0, horizontal: 8.0),
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 16.0,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                  ),
                );
              }).toList(),
              onChanged: (String? newValue) {
                logger.i('PrepareShortTest - Test type changed to: $newValue');
                setState(() {
                  _selectedTestType = newValue;
                });
              },
              dropdownColor: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12.0),
              elevation: 8,
              icon: Icon(Icons.arrow_drop_down,
                  color: Theme.of(context).primaryColor),
              isExpanded: true,
              selectedItemBuilder: (BuildContext context) {
                return <String>[
                  'MCQ Test',
                  'Short Question',
                  'Fill In the Blanks',
                ].map<Widget>((String item) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      item,
                      style: TextStyle(
                        fontSize: 16.0,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                  );
                }).toList();
              },
            ),
            const SizedBox(height: 16.0),
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                labelText: 'Select Language',
                prefixIcon: const Icon(Icons.language),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                  borderSide: BorderSide(color: Colors.grey[300]!, width: 1.0),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                  borderSide: BorderSide(
                      color: Theme.of(context).primaryColor, width: 2.0),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16.0, vertical: 12.0),
                filled: true,
                fillColor: Theme.of(context).inputDecorationTheme.fillColor ??
                    Colors.grey[100],
              ),
              value: _selectedLanguage,
              items: ['English', 'বাংলা'].map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setState(() {
                    _selectedLanguage = newValue;
                  });
                }
              },
              dropdownColor: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12.0),
              elevation: 8,
              icon: Icon(Icons.arrow_drop_down,
                  color: Theme.of(context).primaryColor),
              isExpanded: true,
              selectedItemBuilder: (BuildContext context) {
                return <String>[
                  'English',
                  'বাংলা',
                ].map<Widget>((String item) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      item,
                      style: TextStyle(
                        fontSize: 16.0,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                  );
                }).toList();
              },
            ),
            const SizedBox(height: 16.0),
            _buildImagePickerCard(),
            if (_selectedImage != null) ...[
              const SizedBox(height: 16.0),
              if (_isProcessingImage)
                const CircularProgressIndicator()
              else if (_aiResponse.isNotEmpty)
                Container(
                  height: 200, // Fixed height
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey[50],
                    borderRadius: BorderRadius.circular(12.0),
                    border: Border.all(color: Colors.blueGrey[200]!),
                  ),
                  child: SingleChildScrollView(
                    // Add scrolling for overflow
                    child: Text(
                      'AI Generated Question: $_aiResponse',
                      style: const TextStyle(
                          fontSize: 14.0, color: Colors.black87),
                    ),
                  ),
                ),
              const SizedBox(height: 16.0),
            ],
            TextField(
              decoration: InputDecoration(
                labelText: 'Number of Questions',
                prefixIcon: const Icon(Icons.question_mark),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                  borderSide: BorderSide(color: Colors.grey[300]!, width: 1.0),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                  borderSide: BorderSide(
                      color: Theme.of(context).primaryColor, width: 2.0),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16.0, vertical: 12.0),
                filled: true,
                fillColor: Theme.of(context).inputDecorationTheme.fillColor ??
                    Colors.grey[100],
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                logger.i(
                    'PrepareShortTest - Number of questions changed to: $value');
                _numberOfQuestions = int.tryParse(value);
              },
            ),
            const SizedBox(height: 16.0),
            TextField(
              decoration: InputDecoration(
                labelText: 'Test Time (minutes)',
                prefixIcon: const Icon(Icons.timer),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                  borderSide: BorderSide(color: Colors.grey[300]!, width: 1.0),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                  borderSide: BorderSide(
                      color: Theme.of(context).primaryColor, width: 2.0),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16.0, vertical: 12.0),
                filled: true,
                fillColor: Theme.of(context).inputDecorationTheme.fillColor ??
                    Colors.grey[100],
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                logger.i(
                    'PrepareShortTest - Test time changed to: $value minutes');
                _testTimeInMinutes = int.tryParse(value);
              },
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: (_selectedImage != null &&
                      _selectedTestType != null &&
                      !_isProcessingImage)
                  ? _sendImageToGemini
                  : null,
              icon: _isProcessingImage
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(
                  _isProcessingImage ? 'Generating...' : 'Generate Question'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            if (_aiResponse.isNotEmpty && !_isProcessingImage) ...[
              const SizedBox(height: 16.0),
              ElevatedButton.icon(
                onPressed: () {
                  if (_selectedTestType != null &&
                      _numberOfQuestions != null &&
                      _testTimeInMinutes != null &&
                      _testTimeInMinutes! > 0) {
                    final Widget testPage;
                    switch (_selectedTestType) {
                      case 'MCQ Test':
                        testPage = MCQTestPage(
                          numberOfQuestions: _numberOfQuestions!,
                          testTimeInMinutes: _testTimeInMinutes!,
                          selectedImage: _selectedImage,
                          aiResponse: _aiResponse,
                          language: _selectedLanguage,
                        );
                        break;
                      case 'Short Question':
                        testPage = ShortQuestionPage(
                          numberOfQuestions: _numberOfQuestions!,
                          testTimeInMinutes: _testTimeInMinutes!,
                          selectedImage: _selectedImage,
                          aiResponse: _aiResponse,
                          language: _selectedLanguage,
                        );
                        break;
                      // ...similar cases for other test types...
                      default:
                        testPage = ShortTestPage(
                          selectedTestType: _selectedTestType!,
                          numberOfQuestions: _numberOfQuestions!,
                          testTimeInMinutes: _testTimeInMinutes!,
                          selectedImage: _selectedImage,
                          aiResponse: _aiResponse,
                          language: _selectedLanguage,
                        );
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => testPage),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please fill all fields correctly'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start Test'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildImagePickerCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_selectedImage == null)
              InkWell(
                onTap: _pickImage,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 200,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.image_outlined, size: 48, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'Tap to select image',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              )
            else
              Column(
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(_selectedImage!.path),
                          height: 200,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            setState(() {
                              _selectedImage = null;
                              _aiResponse = '';
                            });
                          },
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

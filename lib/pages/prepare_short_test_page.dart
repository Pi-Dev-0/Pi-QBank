import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/app_config.dart';
import 'package:pi_qbank/widgets/api_key_dialog.dart'; // Import the API key dialog
import 'fill_in_the_blanks_test_page.dart';
import 'mcq_test_page.dart';
import 'short_question_page.dart';
import 'package:pi_qbank/widgets/custom_app_bar.dart';

class PrepareShortTestPage extends StatefulWidget {
  const PrepareShortTestPage({super.key});

  @override
  State<PrepareShortTestPage> createState() => _PrepareShortTestPageState();
}

class _PrepareShortTestPageState extends State<PrepareShortTestPage>
    with TickerProviderStateMixin {
  String? _selectedTestType;
  int? _numberOfQuestions;
  int? _testTimeInMinutes;
  XFile? _selectedImage;
  String? _selectedImageMimeType;
  String _aiResponse = '';
  bool _isProcessingImage = false;
  String _selectedLanguage = 'English';

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
        parent: _animationController, curve: Curves.easeOutBack));

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1200,
        maxHeight: 1200,
      );

      if (image != null) {
        final File file = File(image.path);
        if (await file.exists()) {
          setState(() {
            _selectedImage = image;
            _selectedImageMimeType = image.mimeType;
            _aiResponse = '';
          });
        } else {
          throw Exception('Selected image file does not exist');
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Error selecting image!'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
    if (_selectedImage == null || _selectedTestType == null) return;

    setState(() {
      _isProcessingImage = true;
      _aiResponse = 'Processing image...';
    });

    try {
      String? apiKey = await getApiKey(); // Try to get API key from SharedPreferences

      if (apiKey == null || apiKey.isEmpty) {
        // If not found in SharedPreferences, use the default from AppConfig
        apiKey = AppConfig.geminiApiKey;
      }

      if (apiKey.isEmpty) { // Removed unnecessary non-null assertion.
        if (!mounted) return;
        showApiKeyDialog(context); // Show dialog if API key is still not set
        setState(() {
          _isProcessingImage = false;
          _aiResponse = 'API Key not set. Please enter your API key.';
        });
        return;
      }

      final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$apiKey');

      List<Map<String, dynamic>> parts = [];

      final bytes = await _selectedImage!.readAsBytes();
      const int maxImageSize = 15 * 1024 * 1024;
      if (bytes.length > maxImageSize) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Image too large. Please choose a smaller image (max 15MB).'),
            backgroundColor: Colors.orange.shade600,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        setState(() {
          _isProcessingImage = false;
        });
        return;
      }

      final base64Image = base64Encode(bytes);
      parts.add({
        "inline_data": {
          "mime_type": _selectedImageMimeType ?? 'image/jpeg',
          "data": base64Image
        }
      });

      String prompt = _getAIInstructions(_selectedTestType!);
      parts.add({"text": prompt});

      List<Map<String, dynamic>> contents = [
        {"role": "user", "parts": parts}
      ];

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({"contents": contents}),
      );

      if (response.statusCode == 200) {
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
        throw Exception(
            'Failed to get AI understanding. Status: ${response.statusCode}, Body: ${response.body}');
      }
    } catch (e) {
      setState(() {
        _aiResponse = 'Error: ${e.toString()}';
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Error getting AI understanding!'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } finally {
      setState(() {
        _isProcessingImage = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: CustomAppBar(
        title: 'Prepare Short Test',
        centerTitle: true,
      ),
      body: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // Header Section
                    _buildHeaderSection(),
                    const SizedBox(height: 24),

                    // Configuration Section
                    _buildConfigurationSection(),
                    const SizedBox(height: 24),

                    // Image Section
                    _buildImageSection(),
                    const SizedBox(height: 24),

                    // Question Settings Section
                    _buildQuestionSettingsSection(),
                    const SizedBox(height: 32),

                    // Action Buttons Section
                    _buildActionButtonsSection(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeaderSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.blue.shade600,
            Colors.purple.shade600,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            Icons.auto_awesome,
            size: 48,
            color: Colors.white,
          ),
          const SizedBox(height: 16),
          Text(
            'AI-Powered Test Generator',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Upload an image and let AI generate personalized questions for you',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withOpacity(0.9),
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildConfigurationSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.settings,
                  color: Colors.blue.shade600,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'Test Configuration',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Test Type Dropdown
          _buildStylishDropdown(
            label: 'Test Type',
            icon: Icons.assignment_outlined,
            value: _selectedTestType,
            items: ['MCQ Test', 'Short Question', 'Fill In the Blanks'],
            onChanged: (String? newValue) {
              setState(() {
                _selectedTestType = newValue;
              });
            },
          ),
          const SizedBox(height: 16),

          // Language Dropdown
          _buildStylishDropdown(
            label: 'Select Language',
            icon: Icons.language_outlined,
            value: _selectedLanguage,
            items: ['English', 'বাংলা'],
            onChanged: (String? newValue) {
              if (newValue != null) {
                setState(() {
                  _selectedLanguage = newValue;
                });
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStylishDropdown({
    required String label,
    required IconData icon,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        color: Colors.grey.shade50,
      ),
      child: DropdownButtonFormField<String>(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Colors.blue.shade600),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        value: value,
        items: items.map<DropdownMenuItem<String>>((String item) {
          return DropdownMenuItem<String>(
            value: item,
            child: Text(item, style: const TextStyle(fontSize: 16)),
          );
        }).toList(),
        onChanged: onChanged,
        dropdownColor: Colors.white,
        borderRadius: BorderRadius.circular(16),
        icon: Icon(Icons.keyboard_arrow_down, color: Colors.blue.shade600),
      ),
    );
  }

  Widget _buildImageSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.image_outlined,
                  color: Colors.green.shade600,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'Upload Image',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildImagePickerCard(),

          // AI Processing Status
          if (_selectedImage != null) ...[
            const SizedBox(height: 20),
            if (_isProcessingImage)
              _buildProcessingIndicator()
            else if (_aiResponse.isNotEmpty)
              _buildStatusIndicator(),
          ],
        ],
      ),
    );
  }

  Widget _buildProcessingIndicator() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Processing Image...',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue.shade800,
                  ),
                ),
                Text(
                  'AI is analyzing your image to generate questions',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.blue.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator() {
    final bool isError = _aiResponse.contains('Error');
    final Color statusColor = isError ? Colors.red : Colors.green;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: statusColor.withOpacity(0.6),
            size: 24,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isError ? 'Generation Failed' : 'Successfully Generated',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: statusColor.withOpacity(0.8),
                  ),
                ),
                Text(
                  isError
                      ? 'Please try again with a different image'
                      : 'Questions are ready! Configure settings below to start test.',
                  style: TextStyle(
                    fontSize: 14,
                    color: statusColor.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionSettingsSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.tune,
                  color: Colors.purple.shade600,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'Question Settings',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildStylishTextField(
                label: 'Number of Questions',
                icon: Icons.quiz_outlined,
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  _numberOfQuestions = int.tryParse(value);
                },
              ),
              const SizedBox(height: 16),
              _buildStylishTextField(
                label: 'Test Time (minutes)',
                icon: Icons.timer_outlined,
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  _testTimeInMinutes = int.tryParse(value);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStylishTextField({
    required String label,
    required IconData icon,
    required TextInputType keyboardType,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        color: Colors.grey.shade50,
      ),
      child: TextField(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Colors.purple.shade600),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        keyboardType: keyboardType,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildActionButtonsSection() {
    return Column(
      children: [
        // Generate Button
        Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade600, Colors.blue.shade800],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ElevatedButton.icon(
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
                : const Icon(Icons.auto_awesome, size: 24),
            label: Text(
              _isProcessingImage ? 'Generating...' : 'Generate Questions',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),

        // Start Test Button
        if (_aiResponse.isNotEmpty &&
            !_isProcessingImage &&
            !_aiResponse.contains('Error')) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.green.shade600, Colors.green.shade800],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ElevatedButton.icon(
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
                    case 'Fill In the Blanks':
                      testPage = FillInTheBlanksTestPage(
                        numberOfQuestions: _numberOfQuestions!,
                        testTimeInMinutes: _testTimeInMinutes!,
                        aiResponse: _aiResponse,
                        language: _selectedLanguage,
                      );
                      break;
                    default:
                      testPage = FillInTheBlanksTestPage(
                        numberOfQuestions: _numberOfQuestions!,
                        testTimeInMinutes: _testTimeInMinutes!,
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
                    SnackBar(
                      content: const Text('Please fill all fields correctly'),
                      backgroundColor: Colors.orange.shade600,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.play_arrow, size: 24),
              label: const Text(
                'Start Test',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildImagePickerCard() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200, width: 2),
        color: Colors.grey.shade50,
      ),
      child: Column(
        children: [
          if (_selectedImage == null)
            InkWell(
              onTap: _pickImage,
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 200,
                width: double.infinity,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: Icon(
                        Icons.cloud_upload_outlined,
                        size: 48,
                        color: Colors.blue.shade600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Tap to Upload Image',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Support JPG, PNG, GIF (Max 15MB)',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(
                    File(_selectedImage!.path),
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () {
                        setState(() {
                          _selectedImage = null;
                          _aiResponse = '';
                        });
                      },
                      style: IconButton.styleFrom(
                        foregroundColor: Colors.grey.shade700,
                        padding: const EdgeInsets.all(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

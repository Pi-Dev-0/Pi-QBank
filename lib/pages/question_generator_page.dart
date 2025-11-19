import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/app_config.dart';
import 'package:pi_qbank/widgets/api_key_dialog.dart';
import 'package:pi_qbank/widgets/custom_app_bar.dart';
import 'package:pi_qbank/services/question_generator_google_sheet_service.dart';

class QuestionGeneratorPage extends StatefulWidget {
  const QuestionGeneratorPage({super.key});

  @override
  State<QuestionGeneratorPage> createState() => _QuestionGeneratorPageState();
}

class _QuestionGeneratorPageState extends State<QuestionGeneratorPage>
    with TickerProviderStateMixin {
  String? _selectedQuestionType; // Changed from _selectedTestType
  int? _numberOfQuestions;
  final List<XFile> _selectedImages = [];
  final List<String> _selectedImageMimeTypes = [];
  String _aiResponse = '';
  bool _isProcessingImage = false;
  String _selectedLanguage = 'English';
  final List<Map<String, String>> _generatedQuestions = [];
  String _generatedTopic = ''; // New state for the generated topic
  String? _selectedClass; // New state for selected class

  // MCQ state
  List<Map<String, dynamic>> _generatedMcqs = [];
  final Map<int, bool> _answerVisibility = {};

  late ScrollController _scrollController; // Declare ScrollController

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(); // Initialize ScrollController
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
    _scrollController.dispose(); // Dispose ScrollController
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final List<XFile> images = await picker.pickMultiImage(
        imageQuality: 80,
        maxWidth: 1200,
        maxHeight: 1200,
      );

      if (images.isNotEmpty) {
        List<XFile> validImages = [];
        List<String> validMimeTypes = [];
        for (XFile image in images) {
          final File file = File(image.path);
          if (await file.exists()) {
            validImages.add(image);
            validMimeTypes.add(image.mimeType ?? 'image/jpeg');
          }
        }
        setState(() {
          _selectedImages.addAll(validImages);
          _selectedImageMimeTypes.addAll(validMimeTypes);
          _aiResponse = '';
          _generatedTopic = ''; // Reset topic
          _generatedMcqs.clear();
          _answerVisibility.clear();
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error selecting images: ${e.toString()}'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  String _getAIInstructions(String questionType) {
    final int questionsCount = _numberOfQuestions ?? 4;
    final String languageInstruction = _selectedLanguage == 'বাংলা'
        ? 'Generate questions and answers strictly in Bengali (Bangla) language. '
        : 'Generate questions and answers strictly in English language. ';
    final String imageContext = _selectedImages.length > 1
        ? 'these images' : 'this image';

    String topicInstruction = _selectedLanguage == 'বাংলা'
        ? 'এই $imageContext উপর ভিত্তি করে একটি উপযুক্ত বিষয় বা শিরোনাম তৈরি করুন এবং আপনার প্রতিক্রিয়ার শুরুতে "বিষয়:" দিয়ে শুরু করুন। তারপর, '
        : 'Generate a suitable topic or title based on $imageContext and start your response with "Topic: [Your Topic]". Then, ';

    switch (questionType) {
      case 'Short Question':
        if (_selectedLanguage == 'বাংলা') {
          return '$topicInstruction$languageInstructionএই $imageContext সম্পর্কে $questionsCount টি সংক্ষিপ্ত উত্তর প্রশ্ন তৈরি করুন যার জন্য সংক্ষিপ্ত ব্যাখ্যার প্রয়োজন। প্রতিটি উত্তর ১-৩ শব্দের মধ্যে হওয়া উচিত। প্রতিটি প্রশ্নের উত্তর একটি নতুন লাইনে "উত্তর:" দিয়ে শুরু হবে।';
        }
        return '$topicInstruction${languageInstruction}Generate $questionsCount short answer questions about $imageContext that require brief explanations. Each answer should be 1-3 words. Each answer must start on a new line with "Answer:".';
      case 'Broad Question':
        if (_selectedLanguage == 'বাংলা') {
          return '$topicInstruction$languageInstructionএই $imageContext সম্পর্কে $questionsCount টি বিস্তারিত উত্তর প্রশ্ন তৈরি করুন যার জন্য বিস্তারিত ব্যাখ্যার প্রয়োজন। প্রতিটি উত্তর ৫-২০ বাক্যের মধ্যে হওয়া উচিত। প্রতিটি প্রশ্নের উত্তর একটি নতুন লাইনে "উত্তর:" দিয়ে শুরু হবে।';
        }
        return '$topicInstruction${languageInstruction}Generate $questionsCount broad answer questions about $imageContext that require detailed explanations. Each answer should be 5-20 sentences. Each answer must start on a new line with "Answer:".';
      case 'MCQ':
        final String mcqLanguageInstruction = _selectedLanguage == 'বাংলা'
            ? 'Generate questions and answers strictly in Bengali (Bangla) language.'
            : 'Generate questions and answers strictly in English language.';
        return '''
$mcqLanguageInstruction Generate $questionsCount multiple choice questions about $imageContext with 4 options each. 
Each question must also include the correct answer.
Respond in the following JSON format:

{
  "topic": "A concise topic/title for these MCQs in $_selectedLanguage",
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
      default:
        return '$topicInstruction${languageInstruction}Generate questions about $imageContext.';
    }
  }

  Future<void> _sendImageToGemini() async {
    if (_selectedImages.isEmpty || _selectedQuestionType == null) return;

    setState(() {
      _isProcessingImage = true;
      _aiResponse = 'Processing images...';
      _generatedTopic = ''; // Clear topic on new generation
      _generatedQuestions.clear();
      _generatedMcqs.clear();
      _answerVisibility.clear();
    });

    try {
      String? apiKey = await getApiKey();

      if (apiKey == null || apiKey.isEmpty) {
        apiKey = AppConfig.geminiApiKey;
      }

      if (apiKey.isEmpty) {
        if (!mounted) return;
        showApiKeyDialog(context);
        setState(() {
          _isProcessingImage = false;
          _aiResponse = 'API Key not set. Please enter your API key.';
        });
        return;
      }

      final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$apiKey');

      List<Map<String, dynamic>> parts = [];

      for (int i = 0; i < _selectedImages.length; i++) {
        final image = _selectedImages[i];
        final mimeType = _selectedImageMimeTypes[i];
        final bytes = await image.readAsBytes();
        const int maxImageSize = 15 * 1024 * 1024;
        if (bytes.length > maxImageSize) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Image ${i + 1} is too large. Please choose smaller images (max 15MB each).'),
              backgroundColor: Colors.orange.shade600,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
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
            "mime_type": mimeType,
            "data": base64Image
          }
        });
      }

      String prompt = _getAIInstructions(_selectedQuestionType!);
      parts.add({"text": prompt});

      List<Map<String, dynamic>> contents = [];

      contents.add({
        "role": "user",
        "parts": [
          {
            "text":
                "Analyze the provided images and generate questions based on them."
          }
        ]
      });
      contents.add({
        "role": "model",
        "parts": [
          {
            "text":
                "Understood. I will analyze the images and prepare questions."
          }
        ]
      });

      List<Map<String, dynamic>> currentParts = [];
      currentParts.addAll(parts); // Add all image parts
      currentParts.add({"text": prompt});
      contents.add({"role": "user", "parts": currentParts});
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
            if (_selectedQuestionType == 'MCQ') {
              _parseGeneratedMcqs(reply);
            } else {
              _parseGeneratedQuestions();
            }
          });
          // Scroll to top after questions are generated
          _scrollController.animateTo(
            0.0,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
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
    bool showInputForm =
        (_generatedQuestions.isEmpty && _generatedMcqs.isEmpty) ||
            _isProcessingImage ||
            _aiResponse.contains('Error');

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: CustomAppBar(
        title: 'Question Generator',
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
                controller: _scrollController, // Assign ScrollController
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (showInputForm) ...[
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

                    // AI Response Display
                    if (!showInputForm) ...[
                      if (_selectedQuestionType == 'MCQ')
                        _buildMCQResponseSection()
                      else
                        _buildAIResponseSection(),
                    ],
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
            Colors.purple.shade600,
            Colors.deepOrange.shade600,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            Icons.lightbulb_outline,
            size: 48,
            color: Colors.white,
          ),
          const SizedBox(height: 16),
          Text(
            'AI Question Generator',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Upload an image and let AI generate questions for you',
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
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.settings,
                  color: Colors.purple.shade600,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'Question Configuration',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Question Type Dropdown
          _buildStylishDropdown(
            label: 'Question Type',
            icon: Icons.assignment_outlined,
            value: _selectedQuestionType,
            items: ['Short Question', 'Broad Question', 'MCQ'],
            onChanged: (String? newValue) {
              setState(() {
                _selectedQuestionType = newValue;
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
          prefixIcon: Icon(icon, color: Colors.purple.shade600),
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
        icon: Icon(Icons.keyboard_arrow_down, color: Colors.purple.shade600),
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
          if (_selectedImages.isNotEmpty) ...[
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
                      : 'Questions are ready! Expand each question to reveal its answer.',
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
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.format_list_numbered,
                  color: Colors.orange.shade600,
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
          _buildStylishTextField(
            label: 'Number of Questions',
            icon: Icons.quiz_outlined,
            keyboardType: TextInputType.number,
            onChanged: (value) {
              setState(() {
                _numberOfQuestions = int.tryParse(value);
              });
            },
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
          prefixIcon: Icon(icon, color: Colors.orange.shade600),
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
              colors: [Colors.purple.shade600, Colors.purple.shade800],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.purple.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ElevatedButton.icon(
            onPressed: (_selectedImages.isNotEmpty &&
                    _selectedQuestionType != null &&
                    _numberOfQuestions != null &&
                    _numberOfQuestions! > 0 &&
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
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
          if (_selectedImages.isEmpty)
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
                      'Tap to Upload Images',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Support JPG, PNG, GIF (Max 15MB per image)',
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
            Column(
              children: [
                SizedBox(
                  height: 200,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _selectedImages.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.file(
                                File(_selectedImages[index].path),
                                height: 180,
                                width: 180,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 5,
                              right: 5,
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
                                      _selectedImages.removeAt(index);
                                      _selectedImageMimeTypes.removeAt(index);
                                      _aiResponse = '';
                                      _generatedMcqs.clear();
                                      _generatedQuestions.clear();
                                      _answerVisibility.clear();
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
                      );
                    },
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('Add More Images'),
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.blue.shade600,
                    backgroundColor: Colors.blue.shade50,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
        ],
      ),
    );
  }

  void _parseGeneratedMcqs(String response) {
    try {
      String cleanedResponse =
          response.replaceAll('```json\n', '').replaceAll('```', '').trim();
      final Map<String, dynamic> decodedResponse = json.decode(cleanedResponse);
      _generatedTopic = decodedResponse['topic'] ?? 'Generated MCQs';
      _generatedMcqs =
          List<Map<String, dynamic>>.from(decodedResponse['questions'] ?? []);
      for (int i = 0; i < _generatedMcqs.length; i++) {
        _answerVisibility[i] = false;
      }
    } catch (e) {
      setState(() {
        _aiResponse = 'Error parsing MCQs: ${e.toString()}';
        _generatedMcqs = [];
      });
    }
  }

  void _toggleAnswerVisibility(int index) {
    setState(() {
      _answerVisibility[index] = !(_answerVisibility[index] ?? false);
    });
  }

  void _parseGeneratedQuestions() {
    _generatedQuestions.clear();
    _generatedTopic = ''; // Clear topic before parsing
    List<String> lines = _aiResponse.split('\n');
    String currentQuestion = '';
    String currentAnswer = '';
    bool inQuestion =
        false; // True if we are currently accumulating question text
    bool inAnswer = false; // True if we are currently accumulating answer text
    int startIndex = 0;

    // Topic extraction logic remains the same
    for (int i = 0; i < lines.length; i++) {
      String line = lines[i].trim();
      if (line.toLowerCase().startsWith('topic:') ||
          line.toLowerCase().startsWith('বিষয়:')) {
        _generatedTopic = line.substring(line.indexOf(':') + 1).trim();
        startIndex = i + 1;
        break;
      }
      if (RegExp(r'^\d+\.|^[\u09E6-\u09EF]+\.').hasMatch(line)) {
        startIndex = i;
        break;
      }
    }

    for (int i = startIndex; i < lines.length; i++) {
      String line = _normalizeString(lines[i]); // Apply normalization
      if (line.isEmpty) continue;

      // Check for question start
      final questionMatch = RegExp(
              r'^(?:(?:\d+|[\u09E6-\u09EF]+)\. ?|প্রশ্ন(?:ঃ)? ?\d*[:]? ?|Question: ?\d*[:]? ?)',
              caseSensitive: false)
          .firstMatch(line);
      final answerMatch =
          RegExp(r'^(?:উত্তর:|answer:|উঃ) ?', caseSensitive: false)
              .firstMatch(line);

      if (questionMatch != null) {
        // Found a new question
        if (currentQuestion.isNotEmpty) {
          _generatedQuestions.add({
            'question': _stripMarkdown(currentQuestion.trim()),
            'answer': _stripMarkdown(currentAnswer.trim()),
          });
        }
        currentQuestion = line.substring(questionMatch.end).trim();
        currentAnswer = '';
        inQuestion = true;
        inAnswer = false;
      } else if (answerMatch != null) {
        // Found an answer start
        currentAnswer = line.substring(answerMatch.end).trim();
        inAnswer = true;
        inQuestion =
            false; // Should not be in question accumulation if answer starts
      } else {
        // Continue accumulating based on current state
        if (inAnswer) {
          currentAnswer = '$currentAnswer $line';
        } else if (inQuestion) {
          currentQuestion = '$currentQuestion $line';
        }
        // If neither inQuestion nor inAnswer, and not a start, ignore or consider as part of previous line if applicable.
        // For now, if not in a recognized section, it's ignored.
      }
    }

    // Add the last question if exists
    if (currentQuestion.isNotEmpty) {
      _generatedQuestions.add({
        'question': _stripMarkdown(currentQuestion.trim()),
        'answer': _stripMarkdown(currentAnswer.trim()),
      });
    }
  }

  String _normalizeString(String text) {
    // Replace various whitespace characters with a standard space
    String normalized = text.replaceAll(RegExp(r'\s+'), ' ');
    // Remove zero-width spaces and other common invisible characters
    normalized = normalized.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '');
    return normalized.trim();
  }

  String _stripMarkdown(String text) {
    // Remove bold (**text**) and italics (*text*)
    String strippedText =
        text.replaceAll(RegExp(r'\*\*([^\*]+)\*\*'), r'\1'); // bold
    strippedText =
        strippedText.replaceAll(RegExp(r'\*([^\*]+)\*'), r'\1'); // italics
    // Remove any remaining single asterisks that might be part of the text but not markdown
    strippedText = strippedText.replaceAll(RegExp(r'\*'), '');
    // Remove leading/trailing spaces
    return strippedText.trim();
  }

  String _convertToBengaliNumber(int number) {
    const english = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const bengali = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
    String strNum = number.toString();
    for (int i = 0; i < english.length; i++) {
      strNum = strNum.replaceAll(english[i], bengali[i]);
    }
    return strNum;
  }

  Widget _buildAIResponseSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          // This container holds the "Generated Questions" title
          padding: const EdgeInsets.all(16),
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
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.lightbulb_outline,
                  color: Colors.blue.shade600,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  _generatedTopic.isNotEmpty
                      ? _generatedTopic
                      : 'Generated Questions',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(
            height: 20), // Space between title container and questions list
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _generatedQuestions.length,
          itemBuilder: (context, index) {
            final question = _generatedQuestions[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white,
                    Colors.grey.shade50,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
                border: Border.all(
                  color: Colors.grey.withOpacity(0.1),
                  width: 2,
                ),
              ),
              child: Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  leading: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.blue.shade400, Colors.blue.shade600],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        _selectedLanguage == 'বাংলা'
                            ? _convertToBengaliNumber(index + 1)
                            : '${index + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ),
                  title: const SizedBox.shrink(),
                  subtitle: Text(
                    question['question'] ?? '',
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                    ),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          // Changed from Column to Row
                          crossAxisAlignment: CrossAxisAlignment
                              .start, // Align content at the top
                          children: [
                            Text(
                              _selectedLanguage == 'বাংলা'
                                  ? 'উত্তর:'
                                  : 'Answer:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                question['answer'] ?? '',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.green.shade800,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines:
                                    _selectedQuestionType == 'Short Question'
                                        ? 1
                                        : null,
                                overflow:
                                    _selectedQuestionType == 'Short Question'
                                        ? TextOverflow.ellipsis
                                        : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMCQResponseSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Center(
            child: Text(
              _generatedTopic.isNotEmpty ? _generatedTopic : 'Generated MCQs',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1F2937),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _generatedMcqs.length,
          itemBuilder: (context, index) {
            final mcq = _generatedMcqs[index];
            final questionText = mcq['question'] as String? ?? 'No question text provided';
            final options = mcq['options'] as Map<String, dynamic>? ?? {};
            final correctAnswerKey = mcq['correct_answer'] as String? ?? '';
            final correctAnswerText = options[correctAnswerKey] as String? ?? 'Not available';
            final isAnswerVisible = _answerVisibility[index] ?? false;

            return Container(
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white,
                    Colors.grey.shade50,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
                border: Border.all(
                  color: Colors.teal.withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.teal.shade50.withOpacity(0.5),
                          Colors.cyan.shade50.withOpacity(0.5),
                        ],
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(18),
                        topRight: Radius.circular(18),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.teal.shade600,
                                Colors.cyan.shade600,
                              ],
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.teal.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              _selectedLanguage == 'বাংলা'
                                  ? _convertToBengaliNumber(index + 1)
                                  : '${index + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            questionText,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1F2937),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: options.entries.map((option) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Text(
                            '${option.key}. ${option.value ?? ''}',
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0),
                    child: ElevatedButton.icon(
                      onPressed: () => _toggleAnswerVisibility(index),
                      icon: Icon(
                        isAnswerVisible
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: Colors.white,
                      ),
                      label: Text(
                        isAnswerVisible ? 'Hide Answer' : 'Show Answer',
                        style: const TextStyle(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  if (isAnswerVisible)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_outline,
                                color: Colors.green.shade700),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Correct Answer: $correctAnswerKey. $correctAnswerText',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        // Upload to Server Button
        if (_aiResponse.isNotEmpty &&
            !_isProcessingImage &&
            !_aiResponse.contains('Error')) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.deepPurple.shade600, Colors.purple.shade800],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.deepPurple.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: _uploadTestToServer, // New method for uploading
              icon: const Icon(Icons.cloud_upload, size: 24),
              label: const Text(
                'Upload to Server',
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

  Future<void> _uploadTestToServer() async {
    if (_generatedQuestions.isEmpty && _generatedMcqs.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No questions generated to upload.'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }
    await _showUploadDialog();
  }

  Future<void> _showUploadDialog() async {
    String? tempSelectedClass = _selectedClass;
    String?
        tempSelectedSubject; // New state for subject selection within the dialog
    final TextEditingController chapterController = TextEditingController();

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 0,
              backgroundColor: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'Upload Questions to Server',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    // Class Dropdown
                    _buildPickerButton(
                      label: 'Select Class',
                      icon: Icons.school_outlined,
                      value: tempSelectedClass,
                      onTap: () {
                        _showSelectionDialog(
                          context: context,
                          title: 'Select Class',
                          items: List.generate(12, (i) => 'Class ${i + 1}'),
                          selectedItem: tempSelectedClass,
                          onItemSelected: (value) {
                            setState(() {
                              tempSelectedClass = value;
                            });
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    // Subject Dropdown
                    _buildPickerButton(
                      label: 'Select Subject',
                      icon: Icons.menu_book_outlined,
                      value: tempSelectedSubject,
                      onTap: () {
                        _showSelectionDialog(
                          context: context,
                          title: 'Select Subject',
                          items: [
                            'Physics',
                            'Chemistry',
                            'Math',
                            'Biology',
                            'English',
                            'Bangla'
                          ],
                          selectedItem: tempSelectedSubject,
                          onItemSelected: (value) {
                            setState(() {
                              tempSelectedSubject = value;
                            });
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    // Chapter Text Field
                    _buildStylishTextField(
                      label: 'Chapter Name',
                      icon: Icons.bookmark_outline,
                      keyboardType: TextInputType.text,
                      onChanged: (value) {
                        chapterController.text = value;
                      },
                    ),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          child: Text(
                            'Cancel',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            final String subject = tempSelectedSubject ?? '';
                            final String chapter =
                                chapterController.text.trim();
                            if (tempSelectedClass != null &&
                                subject.isNotEmpty &&
                                chapter.isNotEmpty) {
                              Navigator.of(context).pop();
                              _uploadQuestions(
                                  tempSelectedClass!, subject, chapter);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                      'Please select a Class, Subject, and enter a Chapter.'),
                                  backgroundColor: Colors.red.shade600,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple.shade600,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                          ),
                          child: const Text('Upload'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showSelectionDialog({
    required BuildContext context,
    required String title,
    required List<String> items,
    required String? selectedItem,
    required ValueChanged<String> onItemSelected,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        elevation: 8,
        title: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
          ),
        ),
        content: SingleChildScrollView(
          child: ListBody(
            children: items.map((item) {
              return GestureDetector(
                onTap: () {
                  onItemSelected(item);
                  Navigator.of(dialogContext).pop();
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                  decoration: BoxDecoration(
                    color: selectedItem == item
                        ? Colors.blue.shade100
                        : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selectedItem == item
                          ? Colors.blue
                          : Colors.grey.shade300,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    item,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: selectedItem == item
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: selectedItem == item
                          ? Colors.blue.shade900
                          : Colors.black87,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildPickerButton({
    required String label,
    required IconData icon,
    required String? value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          color: Colors.grey.shade50,
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, color: Colors.purple.shade600),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label == 'Select Class' && value != null
                    ? value
                    : value ?? label,
                style: TextStyle(
                  fontSize: 16,
                  color:
                      value != null ? Colors.black87 : Colors.grey.shade600,
                ),
              ),
            ),
            Icon(Icons.keyboard_arrow_down, color: Colors.purple.shade600),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadQuestions(String selectedClass, String subject, String chapter) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Uploading questions for Class: $selectedClass, Subject: $subject, Chapter: $chapter...'),
        backgroundColor: Colors.blue.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    String result;
    if (_selectedQuestionType == 'MCQ') {
      result = await QuestionGeneratorGoogleSheetService.uploadQuestions(
        className: selectedClass,
        subject: subject,
        chapter: chapter,
        questionType: _selectedQuestionType!,
        language: _selectedLanguage,
        generatedTopic: _generatedTopic,
        generatedQuestions: [], // Not applicable for MCQ
        generatedMcqs: _generatedMcqs,
      );
    } else {
      result = await QuestionGeneratorGoogleSheetService.uploadQuestions(
        className: selectedClass,
        subject: subject,
        chapter: chapter,
        questionType: _selectedQuestionType!,
        language: _selectedLanguage,
        generatedTopic: _generatedTopic,
        generatedQuestions: _generatedQuestions,
        generatedMcqs: [], // Not applicable for Short/Broad
      );
    }

    if (!mounted) return;
    if (result == 'SUCCESS') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Questions uploaded successfully!'),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to upload questions: $result'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }
}


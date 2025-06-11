import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/app_config.dart';
import 'package:pi_qbank/widgets/api_key_dialog.dart';
import 'package:pi_qbank/widgets/custom_app_bar.dart';

class QuestionGeneratorPage extends StatefulWidget {
  const QuestionGeneratorPage({super.key});

  @override
  State<QuestionGeneratorPage> createState() => _QuestionGeneratorPageState();
}

class _QuestionGeneratorPageState extends State<QuestionGeneratorPage>
    with TickerProviderStateMixin {
  String? _selectedQuestionType; // Changed from _selectedTestType
  int? _numberOfQuestions;
  XFile? _selectedImage;
  String? _selectedImageMimeType;
  String _aiResponse = '';
  bool _isProcessingImage = false;
  String _selectedLanguage = 'English';
  final List<Map<String, String>> _generatedQuestions = [];
  String _generatedTopic = ''; // New state for the generated topic

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
            _generatedTopic = ''; // Reset topic
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

  String _getAIInstructions(String questionType) {
    final int questionsCount = _numberOfQuestions ?? 4;
    final String languageInstruction = _selectedLanguage == 'বাংলা'
        ? 'Generate questions and answers strictly in Bengali (Bangla) language. '
        : 'Generate questions and answers strictly in English language. ';

    String topicInstruction = _selectedLanguage == 'বাংলা'
        ? 'এই ছবির উপর ভিত্তি করে একটি উপযুক্ত বিষয় বা শিরোনাম তৈরি করুন এবং আপনার প্রতিক্রিয়ার শুরুতে "বিষয়:" দিয়ে শুরু করুন। তারপর, '
        : 'Generate a suitable topic or title based on this image and start your response with "Topic: [Your Topic]". Then, ';

    switch (questionType) {
      case 'Short Question':
        if (_selectedLanguage == 'বাংলা') {
          return '$topicInstruction$languageInstructionএই ছবি সম্পর্কে $questionsCount টি সংক্ষিপ্ত উত্তর প্রশ্ন তৈরি করুন যার জন্য সংক্ষিপ্ত ব্যাখ্যার প্রয়োজন। প্রতিটি উত্তর ১-৩ শব্দের মধ্যে হওয়া উচিত। প্রতিটি প্রশ্নের উত্তর একটি নতুন লাইনে "উত্তর:" দিয়ে শুরু হবে।';
        }
        return '$topicInstruction${languageInstruction}Generate $questionsCount short answer questions about this image that require brief explanations. Each answer should be 1-3 words. Each answer must start on a new line with "Answer:".';
      case 'Broad Question':
        if (_selectedLanguage == 'বাংলা') {
          return '$topicInstruction$languageInstructionএই ছবি সম্পর্কে $questionsCount টি বিস্তারিত উত্তর প্রশ্ন তৈরি করুন যার জন্য বিস্তারিত ব্যাখ্যার প্রয়োজন। প্রতিটি উত্তর ৫-২০ বাক্যের মধ্যে হওয়া উচিত। প্রতিটি প্রশ্নের উত্তর একটি নতুন লাইনে "উত্তর:" দিয়ে শুরু হবে।';
        }
        return '$topicInstruction${languageInstruction}Generate $questionsCount broad answer questions about this image that require detailed explanations. Each answer should be 5-20 sentences. Each answer must start on a new line with "Answer:".';
      default:
        return '$topicInstruction${languageInstruction}Generate questions about this image.';
    }
  }

  Future<void> _sendImageToGemini() async {
    if (_selectedImage == null || _selectedQuestionType == null) return;

    setState(() {
      _isProcessingImage = true;
      _aiResponse = 'Processing image...';
      _generatedTopic = ''; // Clear topic on new generation
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

      String prompt = _getAIInstructions(_selectedQuestionType!);
      parts.add({"text": prompt});

      List<Map<String, dynamic>> contents = [];

      contents.add({
        "role": "user",
        "parts": [
          {
            "text":
                "Analyze the provided image and generate questions based on it."
          }
        ]
      });
      contents.add({
        "role": "model",
        "parts": [
          {
            "text":
                "Understood. I will analyze the image and prepare questions."
          }
        ]
      });

      List<Map<String, dynamic>> currentParts = [];
      currentParts.add({
        "inline_data": {
          "mime_type": _selectedImageMimeType ?? 'image/jpeg',
          "data": base64Image
        }
      });
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
            _parseGeneratedQuestions(); // Call parsing after response is set
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
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (_aiResponse.isEmpty ||
                        _isProcessingImage ||
                        _aiResponse.contains('Error')) ...[
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
                    ],

                    // Action Buttons Section
                    _buildActionButtonsSection(),

                    // AI Response Display
                    if (_aiResponse.isNotEmpty &&
                        !_isProcessingImage &&
                        !_aiResponse.contains('Error')) ...[
                      const SizedBox(height: 24),
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
            'Upload an image and let AI generate short or broad questions for you',
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
            items: ['Short Question', 'Broad Question'],
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
        if (_aiResponse.isEmpty ||
            _isProcessingImage ||
            _aiResponse.contains('Error')) ...[
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
              onPressed: (_selectedImage != null &&
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

        // No global "Show Answers" button needed with ExpansionTile
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

  void _parseGeneratedQuestions() {
    _generatedQuestions.clear();
    _generatedTopic = ''; // Clear topic before parsing
    List<String> lines = _aiResponse.split('\n');
    String currentQuestion = '';
    String currentAnswer = '';
    bool expectingAnswer = false;
    bool foundFirstQuestion = false; // New flag
    int startIndex = 0;

    // Try to extract topic from the first few lines
    for (int i = 0; i < lines.length; i++) {
      String line = lines[i].trim();
      if (line.toLowerCase().startsWith('topic:') ||
          line.toLowerCase().startsWith('বিষয়:')) {
        _generatedTopic = line.substring(line.indexOf(':') + 1).trim();
        startIndex = i + 1; // Start parsing questions from the next line
        break;
      }
      // If a question is found before a topic, start parsing from here
      if (RegExp(r'^\d+\.|^[\u09E6-\u09EF]+\.').hasMatch(line)) {
        startIndex = i;
        break;
      }
    }

    for (int i = startIndex; i < lines.length; i++) {
      String line = lines[i].trim();
      if (line.isEmpty) continue;

      // Check for question start (number followed by dot, or Bengali number followed by dot)
      if (RegExp(r'^\d+\.|^[\u09E6-\u09EF]+\.').hasMatch(line)) {
        if (currentQuestion.isNotEmpty) {
          _generatedQuestions.add({
            'question': _stripMarkdown(currentQuestion.trim()),
            'answer': _stripMarkdown(currentAnswer.trim()),
          });
        }
        // Strip the leading number and dot from the question
        currentQuestion = line
            .replaceFirst(RegExp(r'^\d+\. ?|^[\u09E6-\u09EF]+\. ?'), '')
            .trim();
        currentAnswer = '';
        expectingAnswer = true;
        foundFirstQuestion = true; // Set flag when first question is found
      } else if (foundFirstQuestion &&
          expectingAnswer && // Only process answers if we've found a question
          (line.toLowerCase().contains('উত্তর:') ||
              line.toLowerCase().contains('answer:') ||
              line.startsWith('উঃ'))) {
        // This is the start of an answer for the current question
        currentAnswer = line
            .replaceFirst(
                RegExp(r'^(উত্তর:|answer:|উঃ)', caseSensitive: false), '')
            .trim();
        expectingAnswer = false;
      } else if (foundFirstQuestion) {
        // Only append to question/answer if we've found a question
        // If we have a question and are not expecting a new answer, append to current answer
        // Otherwise, append to current question (for multi-line questions)
        if (currentQuestion.isNotEmpty && !expectingAnswer) {
          currentAnswer = '$currentAnswer $line';
        } else {
          currentQuestion = '$currentQuestion $line';
        }
      }
      // If not foundFirstQuestion, and not a question line, and not an answer line, just ignore it.
    }

    // Add the last question if exists
    if (currentQuestion.isNotEmpty) {
      _generatedQuestions.add({
        'question': _stripMarkdown(currentQuestion.trim()),
        'answer': _stripMarkdown(currentAnswer.trim()),
      });
    }
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
                  title: const SizedBox.shrink(), // Remove the "Question X" text
                  subtitle: Text(
                    question['question'] ?? '',
                    maxLines: 2,
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
                        child: Row( // Changed from Column to Row
                          crossAxisAlignment: CrossAxisAlignment.start, // Align content at the top
                          children: [
                            Text(
                              _selectedLanguage == 'বাংলা'
                                  ? 'উত্তর:'
                                  : 'Answer:',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                            const SizedBox(width: 8), // Add horizontal space between label and answer
                            Expanded( // Allow the answer text to take remaining space
                              child: Text(
                                question['answer'] ?? '',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Colors.green.shade800,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: _selectedQuestionType == 'Short Question' ? 1 : null,
                                overflow: _selectedQuestionType == 'Short Question' ? TextOverflow.ellipsis : null,
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
}

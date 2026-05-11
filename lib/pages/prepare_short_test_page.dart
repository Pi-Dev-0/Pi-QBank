import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import 'package:pi_qbank/widgets/api_key_dialog.dart'; // Import the API key dialog
import 'fill_in_the_blanks_test_page.dart';
import 'mcq_test_page.dart';
import 'short_question_page.dart';
import 'package:pi_qbank/widgets/custom_app_bar.dart';
import 'package:pi_qbank/services/test_result_service.dart'; // Import TestResultService
import 'package:pi_qbank/pages/short_question_analytics_page.dart'; // Import ShortQuestionAnalyticsPage
import 'package:pi_qbank/models/test_result.dart'; // Import TestResult
import 'package:pi_qbank/models/saved_test.dart'; // Import SavedTest model
import 'package:pi_qbank/services/saved_test_service.dart'; // Import SavedTestService
import 'package:uuid/uuid.dart'; // Import uuid for unique IDs
import 'package:pi_qbank/pages/saved_tests_page.dart'; // Import SavedTestsPage
import 'package:pi_qbank/widgets/view_and_edit_questions_dialog.dart';

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
  final List<XFile> _selectedImages = [];
  final List<String> _selectedImageMimeTypes = [];
  String _aiResponse = '';
  bool _isProcessingImage = false;
  String _selectedLanguage = 'বাংলা';
  final TextEditingController _customCommandController =
      TextEditingController(); // New controller
  bool _showAdvancedSettings = false; // New state variable
  final Uuid _uuid = const Uuid(); // Initialize Uuid

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
    _customCommandController.dispose(); // Dispose the new controller
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

  Future<void> _takePhoto() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 1200,
        maxHeight: 1200,
      );

      if (photo != null) {
        final File file = File(photo.path);
        if (await file.exists()) {
          setState(() {
            _selectedImages.add(photo);
            _selectedImageMimeTypes.add(photo.mimeType ?? 'image/jpeg');
            _aiResponse = '';
          });
        }
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      String message = 'Camera unavailable.';
      if (e.code == 'camera_access_denied') {
        message =
            'Camera permission denied. Please allow camera access in Settings.';
      } else if (e.message != null && e.message!.contains('startPreview')) {
        message =
            'Camera failed to start. Try closing other apps using the camera and restart.';
      } else {
        message = 'Camera error: ${e.message ?? e.code}';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          action: SnackBarAction(
            label: 'Use Gallery',
            textColor: Colors.white,
            onPressed: _pickImage,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error taking photo: ${e.toString()}'),
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
        ? 'Generate questions and answers strictly in Bengali (Bangla) language. '
        : 'Generate questions and answers strictly in English language. ';
    final String imageContext =
        _selectedImages.length > 1 ? 'these images' : 'this image';
    final String customCommand = _customCommandController.text.trim();
    final String customInstruction =
        customCommand.isNotEmpty ? '$customCommand. ' : '';

    switch (testType) {
      case 'MCQ Test':
        return '''
$languageInstruction${customInstruction}Generate $questionsCount multiple choice questions about $imageContext with 4 options each. 
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
        if (_selectedLanguage == 'বাংলা') {
          return '$languageInstruction$customInstruction এই $imageContext সম্পর্কে $questionsCount টি সংক্ষিপ্ত উত্তর প্রশ্ন তৈরি করুন যার জন্য সংক্ষিপ্ত ব্যাখ্যার প্রয়োজন। প্রতিটি উত্তর ১-৩ শব্দের মধ্যে হওয়া উচিত। প্রতিটি প্রশ্নের উত্তর একটি নতুন লাইনে "উত্তর:" দিয়ে শুরু হবে।';
        }
        return '$languageInstruction${customInstruction}Generate $questionsCount short answer questions about $imageContext that require brief explanations. Each answer should be 1-3 words. Each answer must start on a new line with "Answer:".';
      case 'Quiz Test':
        if (_selectedLanguage == 'বাংলা') {
          return '$languageInstruction$customInstruction এই $imageContext সম্পর্কে $questionsCount টি কুইজ প্রশ্ন তৈরি করুন। প্রতিটি প্রশ্নের উত্তর অবশ্যই মাত্র একটি বা দুটি শব্দের মধ্যে হতে হবে। প্রতিটি প্রশ্নের উত্তর একটি নতুন লাইনে "উত্তর:" দিয়ে শুরু হবে।';
        }
        return '$languageInstruction${customInstruction}Generate $questionsCount quiz questions about $imageContext. Each answer MUST be only one or two words long. Each answer must start on a new line with "Answer:".';
      case 'Fill In the Blanks':
        if (_selectedLanguage == 'বাংলা') {
          return '$languageInstruction$customInstruction এই $imageContext সম্পর্কে $questionsCount টি শূন্যস্থান পূরণ প্রশ্ন তৈরি করুন। বিন্যাস: শূন্যস্থানের জন্য _____ সহ প্রশ্ন, তারপরে সঠিক উত্তর।';
        }
        return '$languageInstruction${customInstruction}Generate $questionsCount fill-in-the-blank questions about $imageContext. Format: Question with _____ for blanks, followed by the correct answer.';
      default:
        if (_selectedLanguage == 'বাংলা') {
          return '$languageInstruction$customInstructionএকটি পরীক্ষার জন্য উপযোগী $questionsCount টি প্রশ্ন তৈরি করুন।';
        }
        return '$languageInstruction${customInstruction}Generate questions about $imageContext suitable for a test.';
    }
  }

  Future<void> _sendImageToGemini() async {
    if (_selectedImages.isEmpty || _selectedTestType == null) return;

    setState(() {
      _isProcessingImage = true;
      _aiResponse = 'Processing images...';
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      String provider = prefs.getString('global_ai_provider') ?? 'google';

      String? apiKey =
          await getApiKey(); // Try to get API key from SharedPreferences

      if (apiKey == null || apiKey.isEmpty) {
        // If not found in SharedPreferences, use the default from AppConfig
        apiKey = provider == 'openrouter'
            ? AppConfig.openRouterApiKey
            : AppConfig.geminiApiKey;
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
      String selectedModel = prefs.getString('global_image_model') ??
          prefs.getString('global_selected_model') ??
          prefs.getString('selected_model') ??
          'gemini-2.0-flash-001';

      // Ensure model supports images
      if (selectedModel.startsWith('gemma') ||
          selectedModel.contains('image')) {
        if (provider == 'google') {
          selectedModel = 'gemini-2.0-flash-001';
        } else if (provider == 'openrouter') {
          selectedModel = AppConfig.openRouterModelId;
        }
      }

      // Secondary fallback for OpenRouter model if it was gemini-2.0-flash-001 but no provider prefix
      if (provider == 'openrouter' && !selectedModel.contains('/')) {
        selectedModel = AppConfig.openRouterModelId;
      }
      final baseUrl = prefs.getString('global_ai_base_url') ??
          (provider == 'openrouter'
              ? AppConfig.openRouterBaseUrl
              : 'https://generativelanguage.googleapis.com/v1beta');

      String cleanUrl = baseUrl.trim();
      if (cleanUrl.isEmpty) {
        cleanUrl = 'https://generativelanguage.googleapis.com/v1beta';
      }
      if (cleanUrl.endsWith('/')) {
        cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
      }

      final bool isGoogle = provider == 'google';
      final url = isGoogle
          ? Uri.parse(
              '$cleanUrl/models/$selectedModel:generateContent?key=$apiKey')
          : (cleanUrl.endsWith('/chat/completions')
              ? Uri.parse(cleanUrl)
              : Uri.parse('$cleanUrl/chat/completions'));

      Map<String, String> headers = {'Content-Type': 'application/json'};
      if (!isGoogle) {
        headers['Authorization'] = 'Bearer $apiKey';
        if (provider == 'openrouter') {
          headers['HTTP-Referer'] = 'https://github.com/rashidsahriar/Pi-QBank';
          headers['X-Title'] = 'Pi-QBank';
        }
      }

      List<Map<String, dynamic>> googleParts = [];
      List<Map<String, dynamic>> openaiUserContent = [];
      String prompt = _getAIInstructions(_selectedTestType!);

      for (int i = 0; i < _selectedImages.length; i++) {
        final image = _selectedImages[i];
        final bytes = await image.readAsBytes();
        final base64Image = base64Encode(bytes);
        final mimeType = _selectedImageMimeTypes[i];

        if (isGoogle) {
          googleParts.add({
            "inline_data": {"mime_type": mimeType, "data": base64Image}
          });
        } else {
          openaiUserContent.add({
            "type": "image_url",
            "image_url": {"url": "data:$mimeType;base64,$base64Image"}
          });
        }
      }

      dynamic requestBody;
      if (isGoogle) {
        googleParts.add({"text": prompt});
        requestBody = {
          "contents": [
            {
              "role": "user",
              "parts": [
                {
                  "text":
                      "Analyze the provided images and generate questions based on them."
                }
              ]
            },
            {
              "role": "model",
              "parts": [
                {
                  "text":
                      "Understood. I will analyze the images and prepare questions."
                }
              ]
            },
            {"role": "user", "parts": googleParts}
          ]
        };
      } else {
        openaiUserContent.insert(0, {"type": "text", "text": prompt});
        requestBody = {
          "model": selectedModel,
          "messages": [
            {
              "role": "system",
              "content":
                  "Analyze image and provide test questions as requested."
            },
            {"role": "user", "content": openaiUserContent}
          ]
        };
      }

      debugPrint('AI URL: $url');
      debugPrint('AI Headers: $headers');
      // debugPrint('AI Request Body: ${json.encode(requestBody)}'); // Too large for log usually

      final response = await http.post(
        url,
        headers: headers,
        body: json.encode(requestBody),
      );

      debugPrint('AI Response Status: ${response.statusCode}');
      final String decodedBody = utf8.decode(response.bodyBytes);
      debugPrint('AI Response Body: $decodedBody');

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(decodedBody);
        String reply = '';
        if (jsonResponse['candidates'] != null &&
            jsonResponse['candidates'].isNotEmpty) {
          reply = jsonResponse['candidates'][0]['content']['parts'][0]['text'];
        } else if (jsonResponse['choices'] != null &&
            jsonResponse['choices'].isNotEmpty) {
          reply = jsonResponse['choices'][0]['message']['content'];
        }

        if (reply.isNotEmpty) {
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
    } catch (e, stackTrace) {
      debugPrint('API Error Detail: $e');
      debugPrint('Stack Trace: $stackTrace');
      setState(() {
        _aiResponse = 'Error: ${e.toString()}';
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceAll('Exception: ', ''),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
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
                    // Analytics Button
                    _buildAnalyticsButton(),
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
      padding: const EdgeInsets.all(16),
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
            size: 36,
            color: Colors.white,
          ),
          const SizedBox(height: 12),
          Text(
            'AI-Powered Test Generator',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Upload an image and let AI generate personalized questions for you',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.9),
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsButton() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.orange.shade600, Colors.deepOrange.shade800],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.orange.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ElevatedButton.icon(
            onPressed: () async {
              final List<TestResult> results =
                  await TestResultService.loadTestResults();
              if (!mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ShortQuestionAnalyticsPage(
                    testResults: results,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.analytics_outlined, size: 24),
            label: const Text(
              'View All Test Analytics',
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
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.teal.shade600, Colors.cyan.shade800],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.teal.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SavedTestsPage()),
              );
            },
            icon: const Icon(Icons.save_alt_outlined, size: 24),
            label: const Text(
              'View Saved Tests',
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
            items: [
              'MCQ Test',
              'Short Question',
              'Quiz Test',
              'Fill In the Blanks'
            ],
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
            items: ['বাংলা', 'English'],
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
                  'Processing Images...',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue.shade800,
                  ),
                ),
                Text(
                  'AI is analyzing your images to generate questions',
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
                      ? 'Please try again with different images'
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
              const SizedBox(height: 16),
              Theme(
                data: Theme.of(context).copyWith(
                    dividerColor:
                        Colors.transparent), // Hide the default divider
                child: ExpansionTile(
                  tilePadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  collapsedBackgroundColor: Colors.grey.shade50,
                  backgroundColor: Colors.grey.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  title: Text(
                    'Advanced Settings',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  leading:
                      Icon(Icons.api_outlined, color: Colors.purple.shade600),
                  trailing: Icon(
                    _showAdvancedSettings
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: Colors.purple.shade600,
                  ),
                  onExpansionChanged: (bool expanded) {
                    setState(() {
                      _showAdvancedSettings = expanded;
                    });
                  },
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: _buildStylishTextField(
                        label: 'Custom AI Instruction',
                        icon: Icons.text_snippet_outlined,
                        keyboardType: TextInputType.text,
                        onChanged: (value) {
                          _customCommandController.text = value;
                        },
                        controller: _customCommandController,
                        maxLines: 3,
                      ),
                    ),
                  ],
                ),
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
    TextEditingController? controller,
    int? maxLines,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        color: Colors.grey.shade50,
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
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
            onPressed: (_selectedImages.isNotEmpty &&
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

        // View & Edit Button
        if (_aiResponse.isNotEmpty &&
            !_isProcessingImage &&
            !_aiResponse.contains('Error')) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.purple.shade600, Colors.deepPurple.shade800],
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
              onPressed: _viewAndEditQuestions,
              icon: const Icon(Icons.edit_note, size: 24),
              label: const Text(
                'View & Edit Questions',
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

        // Save Test Button
        if (_aiResponse.isNotEmpty &&
            !_isProcessingImage &&
            !_aiResponse.contains('Error')) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.orange.shade600, Colors.deepOrange.shade800],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: _saveTest,
              icon: const Icon(Icons.save, size: 24),
              label: const Text(
                'Save Test for Later',
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
          const SizedBox(height: 16),
          // Start Test Button
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
                        selectedImages: _selectedImages,
                        aiResponse: _aiResponse,
                        language: _selectedLanguage,
                      );
                      break;
                    case 'Short Question':
                      testPage = ShortQuestionPage(
                        numberOfQuestions: _numberOfQuestions!,
                        testTimeInMinutes: _testTimeInMinutes!,
                        selectedImages: _selectedImages,
                        aiResponse: _aiResponse,
                        language: _selectedLanguage,
                        testType: 'Short Question',
                      );
                      break;
                    case 'Quiz Test':
                      testPage = ShortQuestionPage(
                        numberOfQuestions: _numberOfQuestions!,
                        testTimeInMinutes: _testTimeInMinutes!,
                        selectedImages: _selectedImages,
                        aiResponse: _aiResponse,
                        language: _selectedLanguage,
                        testType: 'Quiz Test',
                      );
                      break;
                    case 'Fill In the Blanks':
                      testPage = FillInTheBlanksTestPage(
                        numberOfQuestions: _numberOfQuestions!,
                        testTimeInMinutes: _testTimeInMinutes!,
                        aiResponse: _aiResponse,
                        language: _selectedLanguage,
                        selectedImages: _selectedImages,
                      );
                      break;
                    default:
                      testPage = FillInTheBlanksTestPage(
                        numberOfQuestions: _numberOfQuestions!,
                        testTimeInMinutes: _testTimeInMinutes!,
                        aiResponse: _aiResponse,
                        language: _selectedLanguage,
                        selectedImages: _selectedImages,
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
          if (_selectedImages.isEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Icon(
                      Icons.image_search_outlined,
                      size: 48,
                      color: Colors.blue.shade600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Add an Image to Generate Questions',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Choose from gallery or take a new photo',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.photo_library_outlined, size: 20),
                      label: const Text(
                        'Choose File',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.blue.shade700,
                        backgroundColor: Colors.blue.shade50,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: Colors.blue.shade200),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _takePhoto,
                      icon: const Icon(Icons.camera_alt_outlined, size: 20),
                      label: const Text(
                        'Take Photo',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.green.shade700,
                        backgroundColor: Colors.green.shade50,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: Colors.green.shade200),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _pickImage,
                          icon: const Icon(Icons.photo_library_outlined,
                              size: 18),
                          label: const Text('Add More'),
                          style: ElevatedButton.styleFrom(
                            foregroundColor: Colors.blue.shade700,
                            backgroundColor: Colors.blue.shade50,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.blue.shade200),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _takePhoto,
                          icon: const Icon(Icons.camera_alt_outlined, size: 18),
                          label: const Text('Take Photo'),
                          style: ElevatedButton.styleFrom(
                            foregroundColor: Colors.green.shade700,
                            backgroundColor: Colors.green.shade50,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.green.shade200),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _saveTest() async {
    if (_selectedTestType == null ||
        _numberOfQuestions == null ||
        _testTimeInMinutes == null ||
        _testTimeInMinutes! <= 0 ||
        _aiResponse.isEmpty ||
        _aiResponse.contains('Error')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'Cannot save test. Please generate questions first and ensure all fields are valid.'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    final savedTest = SavedTest(
      id: _uuid.v4(), // Generate a unique ID
      testType: _selectedTestType!,
      numberOfQuestions: _numberOfQuestions!,
      testTimeInMinutes: _testTimeInMinutes!,
      imagePaths: _selectedImages.map((xFile) => xFile.path).toList(),
      aiResponse: _aiResponse,
      language: _selectedLanguage,
      savedDate: DateTime.now(),
    );

    await SavedTestService.saveTest(savedTest);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Test saved successfully!'),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _viewAndEditQuestions() async {
    if (_aiResponse.isEmpty) return;

    List<Map<String, String>> parsedQuestions = [];

    try {
      // First, try to parse as JSON for MCQ tests
      String cleanedResponse =
          _aiResponse.replaceAll('```json', '').replaceAll('```', '').trim();
      final jsonResponse = json.decode(cleanedResponse);

      if (jsonResponse['questions'] != null) {
        final List<dynamic> questions = jsonResponse['questions'];
        for (var q in questions) {
          String questionText = q['question'] ?? 'No question text';
          Map<String, dynamic> options = q['options'] ?? {};
          String correctAnswer = q['correct_answer'] ?? 'N/A';

          String fullQuestion = questionText;
          options.forEach((key, value) {
            fullQuestion += '\n$key: $value';
          });

          parsedQuestions.add({
            'question': fullQuestion,
            'answer': correctAnswer,
          });
        }
      } else {
        throw Exception("Not a valid MCQ JSON format.");
      }
    } catch (e) {
      // If JSON parsing fails, fall back to plain text parsing for Short Questions
      try {
        final questionBlocks = _aiResponse.trim().split(RegExp(r'\n\s*\n+'));

        for (var block in questionBlocks) {
          if (block.trim().isEmpty) continue;

          String question = '';
          String answer = '';
          final lines = block.trim().split('\n');
          List<String> questionLines = [];
          bool answerFound = false;

          for (var line in lines) {
            line = line.trim();
            if (RegExp(r'^(answer:|উত্তর:|উঃ)', caseSensitive: false)
                .hasMatch(line)) {
              answer = line
                  .replaceFirst(
                      RegExp(r'^(answer:|উত্তর:|উঃ)', caseSensitive: false), '')
                  .trim();
              answerFound = true;
            } else if (!answerFound) {
              questionLines.add(line);
            } else {
              answer += '\n$line';
            }
          }

          question = questionLines.join(' ').trim();
          question = question
              .replaceFirst(RegExp(r'^\d+\.\s*|^[০-৯]+\.\s*'), '')
              .trim();

          if (question.isNotEmpty) {
            parsedQuestions.add({
              'question': _stripMarkdown(question),
              'answer': _stripMarkdown(answer),
            });
          }
        }
      } catch (e2) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error parsing questions: ${e2.toString()}'),
            backgroundColor: Colors.red.shade600,
          ),
        );
        return;
      }
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ViewAndEditQuestionsDialog(
          initialQuestions: parsedQuestions,
          selectedLanguage: _selectedLanguage,
          selectedTestType: _selectedTestType ?? '',
          onSave: (updatedQuestions) {
            if (_selectedTestType == 'MCQ Test') {
              List<Map<String, dynamic>> questionsList = [];
              for (var q in updatedQuestions) {
                final lines = q['question']!.split('\n');
                final questionText = lines[0];
                final options = <String, String>{};
                for (int i = 1; i < lines.length; i++) {
                  final optionParts = lines[i].split(': ');
                  if (optionParts.length == 2) {
                    options[optionParts[0]] = optionParts[1];
                  }
                }
                questionsList.add({
                  "question": questionText,
                  "options": options,
                  "correct_answer": q['answer'],
                });
              }
              final newJsonResponse = {"questions": questionsList};
              setState(() {
                _aiResponse = '```json\n${json.encode(newJsonResponse)}\n```';
                _numberOfQuestions = updatedQuestions.length;
              });
            } else {
              StringBuffer newResponse = StringBuffer();
              for (int i = 0; i < updatedQuestions.length; i++) {
                newResponse
                    .writeln('${i + 1}. ${updatedQuestions[i]['question']}');
                newResponse.writeln('Answer: ${updatedQuestions[i]['answer']}');
                newResponse.writeln();
              }
              setState(() {
                _aiResponse = newResponse.toString();
                _numberOfQuestions = updatedQuestions.length;
              });
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_selectedLanguage == 'বাংলা'
                    ? 'পরিবর্তনগুলো সংরক্ষণ করা হয়েছে'
                    : 'Changes saved successfully'),
                backgroundColor: Colors.green,
              ),
            );
          },
        ),
      ),
    );
  }

  String _stripMarkdown(String text) {
    String strippedText = text.replaceAll(RegExp(r'\*\*([^\*]+)\*\*'), r'\1');
    strippedText = strippedText.replaceAll(RegExp(r'\*([^\*]+)\*'), r'\1');
    strippedText = strippedText.replaceAll(RegExp(r'\*'), '');
    return strippedText.trim();
  }
}

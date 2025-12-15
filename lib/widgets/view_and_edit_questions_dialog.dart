import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../widgets/api_key_dialog.dart';
import '../widgets/delete_confirmation_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ViewAndEditQuestionsDialog extends StatefulWidget {
  final List<Map<String, String>> initialQuestions;
  final String selectedLanguage;
  final String selectedTestType;
  final List<XFile> selectedImages;
  final Function(List<Map<String, String>>) onSave;

  const ViewAndEditQuestionsDialog({
    super.key,
    required this.initialQuestions,
    required this.selectedLanguage,
    required this.selectedTestType,
    required this.selectedImages,
    required this.onSave,
  });

  @override
  State<ViewAndEditQuestionsDialog> createState() =>
      _ViewAndEditQuestionsDialogState();
}

class _ViewAndEditQuestionsDialogState
    extends State<ViewAndEditQuestionsDialog> {
  late List<Map<String, String>> _questions;

  @override
  void initState() {
    super.initState();
    _questions = List.from(widget.initialQuestions);
  }

  Future<String?> _getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('gemini_api_key');
  }

  Future<void> _regenerateSingleQuestion(int index) async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      String? apiKey = await _getApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        apiKey = AppConfig.geminiApiKey;
      }

      if (apiKey.isEmpty) {
        if (!mounted) return;
        Navigator.pop(context); // Close loading
        showApiKeyDialog(context);
        return;
      }

      final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$apiKey');

      List<Map<String, dynamic>> parts = [];

      // Add images if available
      if (widget.selectedImages.isNotEmpty) {
        for (int i = 0; i < widget.selectedImages.length; i++) {
          final image = widget.selectedImages[i];
          final bytes = await image.readAsBytes();
          final base64Image = base64Encode(bytes);
          parts.add({
            "inline_data": {
              "mime_type": image.mimeType ?? 'image/jpeg',
              "data": base64Image
            }
          });
        }
      }

      final String languageInstruction = widget.selectedLanguage == 'বাংলা'
          ? 'Generate a question and answer strictly in Bengali (Bangla) language. '
          : 'Generate a question and answer strictly in English language. ';

      final String currentQuestion = _questions[index]['question'] ?? '';
      final String nonce = DateTime.now().millisecondsSinceEpoch.toString();

      String prompt = '';

      // Generate prompt based on test type
      if (widget.selectedTestType == 'MCQ Test') {
        if (widget.selectedLanguage == 'বাংলা') {
          prompt =
              '$languageInstruction এই ছবি সম্পর্কে ১টি বহুনির্বাচনী প্রশ্ন তৈরি করুন যার ৪টি অপশন থাকবে। নিম্নলিখিত JSON ফরম্যাটে উত্তর দিন:\n\n{\n  "question": "প্রশ্নের টেক্সট?",\n  "options": {\n    "A": "অপশন A",\n    "B": "অপশন B",\n    "C": "অপশন C",\n    "D": "অপশন D"\n  },\n  "correct_answer": "A"\n}\n\nএই প্রশ্নটি তৈরি করবেন না: "$currentQuestion" (Random: $nonce)';
        } else {
          prompt =
              '${languageInstruction}Generate 1 multiple choice question about this image with 4 options. Respond in the following JSON format:\n\n{\n  "question": "Question text?",\n  "options": {\n    "A": "Option A",\n    "B": "Option B",\n    "C": "Option C",\n    "D": "Option D"\n  },\n  "correct_answer": "A"\n}\n\nDo NOT generate this question: "$currentQuestion" (Random: $nonce)';
        }
      } else if (widget.selectedTestType == 'Fill In the Blanks') {
        if (widget.selectedLanguage == 'বাংলা') {
          prompt =
              '$languageInstruction এই ছবি সম্পর্কে ১টি শূন্যস্থান পূরণ প্রশ্ন তৈরি করুন। ফরম্যাট: শূন্যস্থানের জন্য _____ সহ প্রশ্ন, তারপর সঠিক উত্তর। প্রশ্নের উত্তর একটি নতুন লাইনে "উত্তর:" দিয়ে শুরু হবে। এই প্রশ্নটি তৈরি করবেন না: "$currentQuestion" (Random: $nonce)';
        } else {
          prompt =
              '${languageInstruction}Generate 1 fill-in-the-blank question about this image. Format: Question with _____ for blanks, followed by the correct answer on a new line starting with "Answer:". Do NOT generate this question: "$currentQuestion" (Random: $nonce)';
        }
      } else {
        // Short Question (default)
        if (widget.selectedLanguage == 'বাংলা') {
          prompt =
              '$languageInstruction এই ছবি সম্পর্কে ১টি সংক্ষিপ্ত উত্তর প্রশ্ন তৈরি করুন যার জন্য সংক্ষিপ্ত ব্যাখ্যার প্রয়োজন। উত্তর ১-৩ শব্দের মধ্যে হওয়া উচিত। প্রশ্নের উত্তর একটি নতুন লাইনে "উত্তর:" দিয়ে শুরু হবে। এই প্রশ্নটি তৈরি করবেন না: "$currentQuestion" (Random: $nonce)';
        } else {
          prompt =
              '${languageInstruction}Generate 1 short answer question about this image that requires brief explanation. Answer should be 1-3 words. Answer must start on a new line with "Answer:". Do NOT generate this question: "$currentQuestion" (Random: $nonce)';
        }
      }

      parts.add({"text": prompt});

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          "contents": [
            {"role": "user", "parts": parts}
          ]
        }),
      );

      if (!mounted) return;
      Navigator.pop(context); // Close loading

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        if (jsonResponse['candidates'] != null &&
            jsonResponse['candidates'].isNotEmpty) {
          final reply =
              jsonResponse['candidates'][0]['content']['parts'][0]['text'];

          if (widget.selectedTestType == 'MCQ Test') {
            // Parse MCQ JSON response
            try {
              String cleanedReply =
                  reply.replaceAll('```json', '').replaceAll('```', '').trim();
              final mcqData = json.decode(cleanedReply);

              String questionText = mcqData['question'] ?? '';
              Map<String, dynamic> options = mcqData['options'] ?? {};
              String correctAnswer = mcqData['correct_answer'] ?? 'A';

              // Format as: Question\nA: Option A\nB: Option B\nC: Option C\nD: Option D
              StringBuffer formattedQuestion = StringBuffer();
              formattedQuestion.writeln(questionText);
              options.forEach((key, value) {
                formattedQuestion.writeln('$key: $value');
              });

              setState(() {
                _questions[index] = {
                  'question': formattedQuestion.toString().trim(),
                  'answer': correctAnswer,
                };
              });

              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(widget.selectedLanguage == 'বাংলা'
                      ? 'প্রশ্ন পুনরায় তৈরি করা হয়েছে'
                      : 'Question regenerated successfully'),
                  backgroundColor: Colors.green,
                ),
              );
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Failed to parse MCQ: ${e.toString()}'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          } else {
            // Parse Short Question or Fill in the Blanks response
            String question = '';
            String answer = '';
            final lines = reply.trim().split('\n');
            List<String> questionLines = [];
            bool answerFound = false;

            for (var line in lines) {
              line = line.trim();
              if (RegExp(r'^(answer:|উত্তর:|উঃ)', caseSensitive: false)
                  .hasMatch(line)) {
                answer = line
                    .replaceFirst(
                        RegExp(r'^(answer:|উত্তর:|উঃ)', caseSensitive: false),
                        '')
                    .trim();
                answerFound = true;
              } else if (!answerFound) {
                questionLines.add(line);
              } else {
                answer += '\n$line';
              }
            }

            question = questionLines.join(' ').trim();

            if (question.isNotEmpty) {
              setState(() {
                _questions[index] = {
                  'question': question,
                  'answer': answer,
                };
              });

              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(widget.selectedLanguage == 'বাংলা'
                      ? 'প্রশ্ন পুনরায় তৈরি করা হয়েছে'
                      : 'Question regenerated successfully'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          }
        }
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to regenerate: ${response.statusCode}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading if error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.purple.shade600, Colors.deepPurple.shade600],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.edit_note,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      widget.selectedLanguage == 'বাংলা'
                          ? 'প্রশ্ন সম্পাদনা করুন'
                          : 'View & Edit Questions',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: _questions.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.assignment_outlined,
                              size: 64, color: Colors.grey.shade300),
                          const SizedBox(height: 16),
                          Text(
                            widget.selectedLanguage == 'বাংলা'
                                ? 'কোন প্রশ্ন পাওয়া যায়নি'
                                : 'No questions found',
                            style: TextStyle(
                                color: Colors.grey.shade500, fontSize: 16),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(24),
                      itemCount: _questions.length,
                      itemBuilder: (context, index) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.grey.shade200, width: 1),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Question Header
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(20),
                                    topRight: Radius.circular(20),
                                  ),
                                  border: Border(
                                    bottom:
                                        BorderSide(color: Colors.grey.shade200),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.purple.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        widget.selectedLanguage == 'বাংলা'
                                            ? 'প্রশ্ন ${index + 1}'
                                            : 'Question ${index + 1}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Colors.purple.shade800,
                                        ),
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.refresh,
                                              color: Colors.orange, size: 20),
                                          onPressed: () =>
                                              _regenerateSingleQuestion(index),
                                          tooltip:
                                              widget.selectedLanguage == 'বাংলা'
                                                  ? 'প্রশ্ন পরিবর্তন করুন'
                                                  : 'Regenerate',
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline,
                                              color: Colors.red, size: 20),
                                          onPressed: () async {
                                            final bool? confirmed =
                                                await showDeleteConfirmationDialog(
                                              context: context,
                                              title: 'Delete Question',
                                              message:
                                                  'Are you sure you want to delete this question?',
                                            );
                                            if (confirmed == true) {
                                              setState(() {
                                                _questions.removeAt(index);
                                              });
                                            }
                                          },
                                          tooltip:
                                              widget.selectedLanguage == 'বাংলা'
                                                  ? 'মুছে ফেলুন'
                                                  : 'Delete',
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              // Inputs
                              Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  children: [
                                    TextFormField(
                                      key: ValueKey(
                                          _questions[index]['question']),
                                      initialValue: _questions[index]
                                          ['question'],
                                      maxLines: 3,
                                      decoration: InputDecoration(
                                        labelText:
                                            widget.selectedLanguage == 'বাংলা'
                                                ? 'প্রশ্ন'
                                                : 'Question',
                                        alignLabelWithHint: true,
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          borderSide: BorderSide(
                                              color: Colors.grey.shade300),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          borderSide: BorderSide(
                                              color: Colors.grey.shade300),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          borderSide: BorderSide(
                                              color: Colors.purple.shade600,
                                              width: 2),
                                        ),
                                        filled: true,
                                        fillColor: Colors.grey.shade50,
                                        contentPadding:
                                            const EdgeInsets.all(16),
                                      ),
                                      onChanged: (value) {
                                        _questions[index]['question'] = value;
                                      },
                                    ),
                                    const SizedBox(height: 16),
                                    TextFormField(
                                      key:
                                          ValueKey(_questions[index]['answer']),
                                      initialValue: _questions[index]['answer'],
                                      maxLines: 2,
                                      decoration: InputDecoration(
                                        labelText:
                                            widget.selectedLanguage == 'বাংলা'
                                                ? 'উত্তর'
                                                : 'Answer',
                                        alignLabelWithHint: true,
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          borderSide: BorderSide(
                                              color: Colors.grey.shade300),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          borderSide: BorderSide(
                                              color: Colors.grey.shade300),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          borderSide: BorderSide(
                                              color: Colors.green.shade600,
                                              width: 2),
                                        ),
                                        filled: true,
                                        fillColor: Colors.green.shade50,
                                        contentPadding:
                                            const EdgeInsets.all(16),
                                      ),
                                      onChanged: (value) {
                                        _questions[index]['answer'] = value;
                                      },
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

            // Footer
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      foregroundColor: Colors.grey.shade700,
                    ),
                    child: Text(widget.selectedLanguage == 'বাংলা'
                        ? 'বাতিল'
                        : 'Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      widget.onSave(_questions);
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.save_outlined, size: 20),
                    label: Text(widget.selectedLanguage == 'বাংলা'
                        ? 'সংরক্ষণ করুন'
                        : 'Save Changes'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

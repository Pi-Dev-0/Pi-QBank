import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/app_config.dart';
import 'package:pi_qbank/widgets/api_key_dialog.dart';
import '../widgets/custom_app_bar.dart';


class ExamPaperBuilderPage extends StatefulWidget {
  const ExamPaperBuilderPage({super.key});

  @override
  State<ExamPaperBuilderPage> createState() => _ExamPaperBuilderPageState();
}

class _ExamPaperBuilderPageState extends State<ExamPaperBuilderPage> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();
  
  // Form controllers
  final TextEditingController _examTimeController = TextEditingController();
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _instituteController = TextEditingController();
  final TextEditingController _totalMarksController = TextEditingController();
  final TextEditingController _directionsController = TextEditingController();
  
  // Question type checkboxes
  bool _creativeSrojonshil = false;
  bool _shortSangkhipto = false;
  bool _mcqMultipleChoice = false;
  
  // Image lists for each question type
  final List<File> _creativeSrojonshilImages = [];
  final List<File> _shortSangkhiptoImages = [];
  final List<File> _mcqImages = [];
  
  // Generated questions
  List<String> _creativeSrojonshilQuestions = [];
  List<String> _shortSangkhiptoQuestions = [];
  List<String> _mcqQuestions = [];
  
  bool _isGenerating = false;
  
  @override
  void initState() {
    super.initState();
    // Set default values
    _examTimeController.text = '৩ ঘন্টা';
    _directionsController.text = 'নির্দেশনা: সব প্রশ্নের উত্তর দিতে হবে। প্রতিটি প্রশ্নের উত্তর আলাদা খাতায় লিখতে হবে।';
  }

  Future<void> _pickImages(String questionType) async {
    final List<XFile> images = await _picker.pickMultiImage();
    if (images.isNotEmpty) {
      setState(() {
        List<File> imageFiles = images.map((image) => File(image.path)).toList();
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

  Future<List<String>> _generateQuestionsFromImages(List<File> images, String questionType) async {
    String? apiKey = await getApiKey(); // Try to get API key from SharedPreferences

    if (apiKey == null || apiKey.isEmpty) {
      // If not found in SharedPreferences, use the default from AppConfig
      apiKey = AppConfig.geminiApiKey;
    }

    if (apiKey.isEmpty) {
      throw Exception('API Key not set. Please enter your API key.');
    }
    
    final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$apiKey');
    
    List<String> questions = [];
    
    String prompt = '';
    switch (questionType) {
      case 'creative':
        prompt = '''এই ছবি থেকে বাংলায় সৃজনশীল প্রশ্ন তৈরি করুন। প্রতিটি প্রশ্নে থাকবে:
১. উদ্দীপক (একটি ছোট অনুচ্ছেদ বা তথ্য)
২. ক) জ্ঞানমূলক প্রশ্ন (১ নম্বর)
৩. খ) অনুধাবনমূলক প্রশ্ন (২ নম্বর)
৪. গ) প্রয়োগমূলক প্রশ্ন (৩ নম্বর)
৫. ঘ) উচ্চতর দক্ষতামূলক প্রশ্ন (৪ নম্বর)

প্রশ্নটি সম্পূর্ণ বাংলায় লিখুন।''';
        break;
      case 'short':
        prompt = '''এই ছবি থেকে বাংলায় সংক্ষিপ্ত প্রশ্ন তৈরি করুন। প্রতিটি প্রশ্ন ২-৫ নম্বরের হবে এবং উত্তর ৫০-১০০ শব্দের মধ্যে হওয়া উচিত। প্রশ্নগুলো বাংলায় লিখুন.''';
        break;
      case 'mcq':
        prompt = '''এই ছবি থেকে বাংলায় বহুনির্বাচনি প্রশ্ন (MCQ) তৈরি করুন। প্রতিটি প্রশ্নে:
১. প্রশ্ন
২. চারটি অপশন (ক, খ, গ, ঘ)
৩. সঠিক উত্তর নির্দেশ করুন

প্রশ্ন ও অপশন সব বাংলায় লিখুন।''';
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
            {"inline_data": {"mime_type": "image/jpeg", "data": base64Image}},
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
            questions.add(reply);
          } 
        }
      } catch (e) {
        Text('Error generating question from image: $e');
      }
    }
    
    return questions;
  }

  Future<void> _generateQuestions() async {
    setState(() {
      _isGenerating = true;
    });
    
    try {
      if (_creativeSrojonshil && _creativeSrojonshilImages.isNotEmpty) {
        _creativeSrojonshilQuestions = await _generateQuestionsFromImages(_creativeSrojonshilImages, 'creative');
      }
      
      if (_shortSangkhipto && _shortSangkhiptoImages.isNotEmpty) {
        _shortSangkhiptoQuestions = await _generateQuestionsFromImages(_shortSangkhiptoImages, 'short');
      }
      
      if (_mcqMultipleChoice && _mcqImages.isNotEmpty) {
        _mcqQuestions = await _generateQuestionsFromImages(_mcqImages, 'mcq');
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('প্রশ্ন সফলভাবে তৈরি হয়েছে!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ত্রুটি: $e')),
      );
    } finally {
      setState(() {
        _isGenerating = false;
      });
    }
  }

  Future<void> _generatePDF() async {
    final pdf = pw.Document();
    
    // Load Bengali font (you'll need to add this to your assets)
    final font = await PdfGoogleFonts.notoSansBengaliRegular();
    final boldFont = await PdfGoogleFonts.notoSansBengaliBold();
    
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
                    _instituteController.text,
                    style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Text(
                    'বিষয়: ${_subjectController.text}',
                    style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 5),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('সময়: ${_examTimeController.text}'),
                      pw.Text('পূর্ণমান: ${_totalMarksController.text}'),
                    ],
                  ),
                  pw.SizedBox(height: 20),
                ],
              ),
            ),
            
            // Directions
            if (_directionsController.text.isNotEmpty) ...[
              pw.Text(
                _directionsController.text,
                style: pw.TextStyle(fontSize: 12, fontStyle: pw.FontStyle.italic),
              ),
              pw.SizedBox(height: 20),
            ],
            
            // Creative Questions
            if (_creativeSrojonshil && _creativeSrojonshilQuestions.isNotEmpty) ...[
              pw.Text(
                'সৃজনশীল প্রশ্ন',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 10),
              ...List.generate(_creativeSrojonshilQuestions.length, (index) => 
                pw.Container(
                  margin: pw.EdgeInsets.only(bottom: 20),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        '${index + 1}. ${_creativeSrojonshilQuestions[index]}',
                        style: pw.TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            
            // Short Questions
            if (_shortSangkhipto && _shortSangkhiptoQuestions.isNotEmpty) ...[
              pw.Text(
                'সংক্ষিপ্ত প্রশ্ন',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 10),
              ...List.generate(_shortSangkhiptoQuestions.length, (index) => 
                pw.Container(
                  margin: pw.EdgeInsets.only(bottom: 15),
                  child: pw.Text(
                    '${index + 1}. ${_shortSangkhiptoQuestions[index]}',
                    style: pw.TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
            
            // MCQ Questions
            if (_mcqMultipleChoice && _mcqQuestions.isNotEmpty) ...[
              pw.Text(
                'বহুনির্বাচনি প্রশ্ন',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 10),
              ...List.generate(_mcqQuestions.length, (index) => 
                pw.Container(
                  margin: pw.EdgeInsets.only(bottom: 15),
                  child: pw.Text(
                    '${index + 1}. ${_mcqQuestions[index]}',
                    style: pw.TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ];
        },
      ),
    );
    
    // Show PDF preview and print
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(
        title: 'পরীক্ষার প্রশ্নপত্র তৈরি করুন',
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Gemini API Key Button
              ElevatedButton.icon(
                onPressed: () {
                  showApiKeyDialog(context);
                },
                icon: const Icon(Icons.key),
                label: const Text('Gemini API Key সেট করুন'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[600],
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50), // full width button
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // Basic Information
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'মৌলিক তথ্য',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      
                      TextFormField(
                        controller: _instituteController,
                        decoration: const InputDecoration(
                          labelText: 'স্কুল/কলেজ/কোচিং/প্রতিষ্ঠানের নাম *',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'প্রতিষ্ঠানের নাম প্রয়োজন';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _subjectController,
                              decoration: const InputDecoration(
                                labelText: 'বিষয়ের নাম *',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'বিষয়ের নাম প্রয়োজন';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _examTimeController,
                              decoration: const InputDecoration(
                                labelText: 'পরীক্ষার সময়',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      TextFormField(
                        controller: _totalMarksController,
                        decoration: const InputDecoration(
                          labelText: 'মোট নম্বর *',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'মোট নম্বর প্রয়োজন';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      TextFormField(
                        controller: _directionsController,
                        decoration: const InputDecoration(
                          labelText: 'পরীক্ষার্থীদের জন্য নির্দেশনা',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // Question Types
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'প্রশ্নের ধরন নির্বাচন করুন',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      
                      // Creative Questions
                      CheckboxListTile(
                        title: const Text('সৃজনশীল প্রশ্ন'),
                        value: _creativeSrojonshil,
                        onChanged: (value) {
                          setState(() {
                            _creativeSrojonshil = value!;
                          });
                        },
                      ),
                      if (_creativeSrojonshil) ...[
                        Padding(
                          padding: const EdgeInsets.only(left: 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ElevatedButton.icon(
                                onPressed: () => _pickImages('creative'),
                                icon: const Icon(Icons.add_photo_alternate),
                                label: const Text('ছবি যোগ করুন'),
                              ),
                              const SizedBox(height: 8),
                              if (_creativeSrojonshilImages.isNotEmpty)
                                SizedBox(
                                  height: 100,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: _creativeSrojonshilImages.length,
                                    itemBuilder: (context, index) {
                                      return Container(
                                        margin: const EdgeInsets.only(right: 8),
                                        child: Stack(
                                          children: [
                                            Image.file(
                                              _creativeSrojonshilImages[index],
                                              width: 80,
                                              height: 80,
                                              fit: BoxFit.cover,
                                            ),
                                            Positioned(
                                              top: 0,
                                              right: 0,
                                              child: GestureDetector(
                                                onTap: () => _removeImage('creative', index),
                                                child: Container(
                                                  decoration: const BoxDecoration(
                                                    color: Colors.red,
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
                          ),
                        ),
                      ],
                      
                      // Short Questions
                      CheckboxListTile(
                        title: const Text('সংক্ষিপ্ত প্রশ্ন'),
                        value: _shortSangkhipto,
                        onChanged: (value) {
                          setState(() {
                            _shortSangkhipto = value!;
                          });
                        },
                      ),
                      if (_shortSangkhipto) ...[
                        Padding(
                          padding: const EdgeInsets.only(left: 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ElevatedButton.icon(
                                onPressed: () => _pickImages('short'),
                                icon: const Icon(Icons.add_photo_alternate),
                                label: const Text('ছবি যোগ করুন'),
                              ),
                              const SizedBox(height: 8),
                              if (_shortSangkhiptoImages.isNotEmpty)
                                SizedBox(
                                  height: 100,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: _shortSangkhiptoImages.length,
                                    itemBuilder: (context, index) {
                                      return Container(
                                        margin: const EdgeInsets.only(right: 8),
                                        child: Stack(
                                          children: [
                                            Image.file(
                                              _shortSangkhiptoImages[index],
                                              width: 80,
                                              height: 80,
                                              fit: BoxFit.cover,
                                            ),
                                            Positioned(
                                              top: 0,
                                              right: 0,
                                              child: GestureDetector(
                                                onTap: () => _removeImage('short', index),
                                                child: Container(
                                                  decoration: const BoxDecoration(
                                                    color: Colors.red,
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
                          ),
                        ),
                      ],
                      
                      // MCQ Questions
                      CheckboxListTile(
                        title: const Text('বহুনির্বাচনি প্রশ্ন (MCQ)'),
                        value: _mcqMultipleChoice,
                        onChanged: (value) {
                          setState(() {
                            _mcqMultipleChoice = value!;
                          });
                        },
                      ),
                      if (_mcqMultipleChoice) ...[
                        Padding(
                          padding: const EdgeInsets.only(left: 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ElevatedButton.icon(
                                onPressed: () => _pickImages('mcq'),
                                icon: const Icon(Icons.add_photo_alternate),
                                label: const Text('ছবি যোগ করুন'),
                              ),
                              const SizedBox(height: 8),
                              if (_mcqImages.isNotEmpty)
                                SizedBox(
                                  height: 100,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: _mcqImages.length,
                                    itemBuilder: (context, index) {
                                      return Container(
                                        margin: const EdgeInsets.only(right: 8),
                                        child: Stack(
                                          children: [
                                            Image.file(
                                              _mcqImages[index],
                                              width: 80,
                                              height: 80,
                                              fit: BoxFit.cover,
                                            ),
                                            Positioned(
                                              top: 0,
                                              right: 0,
                                              child: GestureDetector(
                                                onTap: () => _removeImage('mcq', index),
                                                child: Container(
                                                  decoration: const BoxDecoration(
                                                    color: Colors.red,
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
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              
              // Action Buttons
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: (_isGenerating || !_hasSelectedTypeWithImages()) 
                              ? null 
                              : _generateQuestions,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: _isGenerating
                              ? const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text('প্রশ্ন তৈরি হচ্ছে...'),
                                  ],
                                )
                              : const Text('প্রশ্ন তৈরি করুন'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: (_hasGeneratedQuestions() && _formKey.currentState?.validate() == true)
                              ? _generatePDF
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('PDF তৈরি করুন'),
                        ),
                      ),
                    ],
                  ),
                  if (_hasGeneratedQuestions()) ...[
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
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
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
                  Text('সৃজনশীল প্রশ্ন:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...List.generate(_creativeSrojonshilQuestions.length, (index) =>
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('${index + 1}. ${_creativeSrojonshilQuestions[index]}'),
                    ),
                  ),
                  SizedBox(height: 16),
                ],
                if (_shortSangkhiptoQuestions.isNotEmpty) ...[
                  Text('সংক্ষিপ্ত প্রশ্ন:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...List.generate(_shortSangkhiptoQuestions.length, (index) =>
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('${index + 1}. ${_shortSangkhiptoQuestions[index]}'),
                    ),
                  ),
                  SizedBox(height: 16),
                ],
                if (_mcqQuestions.isNotEmpty) ...[
                  Text('বহুনির্বাচনি প্রশ্ন:', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 16),
                ],
                if (_shortSangkhiptoQuestions.isNotEmpty) ...[
                  Text('সংক্ষিপ্ত প্রশ্ন:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...List.generate(_shortSangkhiptoQuestions.length, (index) =>
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('${index + 1}. ${_shortSangkhiptoQuestions[index]}'),
                    ),
                  ),
                  SizedBox(height: 16),
                ],
                if (_mcqQuestions.isNotEmpty) ...[
                  Text('বহুনির্বাচনি প্রশ্ন:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...List.generate(_mcqQuestions.length, (index) =>
                    Padding(
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
                                    initialValue: _creativeSrojonshilQuestions[index],
                                    maxLines: 5,
                                    onChanged: (value) {
                                      _creativeSrojonshilQuestions[index] = value;
                                    },
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.delete, color: Colors.red),
                                        onPressed: () {
                                          setState(() {
                                            _creativeSrojonshilQuestions.removeAt(index);
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
                                    initialValue: _shortSangkhiptoQuestions[index],
                                    maxLines: 3,
                                    onChanged: (value) {
                                      _shortSangkhiptoQuestions[index] = value;
                                    },
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.delete, color: Colors.red),
                                        onPressed: () {
                                          setState(() {
                                            _shortSangkhiptoQuestions.removeAt(index);
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
                                        icon: Icon(Icons.delete, color: Colors.red),
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
    _examTimeController.dispose();
    _subjectController.dispose();
    _instituteController.dispose();
    _totalMarksController.dispose();
    _directionsController.dispose();
    super.dispose();
  }
}

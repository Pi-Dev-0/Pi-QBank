import 'package:flutter/material.dart';
import 'delete_confirmation_dialog.dart';

class ViewAndEditQuestionsDialog extends StatefulWidget {
  final List<Map<String, dynamic>> initialQuestions;
  final String selectedLanguage;
  final String selectedTestType;
  final Function(List<Map<String, String>>) onSave;

  const ViewAndEditQuestionsDialog({
    super.key,
    required this.initialQuestions,
    required this.selectedLanguage,
    required this.selectedTestType,
    required this.onSave,
  });

  @override
  State<ViewAndEditQuestionsDialog> createState() =>
      _ViewAndEditQuestionsDialogState();
}

class _ViewAndEditQuestionsDialogState
    extends State<ViewAndEditQuestionsDialog> {
  late List<Map<String, String>> _questions;
  late List<Map<String, String>> _originalQuestions;
  final Set<int> _editableQuestions = {};

  @override
  void initState() {
    super.initState();
    int counter = 0;
    _questions = List.from(widget.initialQuestions.map((q) => {
          'id': '${DateTime.now().millisecondsSinceEpoch}_${counter++}',
          'question': q['question']?.toString() ?? '',
          'answer': q['answer']?.toString() ?? '',
        }));
    // Deeply clone the original questions to separate them from _questions
    _originalQuestions =
        _questions.map((q) => Map<String, String>.from(q)).toList();
  }

  bool _hasChanges() {
    if (_questions.length != _originalQuestions.length) return true;
    for (int i = 0; i < _questions.length; i++) {
      if (_questions[i]['question'] != _originalQuestions[i]['question'] ||
          _questions[i]['answer'] != _originalQuestions[i]['answer']) {
        return true;
      }
    }
    return false;
  }

  Future<void> _handleClose() async {
    if (_hasChanges()) {
      final result = await showDialog<String>(
        context: context,
        builder: (context) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
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
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.save_as_rounded,
                    color: Colors.purple.shade600,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  widget.selectedLanguage == 'বাংলা'
                      ? 'পরিবর্তন সংরক্ষণ করবেন?'
                      : 'Unsaved Changes',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.selectedLanguage == 'বাংলা'
                      ? 'আপনার কিছু পরিবর্তন সংরক্ষিত হয়নি। আপনি কি সেগুলো এখন সংরক্ষণ করতে চান?'
                      : 'You have made changes to the questions. Would you like to save them before leaving?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey.shade600,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                // Action Buttons
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, 'save'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple.shade600,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          widget.selectedLanguage == 'বাংলা'
                              ? 'সংরক্ষণ করুন'
                              : 'Save Changes',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, 'discard'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: BorderSide(color: Colors.red.shade200),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(
                              widget.selectedLanguage == 'বাংলা'
                                  ? 'পরিবর্তন মুছে ফেলুন'
                                  : 'Undo Changes',
                              style: TextStyle(
                                color: Colors.red.shade600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, 'cancel'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: BorderSide(color: Colors.grey.shade500),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(
                              widget.selectedLanguage == 'বাংলা'
                                  ? 'বাতিল'
                                  : 'Cancel',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w600,
                              ),
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
        ),
      );

      if (result == 'save') {
        final saveQuestions = _questions.map((q) {
          final newQ = Map<String, String>.from(q);
          newQ.remove('id');
          return newQ;
        }).toList();
        widget.onSave(saveQuestions);
        if (!mounted) return;
        Navigator.pop(context);
      } else if (result == 'discard') {
        if (!mounted) return;
        Navigator.pop(context);
      }
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        await _handleClose();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 16,
                left: 24,
                right: 24,
                bottom: 24,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.purple.shade600, Colors.deepPurple.shade600],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.edit_note, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.selectedLanguage == 'বাংলা'
                          ? 'প্রশ্ন দেখুন ও সম্পাদনা করুন'
                          : 'View & Edit Questions',
                      style: const TextStyle(
                        fontSize: 20,
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
                    onPressed: _handleClose,
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: _questions.isEmpty
                  ? Center(
                      child: Text(
                        widget.selectedLanguage == 'বাংলা'
                            ? 'কোন প্রশ্ন নেই'
                            : 'No questions available',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: _questions.length,
                      itemBuilder: (context, index) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.grey.shade200,
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
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
                                    horizontal: 20, vertical: 16),
                                decoration: BoxDecoration(
                                  color: Colors.purple.shade50,
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(16),
                                    topRight: Radius.circular(16),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.purple.shade600,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            widget.selectedLanguage == 'বাংলা'
                                                ? 'প্রশ্ন ${index + 1}'
                                                : 'Question ${index + 1}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        IconButton(
                                          icon: Icon(
                                            _editableQuestions.contains(index)
                                                ? Icons.edit_off_outlined
                                                : Icons.edit_outlined,
                                            size: 20,
                                            color: Colors.purple.shade700,
                                          ),
                                          tooltip:
                                              widget.selectedLanguage == 'বাংলা'
                                                  ? (_editableQuestions
                                                          .contains(index)
                                                      ? 'সম্পাদনা বন্ধ করুন'
                                                      : 'সম্পাদনা করুন')
                                                  : (_editableQuestions
                                                          .contains(index)
                                                      ? 'Disable Editing'
                                                      : 'Edit Question'),
                                          onPressed: () {
                                            setState(() {
                                              if (_editableQuestions
                                                  .contains(index)) {
                                                _editableQuestions
                                                    .remove(index);
                                              } else {
                                                _editableQuestions.add(index);
                                              }
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.delete_outline,
                                          color: Colors.red.shade400),
                                      onPressed: () async {
                                        final confirm =
                                            await showDeleteConfirmationDialog(
                                          context: context,
                                          title:
                                              widget.selectedLanguage == 'বাংলা'
                                                  ? 'প্রশ্ন মুছে ফেলবেন?'
                                                  : 'Delete Question?',
                                          message: widget.selectedLanguage ==
                                                  'বাংলা'
                                              ? 'আপনি কি নিশ্চিত যে আপনি এই প্রশ্নটি মুছে ফেলতে চান?'
                                              : 'Are you sure you want to delete this question?',
                                          paperTitle:
                                              widget.selectedLanguage == 'বাংলা'
                                                  ? 'প্রশ্ন ${index + 1}'
                                                  : 'Question ${index + 1}',
                                          paperSubtitle: _questions[index]
                                              ['question'],
                                        );

                                        if (confirm == true) {
                                          setState(() {
                                            _questions.removeAt(index);
                                            _editableQuestions.remove(index);
                                          });
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),

                              // Question and Answer Fields
                              Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  children: [
                                    TextFormField(
                                      key: ValueKey(
                                          'q_${_questions[index]['id']}'),
                                      initialValue: _questions[index]
                                          ['question'],
                                      readOnly:
                                          !_editableQuestions.contains(index),
                                      maxLines: 5,
                                      decoration: InputDecoration(
                                        labelText:
                                            widget.selectedLanguage == 'বাংলা'
                                                ? 'প্রশ্ন'
                                                : 'Question',
                                        labelStyle: TextStyle(
                                          color: Colors.purple.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
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
                                        fillColor:
                                            _editableQuestions.contains(index)
                                                ? Colors.white
                                                : Colors.grey.shade50,
                                        contentPadding:
                                            const EdgeInsets.all(16),
                                      ),
                                      onChanged: (value) {
                                        setState(() {
                                          _questions[index]['question'] = value;
                                        });
                                      },
                                    ),
                                    const SizedBox(height: 16),
                                    TextFormField(
                                      key: ValueKey(
                                          'a_${_questions[index]['id']}'),
                                      initialValue: _questions[index]['answer'],
                                      readOnly:
                                          !_editableQuestions.contains(index),
                                      maxLines: 1,
                                      decoration: InputDecoration(
                                        labelText:
                                            widget.selectedLanguage == 'বাংলা'
                                                ? 'উত্তর'
                                                : 'Answer',
                                        labelStyle: TextStyle(
                                          color: Colors.green.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
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
                                        fillColor:
                                            _editableQuestions.contains(index)
                                                ? Colors.green.shade50
                                                : Colors.green.shade100
                                                    .withOpacity(0.3),
                                        contentPadding:
                                            const EdgeInsets.all(16),
                                      ),
                                      onChanged: (value) {
                                        setState(() {
                                          _questions[index]['answer'] = value;
                                        });
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
          ],
        ),
        floatingActionButton: _hasChanges()
            ? FloatingActionButton.extended(
                onPressed: () {
                  final saveQuestions = _questions.map((q) {
                    final newQ = Map<String, String>.from(q);
                    newQ.remove('id');
                    return newQ;
                  }).toList();
                  widget.onSave(saveQuestions);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(widget.selectedLanguage == 'বাংলা'
                          ? 'পরিবর্তনগুলো সংরক্ষণ করা হয়েছে'
                          : 'Changes saved successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                },
                backgroundColor: Colors.purple.shade600,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.save),
                label: Text(widget.selectedLanguage == 'বাংলা'
                    ? 'সংরক্ষণ করুন'
                    : 'Save Changes'),
              )
            : null,
      ),
    );
  }
}

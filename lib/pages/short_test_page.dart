import 'package:flutter/material.dart';
import 'package:pi_qbank/widgets/custom_app_bar.dart';
import 'dart:async'; // Import for Timer

class ShortTestPage extends StatefulWidget {
  const ShortTestPage({super.key});

  @override
  State<ShortTestPage> createState() => _ShortTestPageState();
}

class _ShortTestPageState extends State<ShortTestPage> {
  String? _selectedTestType;
  int? _numberOfQuestions;
  int? _testTimeInMinutes;
  bool _testStarted = false;
  int _remainingTimeInSeconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showTestConfigDialog();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _showTestConfigDialog() {
    showDialog(
      context: context,
      barrierDismissible: true, // Allow dismissal by tapping outside or back button
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
          title: const Text(
            'Configure Short Test',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      labelText: 'Test Type',
                      prefixIcon: const Icon(Icons.assignment), // Added an icon
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0), // More rounded corners
                        borderSide: BorderSide.none, // No border line
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: BorderSide(color: Colors.grey[300]!, width: 1.0), // Light grey border when enabled
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2.0), // Primary color border when focused
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0), // Adjusted padding
                      filled: true,
                      fillColor: Theme.of(context).inputDecorationTheme.fillColor ?? Colors.grey[100], // Lighter fill color
                    ),
                    value: _selectedTestType,
                    hint: const Text('Select Test Type'), // Moved hint text here
                    items: <String>[
                      'MCQ Test',
                      'Short Question',
                      'Broad Question',
                      'Fill In the Blanks'
                    ].map<DropdownMenuItem<String>>((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 8.0), // Adjusted padding
                          child: Text(
                            value,
                            style: TextStyle(
                              fontSize: 16.0,
                              color: Theme.of(context).textTheme.bodyLarge?.color, // Use theme text color
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedTestType = newValue;
                      });
                    },
                    dropdownColor: Theme.of(context).cardColor, // Background color of the dropdown menu
                    borderRadius: BorderRadius.circular(12.0), // More rounded corners for the dropdown menu
                    elevation: 8, // Added elevation for shadow effect
                    // Removed style property to allow default display of selected item
                    icon: Icon(Icons.arrow_drop_down, color: Theme.of(context).primaryColor), // Custom dropdown icon
                    isExpanded: true, // Make dropdown take full width
                    selectedItemBuilder: (BuildContext context) {
                      return <String>[
                        'MCQ Test',
                        'Short Question',
                        'Broad Question',
                        'Fill In the Blanks'
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
                  TextField(
                    decoration: InputDecoration(
                      labelText: 'Number of Questions',
                      prefixIcon: const Icon(Icons.question_mark), // Added an icon
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0), // More rounded corners
                        borderSide: BorderSide.none, // No border line
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: BorderSide(color: Colors.grey[300]!, width: 1.0), // Light grey border when enabled
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2.0), // Primary color border when focused
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0), // Adjusted padding
                      filled: true,
                      fillColor: Theme.of(context).inputDecorationTheme.fillColor ?? Colors.grey[100], // Lighter fill color
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      _numberOfQuestions = int.tryParse(value);
                    },
                  ),
                  const SizedBox(height: 16.0),
                  TextField(
                    decoration: InputDecoration(
                      labelText: 'Test Time (minutes)',
                      prefixIcon: const Icon(Icons.timer), // Added an icon
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0), // More rounded corners
                        borderSide: BorderSide.none, // No border line
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: BorderSide(color: Colors.grey[300]!, width: 1.0), // Light grey border when enabled
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2.0), // Primary color border when focused
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0), // Adjusted padding
                      filled: true,
                      fillColor: Theme.of(context).inputDecorationTheme.fillColor ?? Colors.grey[100], // Lighter fill color
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      _testTimeInMinutes = int.tryParse(value);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
              onPressed: () {
                if (_selectedTestType != null &&
                    _numberOfQuestions != null &&
                    _testTimeInMinutes != null &&
                    _testTimeInMinutes! > 0) {
                  Navigator.of(context).pop(); // Close the dialog
                  _startTest();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please fill all fields correctly and ensure time is greater than 0.')),
                  );
                }
              },
              child: const Text(
                'Start Test',
                style: TextStyle(fontSize: 16.0),
              ),
            ),
          ],
        );
      },
    );
  }

  void _startTest() {
    setState(() {
      _testStarted = true;
      _remainingTimeInSeconds = _testTimeInMinutes! * 60;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingTimeInSeconds > 0) {
        setState(() {
          _remainingTimeInSeconds--;
        });
      } else {
        timer.cancel();
        _autoSubmitTest();
      }
    });
  }

  void _autoSubmitTest() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Time is up! Test auto-submitted.')),
    );
    // Placeholder for showing results
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Test Completed'),
          content: Text('Your test of type $_selectedTestType with $_numberOfQuestions questions has ended.'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close result dialog
                Navigator.of(context).pop(); // Go back to Tools page
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  String _formatTime(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final remainingSeconds = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remainingSeconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Short Test'),
      body: Column(
        children: [
          if (_testStarted)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                'Time Remaining: ${_formatTime(_remainingTimeInSeconds)}',
                style: TextStyle(
                  fontSize: 24.0,
                  fontWeight: FontWeight.bold,
                  color: _remainingTimeInSeconds < 60 ? Colors.red : Colors.green,
                ),
              ),
            ),
          Expanded(
            child: Center(
              child: _testStarted
                  ? Text(
                      'Test in progress: Type - $_selectedTestType, Questions - $_numberOfQuestions',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18.0),
                    )
                  : const Text(
                      'Short Test Page - Configure test to begin.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18.0),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

class ExamYearSelector extends StatelessWidget {
  final String selectedYear;
  final List<String> examYears;
  final Function(String?) onYearChanged;

  const ExamYearSelector({
    super.key,
    required this.selectedYear,
    required this.examYears,
    required this.onYearChanged,
  });

  void _showYearSelectionDialog(BuildContext context) {
    if (examYears.isEmpty) return;

    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.7;

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
          child: const Center(
            child: Text(
              'Select Year',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
          ),
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            child: ListBody(
              children: [
                // "All Years" option
                GestureDetector(
                  onTap: () {
                    Navigator.of(dialogContext).maybePop();
                    onYearChanged('');
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 14),
                    decoration: BoxDecoration(
                      color: selectedYear.isEmpty
                          ? Colors.blue.shade100
                          : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selectedYear.isEmpty
                            ? Colors.blue
                            : Colors.grey.shade300,
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      'All Years',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: selectedYear.isEmpty
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: selectedYear.isEmpty
                            ? Colors.blue.shade900
                            : Colors.black87,
                      ),
                    ),
                  ),
                ),
                ...examYears.map((year) => GestureDetector(
                      onTap: () {
                        Navigator.of(dialogContext).maybePop();
                        onYearChanged(year);
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 14),
                        decoration: BoxDecoration(
                          color: selectedYear == year
                              ? Colors.blue.shade100
                              : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selectedYear == year
                                ? Colors.blue
                                : Colors.grey.shade300,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          year,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: selectedYear == year
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: selectedYear == year
                                ? Colors.blue.shade900
                                : Colors.black87,
                          ),
                        ),
                      ),
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: MediaQuery.of(context).size.width * 0.7,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha:0.3),
            spreadRadius: 2,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha:0.1),
            spreadRadius: 0,
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _showYearSelectionDialog(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              const Text(
                'Select Year:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black54,
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    selectedYear.isEmpty ? 'All Years' : selectedYear,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
      ),
    );
  }
}

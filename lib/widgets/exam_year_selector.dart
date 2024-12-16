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
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Center(
            child: Text(
              'Select Year',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          content: SizedBox(
            width: double.minPositive,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: examYears.length + 1,
              itemBuilder: (BuildContext context, int index) {
                if (index == 0) {
                  return ListTile(
                    title: const Center(
                      child: Text(
                        'All Years',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                    onTap: () {
                      onYearChanged('');
                      Navigator.pop(context);
                    },
                  );
                }
                final year = examYears[index - 1];
                return ListTile(
                  title: Center(
                    child: Text(
                      year,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  onTap: () {
                    onYearChanged(year);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: MediaQuery.of(context).size.width * 0.6,
      height: 35,
      margin: const EdgeInsets.only(left: 8, right: 8, bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.grey.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
            spreadRadius: 2,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 6),
            spreadRadius: -1,
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _showYearSelectionDialog(context),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Year: ',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black54,
              ),
            ),
            Expanded(
              child: Text(
                selectedYear.isEmpty ? 'All Years' : selectedYear,
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 20),
          ],
        ),
      ),
    );
  }
} 
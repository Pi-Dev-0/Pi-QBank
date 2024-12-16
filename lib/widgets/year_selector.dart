import 'package:flutter/material.dart';

class YearSelector extends StatelessWidget {
  final int selectedYear;
  final Function(int) onYearSelected;

  const YearSelector({
    super.key,
    required this.selectedYear,
    required this.onYearSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: List.generate(4, (index) {
          final year = index + 1;
          final suffix = switch (year) {
            1 => 'st',
            2 => 'nd',
            3 => 'rd',
            _ => 'th',
          };
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: selectedYear == year
                      ? Theme.of(context).colorScheme.primary
                      : Colors.white,
                  foregroundColor:
                      selectedYear == year ? Colors.white : Colors.black87,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  elevation: 8,
                  shadowColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => onYearSelected(year),
                child: Text(
                  '$year$suffix Year',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

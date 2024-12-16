import 'package:flutter/material.dart';

class GroupSelector extends StatelessWidget {
  const GroupSelector({
    super.key,
    required this.selectedGroup,
    required this.groups,
    required this.onGroupChanged,
  });

  final String selectedGroup;
  final List<String> groups;
  final Function(String?) onGroupChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: groups.map((group) {
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: selectedGroup == group
                      ? Theme.of(context).colorScheme.primary
                      : Colors.white,
                  foregroundColor:
                      selectedGroup == group ? Colors.white : Colors.black87,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  elevation: 8,
                  shadowColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => onGroupChanged(group),
                child: Text(
                  group,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
} 
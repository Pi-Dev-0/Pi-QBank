import 'package:flutter/material.dart';

class ToolItem {
  final IconData icon;
  final String title;
  final String description;
  final Color accentColor;
  final VoidCallback onTap;
  bool isPinned;

  ToolItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.accentColor,
    required this.onTap,
    this.isPinned = false,
  });

  // Convert ToolItem to JSON for shared_preferences
  Map<String, dynamic> toJson() => {
        'title': title,
        'isPinned': isPinned,
      };

  // Create ToolItem from JSON (only for loading pinned state)
  factory ToolItem.fromJson(Map<String, dynamic> json) {
    return ToolItem(
      icon: Icons.error, // Placeholder, actual icon will be set in ToolsPage
      title: json['title'],
      description: '', // Placeholder
      accentColor: Colors.grey, // Placeholder
      onTap: () {}, // Placeholder
      isPinned: json['isPinned'] ?? false,
    );
  }
}

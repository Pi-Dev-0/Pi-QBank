import 'package:flutter/material.dart';
import 'ai_page.dart';

/// Built-in Pi AI chat page.
class AiHubPage extends StatelessWidget {
  const AiHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: AIPage(),
    );
  }
}

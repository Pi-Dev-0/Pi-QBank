import 'package:flutter/material.dart';
import '../widgets/app_drawer.dart';
import '../widgets/custom_app_bar.dart';
// Import the new QuestionBankContent

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isAndroid = Theme.of(context).platform == TargetPlatform.android;

    // Keep Android layout completely unmodified
    if (isAndroid) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: const CustomAppBar(title: 'Pi-Mathematics'),
        drawer: const AppDrawer(),
        body: GridView.count(
          padding: const EdgeInsets.all(16),
          crossAxisCount: 2,
          childAspectRatio: 0.9,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          children: _buildMenuItems(context),
        ),
      );
    }

    // Adaptive layout for Linux desktop / non-Android platforms using MediaQuery
    final double screenWidth = MediaQuery.of(context).size.width;

    final int crossAxisCount;
    final double childAspectRatio;
    final double horizontalPadding;
    final double spacing;

    if (screenWidth < 600) {
      crossAxisCount = 2;
      childAspectRatio = 0.9;
      horizontalPadding = 16.0;
      spacing = 10.0;
    } else if (screenWidth < 900) {
      crossAxisCount = 3;
      childAspectRatio = 1.05;
      horizontalPadding = 24.0;
      spacing = 16.0;
    } else if (screenWidth < 1200) {
      crossAxisCount = 3;
      childAspectRatio = 1.2;
      horizontalPadding = 32.0;
      spacing = 20.0;
    } else {
      crossAxisCount = 3;
      childAspectRatio = 1.25;
      horizontalPadding = 40.0;
      spacing = 24.0;
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const CustomAppBar(title: 'Pi-Mathematics'),
      drawer: const AppDrawer(),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: GridView.count(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: 24.0,
            ),
            crossAxisCount: crossAxisCount,
            childAspectRatio: childAspectRatio,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            children: _buildMenuItems(context),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMenuItems(BuildContext context) {
    return [
      _buildMainMenuItem(
        context,
        'Question Bank',
        'Practice with a vast collection of questions',
        Icons.question_answer,
        Colors.blue,
        '/question_bank_content',
      ),
      _buildMainMenuItem(
        context,
        'Books',
        'Access a library of educational books',
        Icons.menu_book,
        Colors.green,
        '/books',
      ),
      _buildMainMenuItem(
        context,
        'Guides & Solutions',
        'Find detailed guides and solutions',
        Icons.lightbulb,
        Colors.orange,
        '/guide_book',
      ),
      _buildMainMenuItem(
        context,
        'Hand & Digital Notes',
        'Review concise and helpful hand & digital notes',
        Icons.note,
        Colors.purple,
        '/hand_notes',
      ),
      _buildMainMenuItem(
        context,
        'Formula',
        'Browse essential formulas for various subjects',
        Icons.functions,
        Colors.red,
        '/formula',
      ),
      _buildMainMenuItem(
        context,
        'Suggestions',
        'Get tips and suggestions for better learning',
        Icons.tips_and_updates,
        Colors.teal,
        '/suggestions',
      ),
    ];
  }

  Widget _buildMainMenuItem(BuildContext context, String title,
      String description, IconData icon, Color accentColor, String route) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () {
            Navigator.pushNamed(context, route);
          },
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.max,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 24, color: accentColor),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 4),
                Flexible(
                  child: Text(
                    description,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Explore',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: accentColor,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.arrow_forward, size: 10, color: accentColor),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

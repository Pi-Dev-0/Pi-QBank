import 'package:flutter/material.dart';
import 'dart:ui'; // Import for ImageFilter
import 'dart:math'; // Import for Random
import '../constants/app_colors.dart';
import 'notification_icon.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool centerTitle;
  final List<Widget>? actions;

  const CustomAppBar({
    super.key,
    required this.title,
    this.centerTitle = true,
    this.actions,
  });

  // Define a list of beautiful colors from AppColors
  static const List<Color> _beautifulColors = [
    AppColors.deepPurple,
    AppColors.tealAccent,
    AppColors.coralSunset,
    AppColors.forestGreen,
    AppColors.vibrantIndigo,
    AppColors.royalBlue,
    AppColors.amethyst,
    AppColors.turquoise,
    AppColors.richCrimson,
    AppColors.goldenrodYellow,
    AppColors.deepSeaTeal,
    AppColors.roseQuartz,
  ];

  // Create a single Random instance
  static final Random _random = Random();

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    final double appBarHeight = isLandscape ? 45 : kToolbarHeight;

    // Select a random color from the predefined list
    final Color selectedColor = _beautifulColors[_random.nextInt(_beautifulColors.length)];

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        bottom: Radius.circular(30), // Increased radius for stylish look
      ),
      child: BackdropFilter(
        filter:
            ImageFilter.blur(sigmaX: 10, sigmaY: 10), // Frosted glass effect
        child: Container(
          height: appBarHeight +
              MediaQuery.of(context).padding.top, // Account for status bar
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15), // Subtle transparent background
          ),
          child: AppBar(
            title: Text(
              title,
              style: TextStyle(
                color: selectedColor, // Use the selected random color
                shadows: [
                  Shadow(
                    color: selectedColor
                        .withOpacity(0.5), // Shadow color, slightly transparent
                    offset: const Offset(0, 1), // X, Y offset
                    blurRadius: 8, // Blur radius
                  ),
                ],
              ),
            ),
            backgroundColor:
                Colors.transparent, // Make AppBar background transparent //blur this background
            shadowColor: Colors.white.withOpacity(0.01), // Remove default shadow color
            elevation: 0, // Remove default shadow
            centerTitle: centerTitle,
            actions: [
              NotificationIcon(
                  iconColor: selectedColor), // Pass the selected random color to NotificationIcon
              ...(actions ?? []),
            ],
            toolbarHeight: appBarHeight,
            iconTheme: IconThemeData(
                color:
                    selectedColor), // Ensure icons match selected random title color
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize {
    // ignore: deprecated_member_use
    final isLandscape = WidgetsBinding.instance.window.physicalSize.width >
        // ignore: deprecated_member_use
        WidgetsBinding.instance.window.physicalSize.height;
    return Size.fromHeight(isLandscape ? 45 : kToolbarHeight);
  }
}

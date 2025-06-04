import 'package:flutter/material.dart';
import 'dart:ui'; // Import for ImageFilter
import 'dart:math'; // Import for Random color generation
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

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    final double appBarHeight = isLandscape ? 45 : kToolbarHeight;
    final Color randomTitleColor = Color((Random().nextDouble() * 0xFFFFFF).toInt()).withOpacity(1.0); // Generate random color once

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        bottom: Radius.circular(30), // Increased radius for stylish look
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20), // Frosted glass effect
        child: Container(
          height: appBarHeight + MediaQuery.of(context).padding.top, // Account for status bar
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15), // Subtle transparent background
          ),
          child: AppBar(
            title: Text(
              title,
              style: TextStyle(
                color: randomTitleColor, // Use the stored random color
              ),
            ),
            backgroundColor: Colors.transparent, // Make AppBar background transparent
            elevation: 0, // Remove default shadow
            centerTitle: centerTitle,
            actions: [
              NotificationIcon(iconColor: randomTitleColor), // Pass the random color to NotificationIcon
              ...(actions ?? []),
            ],
            toolbarHeight: appBarHeight,
            iconTheme: IconThemeData(color: randomTitleColor), // Ensure icons match random title color
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

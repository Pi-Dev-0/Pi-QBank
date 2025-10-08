import 'package:flutter/material.dart';
import 'dart:ui'; // Import for ImageFilter
import 'dart:math'; // Import for Random
import '../constants/app_colors.dart';
import 'notification_icon.dart';

class CustomAppBar extends StatefulWidget implements PreferredSizeWidget {
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
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  State<CustomAppBar> createState() => _CustomAppBarState();
}

class _CustomAppBarState extends State<CustomAppBar> {
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

  static final Random _random = Random();
  late final Color selectedColor;

  @override
  void initState() {
    super.initState();
    selectedColor = _beautifulColors[_random.nextInt(_beautifulColors.length)];
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final double appBarHeight = isLandscape ? 45 : kToolbarHeight;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        bottom: Radius.circular(30),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: appBarHeight + MediaQuery.of(context).padding.top,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha:0.15),
          ),
          child: AppBar(
            title: Text(
              widget.title,
              style: TextStyle(
                color: selectedColor,
                shadows: [
                  Shadow(
                    color: selectedColor.withValues(alpha:0.5),
                    offset: const Offset(0, 1),
                    blurRadius: 30,
                  ),
                ],
              ),
            ),
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            elevation: 0,
            centerTitle: widget.centerTitle,
            actions: [
              NotificationIcon(iconColor: selectedColor),
              ...(widget.actions ?? []),
            ],
            toolbarHeight: appBarHeight,
            iconTheme: IconThemeData(color: selectedColor),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
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
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return AppBar(
      title: Text(title),
      backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      centerTitle: centerTitle,
      actions: [
        NotificationIcon(),
        ...(actions ?? []),
      ],
      toolbarHeight: isLandscape ? 45 : kToolbarHeight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(12),
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
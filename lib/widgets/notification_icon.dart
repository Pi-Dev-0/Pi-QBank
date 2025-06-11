import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/notification_service.dart';

class NotificationIcon extends StatefulWidget {
  final Color? iconColor; // New parameter for icon color
  const NotificationIcon({super.key, this.iconColor});

  @override
  State<NotificationIcon> createState() => _NotificationIconState();
}

class _NotificationIconState extends State<NotificationIcon>
    with TickerProviderStateMixin {
  bool _hasUnseenNotifications = false;
  List<AppNotification> _notifications = [];
  late AnimationController _pulseController;
  late AnimationController _scaleController;
  late AnimationController _rainbowController;
  late AnimationController _glowController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rainbowAnimation;
  late Animation<double> _glowAnimation;

  // Beautiful color palettes
  final List<List<Color>> _notificationGradients = [
    [const Color(0xFF667eea), const Color(0xFF764ba2)], // Purple-Blue
    [const Color(0xFFf093fb), const Color(0xFFf5576c)], // Pink-Red
    [const Color(0xFF4facfe), const Color(0xFF00f2fe)], // Blue-Cyan
    [const Color(0xFF43e97b), const Color(0xFF38f9d7)], // Green-Mint
    [const Color(0xFFfa709a), const Color(0xFFfee140)], // Pink-Yellow
    [const Color(0xFF6a11cb), const Color(0xFF2575fc)], // Purple-Blue
    [const Color(0xFFff9472), const Color(0xFFf2709c)], // Orange-Pink
    [const Color(0xFF00c6ff), const Color(0xFF0072ff)], // Light-Blue-Blue
  ];

  final List<Color> _iconColors = [
    const Color(0xFF667eea),
    const Color(0xFFf093fb),
    const Color(0xFF43e97b),
    const Color(0xFFfa709a),
    const Color(0xFF4facfe),
    const Color(0xFF6a11cb),
    const Color(0xFFff9472),
    const Color(0xFF00c6ff),
  ];

  @override
  void initState() {
    super.initState();

    // Pulse animation for notification badge
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(
      begin: 0.7,
      end: 1.0, // Make the final pulse icon scale a little smaller
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    // Scale animation for button press
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeInOut,
    ));

    // Rainbow animation for dialog
    _rainbowController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );
    _rainbowAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_rainbowController);

    // Glow animation
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _glowAnimation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _glowController,
      curve: Curves.easeInOut,
    ));

    _pulseController.repeat(reverse: true);
    _rainbowController.repeat();
    _glowController.repeat(reverse: true);
    _initializeNotifications();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scaleController.dispose();
    _rainbowController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  Future<void> _initializeNotifications() async {
    try {
      final notifications = await NotificationService.fetchNotifications();
      final hasUnseen = await NotificationService.hasUnseenNotifications();
      if (mounted) {
        setState(() {
          _notifications = notifications;
          _hasUnseenNotifications = hasUnseen;
        });
      }
    } catch (e) {
      debugPrint('Error initializing notifications: $e');
    }
  }

  Color _getNotificationColor(int index) {
    return _iconColors[index % _iconColors.length];
  }

  List<Color> _getNotificationGradient(int index) {
    return _notificationGradients[index % _notificationGradients.length];
  }

  Widget _buildRichText(String text) {
    final urlRegExp = RegExp(
      r'https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)',
      caseSensitive: false,
    );

    List<TextSpan> textSpans = [];
    int lastMatchEnd = 0;

    for (var match in urlRegExp.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        textSpans.add(TextSpan(
          text: text.substring(lastMatchEnd, match.start),
          style: const TextStyle(
            color: Color(0xFF2D3748),
            height: 1.5,
            fontSize: 14,
          ),
        ));
      }

      final url = text.substring(match.start, match.end);
      textSpans.add(
        TextSpan(
          text: url,
          style: TextStyle(
            background: Paint()
              ..color = const Color(0xFF667eea).withOpacity(0.1),
            color: Color(0xFF667eea),
            fontWeight: FontWeight.w600,
            height: 1.5,
            fontSize: 14,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              final Uri uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
            },
        ),
      );

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      textSpans.add(TextSpan(
        text: text.substring(lastMatchEnd),
        style: const TextStyle(
          color: Color(0xFF2D3748),
          height: 1.5,
          fontSize: 14,
        ),
      ));
    }

    return SelectableText.rich(
      TextSpan(children: textSpans),
    );
  }

  void _showNotificationsDialog(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black.withOpacity(0.6),
      transitionDuration: Duration.zero,
      transitionBuilder: (context, a1, a2, widget) {
        return widget;
      },
      pageBuilder: (context, animation1, animation2) {
        return AnimatedBuilder(
          animation: _rainbowAnimation,
          builder: (context, child) {
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 40),
              child: AlertDialog(
                backgroundColor: Colors.transparent,
                elevation: 0,
                contentPadding: EdgeInsets.zero,
                content: Container(
                  width: MediaQuery.of(context).size.width,
                  height: MediaQuery.of(context).size.height * 0.75,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white,
                        const Color(0xFFF7FAFC),
                        Colors.white,
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      width: 2,
                      color: Colors.white.withOpacity(0.8),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF667eea).withOpacity(0.15),
                        blurRadius: 40,
                        offset: const Offset(0, 20),
                        spreadRadius: 0,
                      ),
                      BoxShadow(
                        color: const Color(0xFFfa709a).withOpacity(0.1),
                        blurRadius: 60,
                        offset: const Offset(-20, -20),
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Animated Header
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              const Color(0xFF667eea).withOpacity(0.1),
                              const Color(0xFFfa709a).withOpacity(0.05),
                            ],
                          ),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(26),
                            topRight: Radius.circular(26),
                          ),
                        ),
                        child: Row(
                          children: [
                            AnimatedBuilder(
                              animation: _glowAnimation,
                              builder: (context, child) {
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        const Color(0xFF667eea)
                                            .withOpacity(_glowAnimation.value),
                                        const Color(0xFFfa709a).withOpacity(
                                            _glowAnimation.value * 0.7),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF667eea)
                                            .withOpacity(
                                                _glowAnimation.value * 0.4),
                                        blurRadius: 20,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.notifications_active_rounded,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Notifications',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 24,
                                      color: Color(0xFF2D3748),
                                    ),
                                  ),
                                  Text(
                                    'All your updates here',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_notifications.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF43e97b),
                                      Color(0xFF38f9d7)
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF43e97b)
                                          .withOpacity(0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  '${_notifications.length}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      // Content Area
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                          child: StatefulBuilder(
                            builder: (context, setDialogState) => _notifications
                                    .isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        AnimatedBuilder(
                                          animation: _glowAnimation,
                                          builder: (context, child) {
                                            return Container(
                                              padding: const EdgeInsets.all(24),
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: [
                                                    const Color(0xFF667eea)
                                                        .withOpacity(0.1 *
                                                            _glowAnimation
                                                                .value),
                                                    const Color(0xFFfa709a)
                                                        .withOpacity(0.05 *
                                                            _glowAnimation
                                                                .value),
                                                  ],
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(24),
                                              ),
                                              child: Icon(
                                                Icons
                                                    .notifications_none_rounded,
                                                size: 80,
                                                color: const Color(0xFF667eea)
                                                    .withOpacity(0.6),
                                              ),
                                            );
                                          },
                                        ),
                                        const SizedBox(height: 24),
                                        const Text(
                                          'All caught up! 🎉',
                                          style: TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF2D3748),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'No new notifications right now.\nWe\'ll let you know when something exciting happens!',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 16,
                                            color: Colors.grey[600],
                                            height: 1.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: _notifications.length,
                                    separatorBuilder: (context, index) =>
                                        const SizedBox(height: 16),
                                    itemBuilder: (context, index) {
                                      final notification =
                                          _notifications[index];
                                      final isSeen = !NotificationService
                                          .isNotificationUnseen(notification);
                                      final gradient =
                                          _getNotificationGradient(index);
                                      final iconColor =
                                          _getNotificationColor(index);

                                      return AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 300),
                                        decoration: BoxDecoration(
                                          gradient: isSeen
                                              ? LinearGradient(
                                                  colors: [
                                                    Colors.white,
                                                    const Color(0xFFF7FAFC)
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                )
                                              : LinearGradient(
                                                  colors: [
                                                    gradient[0]
                                                        .withOpacity(0.05),
                                                    gradient[1]
                                                        .withOpacity(0.02),
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          border: Border.all(
                                            color: isSeen
                                                ? Colors.grey[200]!
                                                : gradient[0].withOpacity(0.3),
                                            width: 2,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: isSeen
                                                  ? Colors.grey.withOpacity(0.1)
                                                  : gradient[0]
                                                      .withOpacity(0.15),
                                              blurRadius: 15,
                                              offset: const Offset(0, 8),
                                            ),
                                          ],
                                        ),
                                        child: Theme(
                                          data: Theme.of(context).copyWith(
                                            dividerColor: Colors.transparent,
                                            splashColor: Colors.transparent,
                                            highlightColor: Colors.transparent,
                                          ),
                                          child: ExpansionTile(
                                            tilePadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 20,
                                                    vertical: 12),
                                            expandedAlignment:
                                                Alignment.topLeft,
                                            childrenPadding:
                                                const EdgeInsets.fromLTRB(
                                                    20, 0, 20, 20),
                                            leading: AnimatedContainer(
                                              duration: const Duration(
                                                  milliseconds: 300),
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                gradient: isSeen
                                                    ? LinearGradient(colors: [
                                                        Colors.grey[300]!,
                                                        Colors.grey[200]!
                                                      ])
                                                    : LinearGradient(
                                                        colors: gradient),
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: (isSeen
                                                            ? Colors.grey[400]!
                                                            : iconColor)
                                                        .withOpacity(0.3),
                                                    blurRadius: 8,
                                                    offset: const Offset(0, 4),
                                                  ),
                                                ],
                                              ),
                                              child: Icon(
                                                Icons.campaign_rounded,
                                                color: Colors.white,
                                                size: 22,
                                              ),
                                            ),
                                            title: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    notification.title,
                                                    style: TextStyle(
                                                      fontWeight: isSeen
                                                          ? FontWeight.w600
                                                          : FontWeight.bold,
                                                      fontSize: 17,
                                                      color: const Color(
                                                          0xFF2D3748),
                                                    ),
                                                  ),
                                                ),
                                                if (!isSeen)
                                                  AnimatedBuilder(
                                                    animation: _pulseAnimation,
                                                    builder: (context, child) {
                                                      return Transform.scale(
                                                        scale: _pulseAnimation
                                                                    .value *
                                                                0.5 +
                                                            0.5,
                                                        child: Container(
                                                          width: 10,
                                                          height: 10,
                                                          decoration:
                                                              BoxDecoration(
                                                            gradient:
                                                                LinearGradient(
                                                                    colors:
                                                                        gradient),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        5),
                                                            boxShadow: [
                                                              BoxShadow(
                                                                color: iconColor
                                                                    .withOpacity(
                                                                        0.6),
                                                                blurRadius: 8,
                                                                spreadRadius: 1,
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                  ),
                                              ],
                                            ),
                                            subtitle: Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 6),
                                              child: Text(
                                                notification.subtitle,
                                                style: TextStyle(
                                                  color: isSeen
                                                      ? Colors.grey[600]
                                                      : iconColor,
                                                  fontWeight: isSeen
                                                      ? FontWeight.w500
                                                      : FontWeight.w600,
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ),
                                            children: [
                                              Container(
                                                width: double.infinity,
                                                padding:
                                                    const EdgeInsets.all(20),
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    colors: [
                                                      const Color(0xFFF7FAFC),
                                                      Colors.white,
                                                    ],
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                  border: Border.all(
                                                    color: gradient[0]
                                                        .withOpacity(0.1),
                                                    width: 1,
                                                  ),
                                                ),
                                                child: _buildRichText(
                                                    notification.description),
                                              ),
                                            ],
                                            onExpansionChanged:
                                                (expanded) async {
                                              if (expanded &&
                                                  NotificationService
                                                      .isNotificationUnseen(
                                                          notification)) {
                                                await NotificationService
                                                    .markNotificationAsSeen(
                                                        notification);
                                                final hasUnseen =
                                                    await NotificationService
                                                        .hasUnseenNotifications();
                                                if (mounted) {
                                                  setState(() {
                                                    _hasUnseenNotifications =
                                                        hasUnseen;
                                                  });
                                                  setDialogState(() {});
                                                }
                                              }
                                            },
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ),
                      ),

                      // Footer with gradient button
                      Container(
                        padding: const EdgeInsets.all(24),
                        child: AnimatedBuilder(
                          animation: _glowAnimation,
                          builder: (context, child) {
                            return Container(
                              width: double.infinity,
                              height: 56,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(0xFF667eea).withOpacity(
                                        0.8 + _glowAnimation.value * 0.2),
                                    const Color(0xFFfa709a).withOpacity(
                                        0.8 + _glowAnimation.value * 0.2),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF667eea).withOpacity(
                                        0.4 * _glowAnimation.value),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed: () => Navigator.of(context).pop(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: const Text(
                                  'Close',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _scaleController.forward(),
      onTapUp: (_) => _scaleController.reverse(),
      onTapCancel: () => _scaleController.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: AnimatedBuilder(
                animation: _glowAnimation,
                builder: (context, child) {
                  return Icon(
                    Icons.notifications_rounded,
                    size: 28,
                    color: widget.iconColor ?? (_hasUnseenNotifications
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.7 + _glowAnimation.value * 0.3)),
                  );
                },
              ),
              onPressed: () => _showNotificationsDialog(context),
              tooltip: 'Notifications',
              splashRadius: 24,
            ),
            if (_hasUnseenNotifications)
              Positioned(
                right: 10,
                top: 10,
                child: AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _pulseAnimation.value,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: widget.iconColor ?? Theme.of(context).colorScheme.primary, // Use passed color or fallback
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.white,
                            width: 1,
                          ),
                          // Removed boxShadow
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

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

class _NotificationIconState extends State<NotificationIcon> {
  bool _hasUnseenNotifications = false;
  List<AppNotification> _notifications = [];

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
  }

  @override
  void dispose() {
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
              ..color = const Color(0xFF667eea).withValues(alpha:0.1),
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
      barrierColor: Colors.black.withValues(alpha:0.6),
      transitionDuration: Duration.zero,
      transitionBuilder: (context, a1, a2, widget) {
        return widget;
      },
      pageBuilder: (context, animation1, animation2) {
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
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  width: 2,
                  color: Colors.white.withValues(alpha:0.8),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withValues(alpha:0.15),
                    blurRadius: 40,
                    offset: const Offset(0, 20),
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(26),
                        topRight: Radius.circular(26),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.notifications_active_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
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
                              color: Theme.of(context).colorScheme.secondary,
                              borderRadius: BorderRadius.circular(20),
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
                                    Container(
                                      padding: const EdgeInsets.all(24),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[100],
                                        borderRadius:
                                            BorderRadius.circular(24),
                                      ),
                                      child: Icon(
                                        Icons.notifications_none_rounded,
                                        size: 80,
                                        color: Colors.grey[400],
                                      ),
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

                                  return Container(
                                    decoration: BoxDecoration(
                                      color: isSeen
                                          ? Colors.white
                                          : Theme.of(context).colorScheme.primary.withValues(alpha:0.05),
                                      borderRadius:
                                          BorderRadius.circular(20),
                                      border: Border.all(
                                        color: isSeen
                                            ? Colors.grey[200]!
                                            : Theme.of(context).colorScheme.primary.withValues(alpha:0.3),
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: isSeen
                                              ? Colors.grey.withValues(alpha:0.1)
                                              : Theme.of(context).colorScheme.primary.withValues(alpha:0.15),
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
                                        leading: Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: isSeen
                                                ? Colors.grey[300]!
                                                : Theme.of(context).colorScheme.primary,
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            boxShadow: [
                                              BoxShadow(
                                                color: (isSeen
                                                        ? Colors.grey[400]!
                                                        : Theme.of(context).colorScheme.primary)
                                                    .withValues(alpha:0.3),
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
                                              Container(
                                                width: 10,
                                                height: 10,
                                                decoration:
                                                    BoxDecoration(
                                                  color: Theme.of(context).colorScheme.primary,
                                                  borderRadius:
                                                      BorderRadius
                                                          .circular(
                                                              5),
                                                ),
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
                                                  : Theme.of(context).colorScheme.primary,
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
                                              color: const Color(0xFFF7FAFC),
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              border: Border.all(
                                                color: Theme.of(context).colorScheme.primary.withValues(alpha:0.1),
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

                  // Footer with button
                  Container(
                    padding: const EdgeInsets.all(24),
                    child: Container(
                      width: double.infinity,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha:0.4),
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
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showNotificationsDialog(context),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            icon: Icon(
              Icons.notifications_rounded,
              size: 28,
              color: widget.iconColor ?? (_hasUnseenNotifications
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurface.withValues(alpha:0.7)),
            ),
            onPressed: () => _showNotificationsDialog(context),
            tooltip: 'Notifications',
            splashRadius: 24,
          ),
          if (_hasUnseenNotifications)
            Positioned(
              right: 10,
              top: 10,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: widget.iconColor ?? Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white,
                    width: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

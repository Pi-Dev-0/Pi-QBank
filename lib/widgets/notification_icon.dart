import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/notification_service.dart';

class NotificationIcon extends StatefulWidget {
  const NotificationIcon({super.key});

  @override
  State<NotificationIcon> createState() => _NotificationIconState();
}

class _NotificationIconState extends State<NotificationIcon>
    with SingleTickerProviderStateMixin {
  bool _hasUnseenNotifications = false;
  List<AppNotification> _notifications = [];
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    // Initialize animation controller
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    // Create a blinking animation
    _animation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    // Make the animation repeat
    _animationController.repeat(reverse: true);

    _initializeNotifications();
  }

  @override
  void dispose() {
    _animationController.dispose();
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
        ));
      }

      final url = text.substring(match.start, match.end);
      textSpans.add(
        TextSpan(
          text: url,
          style: const TextStyle(
            color: Colors.blue,
            // Removed the underline decoration
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
      ));
    }

    return SelectableText.rich(TextSpan(children: textSpans));
  }

  void _showNotificationsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Center(child: Text('Notifications', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary))),
        content: SizedBox(
          width: double.maxFinite,
          child: StatefulBuilder(
            builder: (context, setDialogState) => _notifications.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        'No notifications available',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _notifications.length,
                    itemBuilder: (context, index) {
                      final notification = _notifications[index];
                      final isSeen = !NotificationService.isNotificationUnseen(
                          notification);

                      return Theme(
                        data: Theme.of(context)
                            .copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 6),
                          expandedAlignment: Alignment.topLeft,
                          title: Text(
                            notification.title,
                            style: TextStyle(
                              fontWeight:
                                  isSeen ? FontWeight.normal : FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          subtitle: Text(
                            notification.subtitle,
                            style: TextStyle(
                              color: isSeen ? Colors.black87 : Colors.blue[700],
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                          children: [
                            Container(
                              alignment: Alignment.center,
                              margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.grey[400]!,
                                  width: 1,
                                ),
                              ),
                              child: _buildRichText(notification.description),
                            ),
                          ],
                          onExpansionChanged: (expanded) async {
                            if (expanded &&
                                NotificationService.isNotificationUnseen(
                                    notification)) {
                              await NotificationService.markNotificationAsSeen(
                                  notification);
                              final hasUnseen = await NotificationService
                                  .hasUnseenNotifications();
                              if (mounted) {
                                setState(() {
                                  _hasUnseenNotifications = hasUnseen;
                                });
                                setDialogState(() {});
                              }
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
        ),
        actions: [
          Center(
            child: TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              style: TextButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text(
                'Close',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IconButton(
          icon: const Icon(Icons.notifications),
          onPressed: () => _showNotificationsDialog(context),
        ),
        if (_hasUnseenNotifications)
          Positioned(
            right: 10,
            top: 10,
            child: FadeTransition(
              opacity: _animation,
              child: Container(
                padding: const EdgeInsets.all(1),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
                constraints: const BoxConstraints(
                  minWidth: 8,
                  minHeight: 8,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

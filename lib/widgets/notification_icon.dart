import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
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

  void _showNotificationsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Center(child: Text('Notifications')),
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
                      final isSeen = !NotificationService.isNotificationUnseen(notification);

                      return Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                          expandedAlignment: Alignment.topLeft,
                          trailing: Text(
                            timeago.format(notification.timestamp),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.grey,
                                ),
                          ),
                          title: Text(
                            notification.title,
                            style: TextStyle(
                              fontWeight: isSeen ? FontWeight.normal : FontWeight.bold,
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
                              child: Text(
                                notification.description,
                                style: const TextStyle(
                                  color: Colors.black87,
                                  fontSize: 14,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                          onExpansionChanged: (expanded) async {
                            if (expanded && NotificationService.isNotificationUnseen(notification)) {
                              await NotificationService.markNotificationAsSeen(notification);
                              final hasUnseen = await NotificationService.hasUnseenNotifications();
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
          TextButton(
            onPressed: () async {
              // Capture the context before async operation
              final localContext = context;
              
              await NotificationService.markAllAsSeen();
              await NotificationService.hasUnseenNotifications(); // Update the unseen status
              
              // Check mounted before updating UI
              if (mounted) {
                setState(() {
                  _hasUnseenNotifications = false;
                });
                
                // Additional mounted check before using context
                if (mounted && context.mounted && Navigator.of(localContext).canPop()) {
                  Navigator.of(localContext).pop();
                }
              }
            },
            child: const Text('Mark All as Read'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Close'),
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

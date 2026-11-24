import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/notification_service.dart';

/// Bell icon shown in app bars.
///
/// The badge shows the number of unread notifications and stays in sync with
/// every other [NotificationIcon] in the app. Tapping the bell opens a sheet
/// where notifications can be read, filtered, refreshed, and marked as read.
class NotificationIcon extends StatefulWidget {
  final Color? iconColor;

  const NotificationIcon({super.key, this.iconColor});

  @override
  State<NotificationIcon> createState() => _NotificationIconState();
}

class _NotificationIconState extends State<NotificationIcon> {
  @override
  void initState() {
    super.initState();
    _initializeNotifications();
  }

  Future<void> _initializeNotifications() async {
    try {
      await NotificationService.fetchNotifications();
    } catch (e) {
      debugPrint('Error initializing notifications: $e');
    }
  }

  Future<void> _openNotifications() async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withOpacity(0.55),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) {
        return const _NotificationsDialog();
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curvedAnimation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curvedAnimation),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ValueListenableBuilder<int>(
      valueListenable: NotificationService.unreadCountListenable,
      builder: (context, unreadCount, child) {
        final hasUnread = unreadCount > 0;
        final color = widget.iconColor ??
            (hasUnread
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withOpacity(0.7));

        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              onPressed: _openNotifications,
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  hasUnread
                      ? Icons.notifications_rounded
                      : Icons.notifications_none_rounded,
                  key: ValueKey<bool>(hasUnread),
                  size: 27,
                  color: color,
                ),
              ),
              tooltip: hasUnread
                  ? '$unreadCount unread notification${unreadCount == 1 ? '' : 's'}'
                  : 'Notifications',
              splashRadius: 22,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
            Positioned(
              top: 5,
              right: 2,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, animation) {
                  return ScaleTransition(scale: animation, child: child);
                },
                child: hasUnread
                    ? _UnreadBadge(
                        key: const ValueKey<String>('unread-badge'),
                        count: unreadCount,
                      )
                    : const SizedBox.shrink(
                        key: ValueKey<String>('no-unread-badge'),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  final int count;

  const _UnreadBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    final badgeColor = Theme.of(context).colorScheme.error;
    final label = count > 9 ? '9+' : '$count';

    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: badgeColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: badgeColor.withOpacity(0.35),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }
}

enum _NotificationFilter { all, unread }

class _NotificationsDialog extends StatefulWidget {
  const _NotificationsDialog();

  @override
  State<_NotificationsDialog> createState() => _NotificationsDialogState();
}

class _NotificationsDialogState extends State<_NotificationsDialog> {
  _NotificationFilter _filter = _NotificationFilter.all;
  final Set<String> _expandedIds = <String>{};

  bool _isLoading = false;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _isLoading = NotificationService.notificationsListenable.value.isEmpty;

    // Show cached notifications immediately, then quietly check for updates.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh(silent: true);
    });
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent) {
      setState(() => _isRefreshing = true);
    }

    try {
      await NotificationService.fetchNotifications(forceRefresh: true);
    } catch (e) {
      debugPrint('Notification refresh failed: $e');
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't refresh notifications. Please try again."),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _markAllAsSeen() async {
    if (NotificationService.unreadCount == 0) return;
    await NotificationService.markAllAsSeen();
  }

  Future<void> _toggleNotification(AppNotification notification) async {
    final isExpanded = _expandedIds.contains(notification.id);

    setState(() {
      if (isExpanded) {
        _expandedIds.remove(notification.id);
      } else {
        _expandedIds.add(notification.id);
      }
    });

    // Opening an unread notification is what "reads" it.
    if (!isExpanded && !notification.seen) {
      // Do not make the card disappear from under the user's finger when the
      // "Unread" filter is active.
      if (_filter == _NotificationFilter.unread) {
        setState(() => _filter = _NotificationFilter.all);
      }
      await NotificationService.markNotificationAsSeen(notification);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final heightFactor = screenSize.height < 600 ? 0.92 : 0.86;
    final dialogHeight =
        (screenSize.height * heightFactor).clamp(0.0, 760.0).toDouble();

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: 'Notifications',
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SizedBox(
            width: double.infinity,
            height: dialogHeight,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.white.withOpacity(0.8),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withOpacity(0.18),
                    blurRadius: 40,
                    offset: const Offset(0, 20),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: ValueListenableBuilder<List<AppNotification>>(
                  valueListenable: NotificationService.notificationsListenable,
                  builder: (context, allNotifications, child) {
                    final unreadCount = allNotifications
                        .where((notification) => !notification.seen)
                        .length;
                    final visibleNotifications =
                        _filter == _NotificationFilter.unread
                            ? allNotifications
                                .where((notification) => !notification.seen)
                                .toList()
                            : allNotifications;

                    return Column(
                      children: [
                        _buildHeader(
                          context,
                          unreadCount: unreadCount,
                          total: allNotifications.length,
                        ),
                        if (_isRefreshing)
                          const LinearProgressIndicator(minHeight: 2),
                        Expanded(
                          child: _buildBody(
                            context,
                            visibleNotifications,
                            hasAnyNotifications: allNotifications.isNotEmpty,
                          ),
                        ),
                        _buildFooter(context),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context, {
    required int unreadCount,
    required int total,
  }) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF7F9FC), Colors.white],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      primary,
                      Color.lerp(primary, Colors.white, 0.22)!,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: primary.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.notifications_active_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Notifications',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2937),
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      unreadCount > 0
                          ? '$unreadCount unread of $total'
                          : total == 0
                              ? 'No updates yet'
                              : "You're all caught up",
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: unreadCount > 0 ? _markAllAsSeen : null,
                icon: const Icon(Icons.done_all_rounded),
                tooltip: 'Mark all as read',
                color: primary,
                disabledColor: const Color(0xFFB8C0CC),
                splashRadius: 20,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 40,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Close',
                color: const Color(0xFF6B7280),
                splashRadius: 20,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 40,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildFilterTabs(
            context,
            unreadCount: unreadCount,
            total: total,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs(
    BuildContext context, {
    required int unreadCount,
    required int total,
  }) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4F9),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildFilterTab(
              context,
              label: 'All',
              count: total,
              selected: _filter == _NotificationFilter.all,
              onTap: () => setState(() => _filter = _NotificationFilter.all),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildFilterTab(
              context,
              label: 'Unread',
              count: unreadCount,
              selected: _filter == _NotificationFilter.unread,
              onTap: () => setState(() => _filter = _NotificationFilter.unread),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTab(
    BuildContext context, {
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final primary = Theme.of(context).colorScheme.primary;

    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(11),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: selected ? primary : const Color(0xFF6B7280),
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? primary.withOpacity(0.12)
                            : const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: selected ? primary : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<AppNotification> notifications, {
    required bool hasAnyNotifications,
  }) {
    final primary = Theme.of(context).colorScheme.primary;

    if (_isLoading && !hasAnyNotifications) {
      return const Center(child: CircularProgressIndicator());
    }

    if (notifications.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        color: primary,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: _buildEmptyState(
                    context,
                    hasAnyNotifications: hasAnyNotifications,
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: primary,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        itemCount: notifications.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          return _buildNotificationCard(context, notifications[index]);
        },
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context, {
    required bool hasAnyNotifications,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    final isFiltered = _filter == _NotificationFilter.unread;
    final title = isFiltered
        ? 'No unread notifications'
        : hasAnyNotifications
            ? "You're all caught up!"
            : 'No notifications yet';
    final message = isFiltered
        ? 'Everything here has been read. Switch to All to see your history.'
        : hasAnyNotifications
            ? "When there's something new for you, we'll let you know right here."
            : "We'll let you know as soon as something exciting happens.";

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: primary.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isFiltered
                  ? Icons.mark_email_read_rounded
                  : Icons.notifications_none_rounded,
              size: 44,
              color: primary.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: Color(0xFF6B7280),
            ),
          ),
          if (!hasAnyNotifications) ...[
            const SizedBox(height: 18),
            TextButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNotificationCard(
    BuildContext context,
    AppNotification notification,
  ) {
    final primary = Theme.of(context).colorScheme.primary;
    final isUnread = !notification.seen;
    final isExpanded = _expandedIds.contains(notification.id);
    final description = notification.description.trim().isEmpty
        ? 'No further details provided.'
        : notification.description;

    return AnimatedContainer(
      key: ValueKey<String>(notification.id),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: isUnread ? primary.withOpacity(0.035) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isUnread ? primary.withOpacity(0.22) : const Color(0xFFE8EDF3),
          width: isUnread ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isUnread
                ? primary.withOpacity(0.08)
                : const Color(0xFF0F172A).withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _toggleNotification(notification),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isUnread
                              ? [
                                  primary,
                                  Color.lerp(primary, Colors.white, 0.2)!,
                                ]
                              : const [
                                  Color(0xFFCBD5E1),
                                  Color(0xFFE2E8F0),
                                ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: isUnread
                            ? [
                                BoxShadow(
                                  color: primary.withOpacity(0.25),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : null,
                      ),
                      child: const Icon(
                        Icons.campaign_rounded,
                        color: Colors.white,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  notification.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    height: 1.3,
                                    fontWeight: isUnread
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                    color: const Color(0xFF1F2937),
                                  ),
                                ),
                              ),
                              if (isUnread) ...[
                                const SizedBox(width: 8),
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (notification.subtitle.trim().isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              notification.subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                height: 1.35,
                                color: isUnread
                                    ? primary.withOpacity(0.9)
                                    : const Color(0xFF6B7280),
                                fontWeight: isUnread
                                    ? FontWeight.w500
                                    : FontWeight.w400,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Tooltip(
                                message: DateFormat('MMM d, yyyy • h:mm a')
                                    .format(notification.timestamp),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.schedule_rounded,
                                      size: 13,
                                      color: Color(0xFF94A3B8),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _formatRelativeTime(
                                        notification.timestamp,
                                      ),
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: Color(0xFF94A3B8),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                width: 3,
                                height: 3,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFCBD5E1),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Icon(
                                isUnread
                                    ? Icons.fiber_new_rounded
                                    : Icons.check_circle_rounded,
                                size: 13,
                                color: isUnread
                                    ? primary
                                    : const Color(0xFF94A3B8),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                isUnread ? 'Unread' : 'Read',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: isUnread
                                      ? primary
                                      : const Color(0xFF94A3B8),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 22,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: isExpanded
                      ? Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                height: 1,
                                color: const Color(0xFFE8EDF3),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: const Color(0xFFE8EDF3),
                                  ),
                                ),
                                child: _LinkifiedText(
                                  text: description,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    height: 1.55,
                                    color: Color(0xFF374151),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFEEF2F7))),
        ),
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Close',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatRelativeTime(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inSeconds < 60) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    if (difference.inDays < 7) return '${difference.inDays}d ago';
    if (timestamp.year == now.year) {
      return DateFormat('MMM d').format(timestamp);
    }
    return DateFormat('MMM d, yyyy').format(timestamp);
  }
}

/// Renders notification text and makes any URL inside it tappable.
///
/// The gesture recognizers are owned by this widget so they can be disposed
/// when the text changes or the card is removed.
class _LinkifiedText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _LinkifiedText({required this.text, required this.style});

  @override
  State<_LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<_LinkifiedText> {
  static final RegExp _urlRegExp = RegExp(
    r'https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)',
    caseSensitive: false,
  );

  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];
  late TextSpan _span;

  @override
  void initState() {
    super.initState();
    _buildSpan();
  }

  @override
  void didUpdateWidget(covariant _LinkifiedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _disposeRecognizers();
      _buildSpan();
    }
  }

  void _buildSpan() {
    final text = widget.text;
    final spans = <TextSpan>[];
    var lastMatchEnd = 0;

    for (final match in _urlRegExp.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        spans.add(
          TextSpan(
            text: text.substring(lastMatchEnd, match.start),
            style: widget.style,
          ),
        );
      }

      final url = text.substring(match.start, match.end);
      final recognizer = TapGestureRecognizer()..onTap = () => _openLink(url);
      _recognizers.add(recognizer);

      spans.add(
        TextSpan(
          text: url,
          style: widget.style.copyWith(
            color: const Color(0xFF4F46E5),
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationColor: const Color(0xFF4F46E5).withOpacity(0.4),
          ),
          recognizer: recognizer,
        ),
      );

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(lastMatchEnd),
          style: widget.style,
        ),
      );
    }

    _span = TextSpan(children: spans);
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (e) {
      debugPrint('Could not launch $url: $e');
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not open $url'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SelectableText.rich(_span);
  }
}

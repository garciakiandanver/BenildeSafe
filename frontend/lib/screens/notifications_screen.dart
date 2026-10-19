import 'dart:async';

import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/date_filter_bar.dart';
import '../utils/manila_time.dart';

class NotificationButton extends StatefulWidget {
  final String token;

  const NotificationButton({super.key, required this.token});

  @override
  State<NotificationButton> createState() => _NotificationButtonState();
}

class _NotificationButtonState extends State<NotificationButton> {
  int _unreadCount = 0;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
    // Keep the badge up to date while the screen is open.
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadUnreadCount(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUnreadCount({bool silent = false}) async {
    try {
      final result = await ApiService.getNotifications(token: widget.token);
      if (!mounted) return;
      setState(() {
        _unreadCount = (result['unreadCount'] as num?)?.toInt() ?? 0;
      });
    } catch (error) {
      if (!mounted) return;
      debugPrint('Unable to load notification badge count: $error');
      if (silent) return; // background refresh: do not show a snackbar
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Notification count could not be loaded.'),
        ),
      );
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => NotificationsScreen(token: widget.token),
      ),
    );
    if (mounted) {
      await _loadUnreadCount();
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Notifications',
      onPressed: _openNotifications,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_outlined),
          if (_unreadCount > 0)
            Positioned(
              right: -7,
              top: -5,
              child: Container(
                constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  _unreadCount > 99 ? '99+' : '$_unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class NotificationsScreen extends StatefulWidget {
  final String token;

  const NotificationsScreen({super.key, required this.token});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _isLoading = true;
  String _error = '';
  List<dynamic> _notifications = [];

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  // Shows the whole notification in a large, easy-to-read pop-up (for every
  // role). It is marked as read when the pop-up is closed (with Close, the X,
  // or by tapping outside).
  Future<void> _openNotification(Map<String, dynamic> notification) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _NotificationDialog(
        title: notification['title']?.toString() ?? '',
        message: notification['message']?.toString() ?? '',
        date: _formatCreatedAt(notification['created_at']),
        isUnread: notification['read_at'] == null,
      ),
    );
    if (!mounted) return;
    await _markRead(notification);
  }

  Future<void> _loadNotifications() async {
    try {
      final result = await ApiService.getNotifications(token: widget.token);
      if (!mounted) return;
      setState(() {
        _notifications = result['notifications'] as List<dynamic>? ?? [];
        _error = '';
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _markAllRead() async {
    try {
      await ApiService.markAllNotificationsRead(token: widget.token);
      await _loadNotifications();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _markRead(Map<String, dynamic> notification) async {
    if (notification['read_at'] != null) return;
    try {
      await ApiService.markNotificationRead(
        token: widget.token,
        notificationId: notification['id'].toString(),
      );
      await _loadNotifications();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  static const _weekdayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _monthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  // Example: "Sunday, Oct 4, 2026 • 1:24 AM" (always Manila time)
  String _formatCreatedAt(dynamic value) {
    final date = ManilaTime.parse(value);
    if (date == null) return '';
    final weekday = _weekdayNames[date.weekday - 1];
    final month = _monthNames[date.month - 1];
    return '$weekday, $month ${date.day}, ${date.year} • ${ManilaTime.clock(date)}';
  }

  DateFilter _filter = const DateFilter();

  // Notifications that fall inside the selected dates.
  List<Map<String, dynamic>> get _filteredNotifications => _notifications
      .map((item) => Map<String, dynamic>.from(item as Map))
      .where(
        (item) => _filter.matches(
          ManilaTime.parse(item['created_at']),
        ),
      )
      .toList();

  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifications
        .where((item) => item['read_at'] == null)
        .length;
    final visible = _filteredNotifications;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (unreadCount > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _loadNotifications,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                DateFilterBar(
                  filter: _filter,
                  noun: 'notification',
                  resultCount: visible.length,
                  onChanged: (value) => setState(() => _filter = value),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadNotifications,
                    child: visible.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              const SizedBox(height: 180),
                              Center(
                                child: Text(
                                  _notifications.isEmpty
                                      ? 'You have no notifications.'
                                      : 'No notifications for the selected dates.',
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(12),
                            itemCount: visible.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final notification = visible[index];
                              final isUnread = notification['read_at'] == null;
                              return Card(
                                color: isUnread
                                    ? Theme.of(context)
                                          .colorScheme
                                          .primaryContainer
                                          .withValues(alpha: 0.35)
                                    : null,
                                child: ListTile(
                                  leading: Icon(
                                    isUnread
                                        ? Icons.notifications_active
                                        : Icons.notifications_none,
                                    color: isUnread
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.grey,
                                  ),
                                  title: Text(
                                    notification['title']?.toString() ?? '',
                                    style: TextStyle(
                                      fontSize: 19,
                                      fontWeight: isUnread
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Text(
                                        notification['message']?.toString() ??
                                            '',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 17),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _formatCreatedAt(
                                          notification['created_at'],
                                        ),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodyMedium,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Tap to read',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  onTap: () => _openNotification(notification),
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Large-print pop-up for reading one notification (made for parents).
class _NotificationDialog extends StatelessWidget {
  final String title;
  final String message;
  final String date;
  final bool isUnread;

  const _NotificationDialog({
    required this.title,
    required this.message,
    required this.date,
    required this.isUnread,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.of(context).size.height * 0.85;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 12, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Icon(
                      Icons.notifications_active_outlined,
                      size: 32,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    iconSize: 32,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              if (date.isNotEmpty) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    date,
                    style: TextStyle(
                      fontSize: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
              const Divider(height: 28),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SingleChildScrollView(
                    child: Text(
                      message,
                      style: const TextStyle(fontSize: 22, height: 1.55),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(58),
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              if (isUnread) ...[
                const SizedBox(height: 10),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      'Closing this marks it as read.',
                      style: TextStyle(
                        fontSize: 15,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

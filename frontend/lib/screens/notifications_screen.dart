import 'dart:async';

import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/date_filter_bar.dart';

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

  // Example: "Sunday, Oct 4, 2026 • 1:24 AM"
  String _formatCreatedAt(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return '';
    final localDate = date.toLocal();
    final hour = localDate.hour % 12 == 0 ? 12 : localDate.hour % 12;
    final minute = localDate.minute.toString().padLeft(2, '0');
    final period = localDate.hour < 12 ? 'AM' : 'PM';
    final weekday = _weekdayNames[localDate.weekday - 1];
    final month = _monthNames[localDate.month - 1];
    return '$weekday, $month ${localDate.day}, ${localDate.year} • $hour:$minute $period';
  }

  DateFilter _filter = const DateFilter();

  // Notifications that fall inside the selected dates.
  List<Map<String, dynamic>> get _filteredNotifications => _notifications
      .map((item) => Map<String, dynamic>.from(item as Map))
      .where(
        (item) => _filter.matches(
          DateTime.tryParse(item['created_at']?.toString() ?? ''),
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
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _formatCreatedAt(
                                          notification['created_at'],
                                        ),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                  onTap: () => _markRead(notification),
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
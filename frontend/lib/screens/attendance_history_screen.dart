import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../widgets/app_ui.dart';
import '../widgets/date_filter_bar.dart';
import '../utils/manila_time.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  final String token;

  const AttendanceHistoryScreen({super.key, required this.token});

  @override
  State<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  bool _isLoading = true;
  String? _error;
  List<dynamic> _attendance = [];
  DateFilter _filter = const DateFilter();

  @override
  void initState() {
    super.initState();
    _loadAttendanceHistory();
  }

  Future<void> _loadAttendanceHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final result = await ApiService.getAttendanceHistory(token: widget.token);

      if (!mounted) return;

      setState(() {
        _attendance = result['attendance'] ?? [];
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

  // Records that fall inside the selected dates.
  List<Map<String, dynamic>> get _filteredRecords => _attendance
      .map((record) => Map<String, dynamic>.from(record as Map))
      .where(
        (record) => _filter.matches(
          ManilaTime.parse(record['attendance_date']),
        ),
      )
      .toList();

  String _formatDate(String? value) => ManilaTime.longDate(
    value,
    fallback: value == null || value.isEmpty ? 'N/A' : value,
  );

  // Time in / time out are always shown in Manila time.
  String _formatTime(String? value) => ManilaTime.time(
    value,
    fallback: value == null || value.isEmpty ? 'N/A' : value,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance History')),
      body: Column(
        children: [
          DateFilterBar(
            filter: _filter,
            noun: 'record',
            resultCount: (_isLoading || _error != null)
                ? null
                : _filteredRecords.length,
            onChanged: (value) => setState(() => _filter = value),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load attendance',
          message: 'Unable to connect to the server. Please try again.',
          action: FilledButton.icon(
            onPressed: _loadAttendanceHistory,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ),
      );
    }

    if (_attendance.isEmpty) {
      return const Center(
        child: EmptyState(
          icon: Icons.event_busy_outlined,
          title: 'No attendance yet',
          message: 'Your completed attendance records will appear here.',
        ),
      );
    }

    final records = _filteredRecords;
    if (records.isEmpty) {
      return const Center(
        child: EmptyState(
          icon: Icons.event_busy_outlined,
          title: 'No records found',
          message: 'There are no attendance records for the selected dates.',
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAttendanceHistory,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(18),
        itemCount: records.length,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final record = records[index];
          final status = record['status']?.toString() ?? 'Recorded';
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(17),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _formatDate(record['attendance_date']?.toString()),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      StatusBadge(label: status),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _AttendanceTime(
                          icon: Icons.login_rounded,
                          label: 'Time in',
                          value: _formatTime(record['time_in']?.toString()),
                        ),
                      ),
                      Expanded(
                        child: _AttendanceTime(
                          icon: Icons.logout_rounded,
                          label: 'Time out',
                          value: _formatTime(record['time_out']?.toString()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 17,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          record['campus_name']?.toString() ??
                              'Campus unavailable',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AttendanceTime extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _AttendanceTime({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 17, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 7),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ],
    );
  }
}
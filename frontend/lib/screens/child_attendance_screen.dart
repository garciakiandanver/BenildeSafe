import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/manila_time.dart';
import '../widgets/app_ui.dart';

class ChildAttendanceScreen extends StatefulWidget {
  final String token;
  final String studentId;
  final String studentName;

  const ChildAttendanceScreen({
    super.key,
    required this.token,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<ChildAttendanceScreen> createState() => _ChildAttendanceScreenState();
}

class _ChildAttendanceScreenState extends State<ChildAttendanceScreen> {
  bool _isLoading = true;
  String _error = '';
  List<dynamic> _attendance = [];

  @override
  void initState() {
    super.initState();
    _loadAttendance();
  }

  Future<void> _loadAttendance() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });
    try {
      final result = await ApiService.getChildAttendance(
        token: widget.token,
        studentId: widget.studentId,
      );
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

  // The server sends Manila time (for example 2026-10-18T22:59:00). It is
  // shown as it is, on any device and in any browser time zone.
  String _formatTime(dynamic value) => ManilaTime.time(value, fallback: '--');

  String _formatDate(dynamic value) =>
      ManilaTime.shortDate(value, fallback: '--');

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'present':
        return const Color(0xFF248A5A);
      case 'late':
        return Colors.orange;
      case 'absent':
        return Colors.red;
      case 'timeout':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.studentName)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load attendance',
              message: 'Unable to connect to the server. Please try again.',
              action: FilledButton.icon(
                onPressed: _loadAttendance,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadAttendance,
              child: _attendance.isEmpty
                  ? ListView(
                      physics: AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 150),
                        EmptyState(
                          icon: Icons.event_busy_outlined,
                          title: 'No attendance records',
                          message:
                              'Your child’s attendance history will appear here.',
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: _attendance.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final record = Map<String, dynamic>.from(
                          _attendance[index] as Map,
                        );
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _formatDate(record['attendance_date']),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                    StatusBadge(
                                      label:
                                          record['status']?.toString() ??
                                          'Recorded',
                                      color: _getStatusColor(record['status']),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _TimeValue(
                                        icon: Icons.login_rounded,
                                        label: 'Time in',
                                        value: _formatTime(record['time_in']),
                                      ),
                                    ),
                                    Expanded(
                                      child: _TimeValue(
                                        icon: Icons.logout_rounded,
                                        label: 'Time out',
                                        value: _formatTime(record['time_out']),
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
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        record['campus_name']?.toString() ??
                                            '--',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
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
            ),
    );
  }
}

class _TimeValue extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _TimeValue({
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

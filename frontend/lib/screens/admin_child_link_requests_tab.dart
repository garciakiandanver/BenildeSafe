import 'package:flutter/material.dart';

import '../services/api_service.dart';

/// Admin: parent requests to link another child to their account.
/// Shown as the "Child links" tab of the Registration requests screen.
class AdminChildLinkRequestsTab extends StatefulWidget {
  final String token;

  const AdminChildLinkRequestsTab({super.key, required this.token});

  @override
  State<AdminChildLinkRequestsTab> createState() =>
      _AdminChildLinkRequestsTabState();
}

class _AdminChildLinkRequestsTabState extends State<AdminChildLinkRequestsTab> {
  bool _isLoading = true;
  bool _isBusy = false;
  String _error = '';
  List<Map<String, dynamic>> _requests = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await ApiService.getChildLinkRequests(token: widget.token);
      if (!mounted) return;
      setState(() {
        _requests = (result['requests'] as List<dynamic>? ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
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

  void _showMessage(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    required Color color,
  }) async {
    var answered = false; // ignore a second tap while the box is closing
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              if (answered) return;
              answered = true;
              Navigator.pop(dialogContext, false);
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: color),
            onPressed: () {
              if (answered) return;
              answered = true;
              Navigator.pop(dialogContext, true);
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _decide(Map<String, dynamic> request, {required bool approve}) async {
    if (_isBusy) return;
    final parent = request['parent_name']?.toString() ?? 'the parent';
    final student = request['student_name']?.toString() ?? 'the student';
    final movedFrom = request['current_parent_name']?.toString();

    final message = approve
        ? 'Link $student to $parent? They will receive $student\'s attendance notifications.'
              '${movedFrom != null ? '\n\n$student is currently linked to $movedFrom. Approving moves the link to $parent.' : ''}'
        : 'Decline the request from $parent to link $student?';
    final confirmed = await _confirm(
      title: approve ? 'Approve request' : 'Decline request',
      message: message,
      confirmLabel: approve ? 'Approve' : 'Decline',
      color: approve ? Colors.green : Colors.red,
    );
    if (!mounted || !confirmed) return;

    setState(() => _isBusy = true);
    try {
      final id = request['id'].toString();
      final result = approve
          ? await ApiService.approveChildLink(token: widget.token, requestId: id)
          : await ApiService.rejectChildLink(token: widget.token, requestId: id);
      await _load();
      _showMessage(result['message']?.toString() ?? 'Done.');
    } catch (error) {
      await _load();
      _showMessage(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  String _formatDate(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return '--';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _buildCard(Map<String, dynamic> request) {
    final status = request['status']?.toString();
    final isPending = status == 'pending';
    final classInfo = [
      request['course']?.toString(),
      request['year_level'] == null ? null : 'Year ${request['year_level']}',
      (request['section']?.toString().isNotEmpty ?? false)
          ? 'Section ${request['section']}'
          : null,
    ].where((part) => part != null && part.isNotEmpty).join(' • ');
    final movedFrom = request['current_parent_name']?.toString();
    final alreadyLinked = request['already_linked'] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    request['parent_name']?.toString() ?? '--',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(status),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    (status ?? '--').toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            if ((request['parent_contact']?.toString() ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Contact: ${request['parent_contact']}',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.child_care, size: 18, color: Color(0xFF005A23)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Wants to link ${request['student_name'] ?? '--'}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF005A23),
                        ),
                      ),
                      Text(
                        'Student No: ${request['student_number'] ?? '--'}',
                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      if (classInfo.isNotEmpty)
                        Text(
                          classInfo,
                          style: const TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (isPending && movedFrom != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 18, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This student is already linked to $movedFrom. Approving moves the link to this parent.',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (isPending && alreadyLinked) ...[
              const SizedBox(height: 10),
              const Text(
                'This student is already linked to this parent.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              isPending
                  ? 'Requested: ${_formatDate(request['requested_at'])}'
                  : 'Requested: ${_formatDate(request['requested_at'])}  •  Reviewed: ${_formatDate(request['reviewed_at'])}',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            if (isPending) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isBusy
                          ? null
                          : () => _decide(request, approve: false),
                      icon: const Icon(Icons.close, color: Colors.red),
                      label: const Text(
                        'Decline',
                        style: TextStyle(color: Colors.red),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isBusy
                          ? null
                          : () => _decide(request, approve: true),
                      icon: const Icon(Icons.check),
                      label: const Text('Approve'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_requests.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No child link requests yet.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final pending = _requests.where((r) => r['status'] == 'pending').toList();
    final processed = _requests.where((r) => r['status'] != 'pending').toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (pending.isNotEmpty) ...[
            Row(
              children: [
                const Text(
                  'Pending',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${pending.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...pending.map(_buildCard),
            const SizedBox(height: 24),
          ],
          if (processed.isNotEmpty) ...[
            const Text(
              'Processed',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            ...processed.map(_buildCard),
          ],
        ],
      ),
    );
  }
}
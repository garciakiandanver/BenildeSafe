import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'admin_child_link_requests_tab.dart';

class AdminRegistrationRequestsScreen extends StatefulWidget {
  final String token;

  /// 0 = new accounts, 1 = child link requests.
  final int initialTab;

  const AdminRegistrationRequestsScreen({
    super.key,
    required this.token,
    this.initialTab = 0,
  });

  @override
  State<AdminRegistrationRequestsScreen> createState() =>
      _AdminRegistrationRequestsScreenState();
}

class _AdminRegistrationRequestsScreenState
    extends State<AdminRegistrationRequestsScreen> {
  bool _isLoading = true;
  String _error = '';
  List<dynamic> _requests = [];

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });
    try {
      final result = await ApiService.getRegistrationRequests(
        token: widget.token,
      );
      setState(() {
        _requests = result['requests'] ?? [];
        _isLoading = false;
      });
    } catch (error) {
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _approve(String requestId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve Request'),
        content: Text(
          'Approve registration for $name? This will create their account immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Approve'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final result = await ApiService.approveRequest(
        token: widget.token,
        requestId: requestId,
      );

      if (!mounted) return;

      final emailSent = result['notificationEmailSent'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ??
                'Request approved and notification email sent.',
          ),
          backgroundColor: emailSent ? Colors.green : Colors.orange,
        ),
      );

      _loadRequests();
    } catch (error) {
      if (!mounted) return;
      _loadRequests();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _reject(String requestId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Request'),
        content: Text(
          'Reject registration request from $name? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final result = await ApiService.rejectRequest(
        token: widget.token,
        requestId: requestId,
      );

      if (!mounted) return;

      final emailSent = result['notificationEmailSent'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ??
                'Request declined and notification email sent.',
          ),
          backgroundColor: emailSent ? Colors.orange : Colors.deepOrange,
        ),
      );

      _loadRequests();
    } catch (error) {
      if (!mounted) return;
      _loadRequests();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _getFullName(dynamic request) {
    final first = request['first_name'] ?? '';
    final middle = request['middle_name'] ?? '';
    final last = request['last_name'] ?? '';
    if (middle.isEmpty) return '$first $last';
    return '$first $middle $last';
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '--';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      const months = [
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
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return '--';
    }
  }

  Color _getStatusColor(String? status) {
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

  Widget _buildRoleDetails(dynamic request) {
    final role = request['role_name']?.toString().toLowerCase();
    if (role == 'student') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Student No: ${request['student_number'] ?? '--'}',
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
          Text(
            'Course: ${request['course'] ?? '--'} ${request['year_level'] ?? ''}${request['section'] != null && request['section'].toString().isNotEmpty ? '-${request['section']}' : ''}',
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ],
      );
    } else if (role == 'teacher') {
      return Text(
        'Employee No: ${request['employee_number'] ?? '--'}',
        style: const TextStyle(fontSize: 13, color: Colors.grey),
      );
    } else if (role == 'parent') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Contact: ${request['contact_number'] ?? '--'}',
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
          if (request['child_student_number'] != null &&
              request['child_student_number'].toString().isNotEmpty)
            Text(
              "Child's Student No: ${request['child_student_number']}",
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final pending = _requests.where((r) => r['status'] == 'pending').toList();
    final processed = _requests.where((r) => r['status'] != 'pending').toList();

    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Registration Requests'),
          actions: [
            IconButton(
              onPressed: _loadRequests,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh accounts',
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Accounts'),
              Tab(text: 'Child links'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildAccountsTab(pending, processed),
            AdminChildLinkRequestsTab(token: widget.token),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountsTab(List<dynamic> pending, List<dynamic> processed) {
    return _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? Center(child: Text(_error))
          : _requests.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No registration requests yet.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadRequests,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (pending.isNotEmpty) ...[
                    Row(
                      children: [
                        const Text(
                          'Pending',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
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
                    ...pending.map((request) => _buildRequestCard(request)),
                    const SizedBox(height: 24),
                  ],
                  if (processed.isNotEmpty) ...[
                    const Text(
                      'Processed',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...processed.map((request) => _buildRequestCard(request)),
                  ],
                ],
              ),
            );
  }

  Widget _buildRequestCard(dynamic request) {
    final isPending = request['status'] == 'pending';
    final name = _getFullName(request);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    name,
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
                    color: _getStatusColor(request['status']),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    request['status']?.toUpperCase() ?? '--',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              request['email'] ?? '--',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              'Role: ${request['role_name'] ?? '--'}',
              style: const TextStyle(
                color: Color(0xFF005A23),
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            _buildRoleDetails(request),
            const SizedBox(height: 4),
            Text(
              'Requested: ${_formatDate(request['requested_at'])}',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            if (isPending) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _reject(request['id'], name),
                      icon: const Icon(Icons.close, color: Colors.red),
                      label: const Text(
                        'Reject',
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
                      onPressed: () => _approve(request['id'], name),
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
}
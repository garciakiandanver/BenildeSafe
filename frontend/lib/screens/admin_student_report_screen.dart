import 'package:flutter/material.dart';
import '../services/api_service.dart';

class AdminStudentReportScreen extends StatefulWidget {
  final String token;
  final String? role;

  const AdminStudentReportScreen({super.key, required this.token, this.role});

  @override
  State<AdminStudentReportScreen> createState() =>
      _AdminStudentReportScreenState();
}

class _AdminStudentReportScreenState extends State<AdminStudentReportScreen> {
  static const _roles = ['All roles', 'Student', 'Teacher'];

  bool _isLoading = true;
  String _error = '';
  List<dynamic> _users = [];
  String _searchQuery = '';
  String _selectedRole = 'All roles';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (_roles.contains(widget.role)) {
      _selectedRole = widget.role!;
    }
    _loadUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });
    try {
      final result = await ApiService.getReportUsers(
        token: widget.token,
        role: _selectedRole == 'All roles' ? null : _selectedRole,
      );
      if (!mounted) return;
      setState(() {
        _users = result['users'] ?? [];
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

  List<dynamic> _filteredUsers() {
    if (_searchQuery.isEmpty) return _users;
    return _users.where((u) {
      return (u['full_name'] ?? '').toLowerCase().contains(_searchQuery) ||
          (u['id_number'] ?? '').toLowerCase().contains(_searchQuery) ||
          (u['email'] ?? '').toLowerCase().contains(_searchQuery) ||
          (u['role'] ?? '').toLowerCase().contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredUsers();

    return Scaffold(
      appBar: AppBar(title: const Text('Attendance Reports')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: DropdownButtonFormField<String>(
              initialValue: _selectedRole,
              decoration: const InputDecoration(
                labelText: 'Filter by role',
                prefixIcon: Icon(Icons.filter_list),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _roles
                  .map(
                    (role) => DropdownMenuItem(value: role, child: Text(role)),
                  )
                  .toList(),
              onChanged: (role) {
                if (role == null || role == _selectedRole) return;
                setState(() {
                  _selectedRole = role;
                });
                _loadUsers();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name, ID, or role...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                            _searchController.clear();
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 0,
                  horizontal: 16,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              },
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error.isNotEmpty
                ? Center(child: Text(_error))
                : filtered.isEmpty
                ? const Center(child: Text('No users found.'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final user = filtered[index];
                      final role = (user['role'] ?? '').toLowerCase();
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(
                              0xFF005A23,
                            ).withValues(alpha: 0.1),
                            child: Icon(
                              role == 'teacher' ? Icons.person : Icons.school,
                              color: const Color(0xFF005A23),
                            ),
                          ),
                          title: Text(
                            user['full_name'] ?? '--',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '${user['id_number'] ?? '--'} • ${user['role'] ?? '--'}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    AdminUserAttendanceReportScreen(
                                      token: widget.token,
                                      userId: user['user_id'],
                                      userName: user['full_name'] ?? '--',
                                      idNumber: user['id_number'] ?? '--',
                                      role: user['role'] ?? '--',
                                    ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Individual User Report ───────────────────────────────────────

class AdminUserAttendanceReportScreen extends StatefulWidget {
  final String token;
  final String userId;
  final String userName;
  final String idNumber;
  final String role;

  const AdminUserAttendanceReportScreen({
    super.key,
    required this.token,
    required this.userId,
    required this.userName,
    required this.idNumber,
    required this.role,
  });

  @override
  State<AdminUserAttendanceReportScreen> createState() =>
      _AdminUserAttendanceReportScreenState();
}

class _AdminUserAttendanceReportScreenState
    extends State<AdminUserAttendanceReportScreen> {
  bool _isLoading = true;
  String _error = '';
  List<dynamic> _attendance = [];
  Map<String, int> _summary = {
    'present': 0,
    'late': 0,
    'absent': 0,
    'timeout': 0,
  };

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });
    try {
      final result = await ApiService.getUserAttendanceReport(
        token: widget.token,
        userId: widget.userId,
      );
      final attendance = result['attendance'] as List<dynamic>? ?? [];
      final summary = <String, int>{
        'present': 0,
        'late': 0,
        'absent': 0,
        'timeout': 0,
      };
      for (final record in attendance) {
        final status = (record['status'] ?? '').toLowerCase();
        if (summary.containsKey(status)) {
          summary[status] = (summary[status] ?? 0) + 1;
        }
      }
      setState(() {
        _attendance = attendance;
        _summary = summary;
        _isLoading = false;
      });
    } catch (error) {
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '--';
    try {
      final dt = DateTime.parse(dateStr);
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

  String _formatTime(String? timeStr) {
    if (timeStr == null) return '--';
    try {
      final dt = DateTime.parse(timeStr).toLocal();
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $period';
    } catch (_) {
      return '--';
    }
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'present':
        return Colors.green;
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

  Widget _buildSummaryCard(
    String label,
    int count,
    Color color,
    IconData icon,
  ) {
    return Expanded(
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 4),
              Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _summary.values.fold(0, (a, b) => a + b);

    return Scaffold(
      appBar: AppBar(title: Text(widget.userName)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? Center(child: Text(_error))
          : Column(
              children: [
                // User info header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: const Color(0xFF005A23).withValues(alpha: 0.05),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.userName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.idNumber} • ${widget.role}',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Total Records: $total',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),

                // Summary cards
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      _buildSummaryCard(
                        'Present',
                        _summary['present'] ?? 0,
                        Colors.green,
                        Icons.check_circle,
                      ),
                      const SizedBox(width: 8),
                      _buildSummaryCard(
                        'Late',
                        _summary['late'] ?? 0,
                        Colors.orange,
                        Icons.schedule,
                      ),
                      const SizedBox(width: 8),
                      _buildSummaryCard(
                        'Absent',
                        _summary['absent'] ?? 0,
                        Colors.red,
                        Icons.cancel,
                      ),
                      const SizedBox(width: 8),
                      _buildSummaryCard(
                        'Timeout',
                        _summary['timeout'] ?? 0,
                        Colors.red,
                        Icons.timer_off,
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // Attendance list
                Expanded(
                  child: _attendance.isEmpty
                      ? const Center(
                          child: Text('No attendance records found.'),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _attendance.length,
                          itemBuilder: (context, index) {
                            final record = _attendance[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _formatDate(
                                              record['attendance_date'],
                                            ),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          if (record['class_subject'] !=
                                              null) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              'Class: ${record['class_subject']}',
                                              style: const TextStyle(
                                                color: Color(0xFF005A23),
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 4),
                                          Text(
                                            'Campus: ${record['campus_name'] ?? '--'}',
                                            style: const TextStyle(
                                              color: Colors.grey,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.login,
                                                size: 14,
                                                color: Colors.green,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'In: ${_formatTime(record['time_in'])}',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              const Icon(
                                                Icons.logout,
                                                size: 14,
                                                color: Colors.red,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Out: ${_formatTime(record['time_out'])}',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _getStatusColor(
                                          record['status'],
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        record['status']?.toUpperCase() ?? '--',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

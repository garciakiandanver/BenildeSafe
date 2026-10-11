import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'admin_student_report_screen.dart';

class AdminAttendanceScreen extends StatefulWidget {
  final String token;

  const AdminAttendanceScreen({super.key, required this.token});

  @override
  State<AdminAttendanceScreen> createState() => _AdminAttendanceScreenState();
}

class _AdminAttendanceScreenState extends State<AdminAttendanceScreen> {
  bool _isLoading = true;
  String _error = '';
  List<dynamic> _attendance = [];
  DateTime? _selectedDate;
  String _selectedRole = 'All roles';
  int _attendanceRequestId = 0;

  static const List<String> _roles = ['All roles', 'Student', 'Teacher'];

  @override
  void initState() {
    super.initState();
    _loadAttendance();
  }

  // Format date as YYYY-MM-DD without timezone conversion
  String _dateToString(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadAttendance() async {
    final requestId = ++_attendanceRequestId;
    final selectedDate = _selectedDate == null
        ? null
        : _dateToString(_selectedDate!);
    final selectedRole = _selectedRole;
    setState(() {
      _isLoading = true;
      _error = '';
    });
    try {
      final result = await ApiService.getAdminAttendance(
        token: widget.token,
        date: selectedDate,
        role: selectedRole == 'All roles' ? null : selectedRole,
      );
      if (!mounted || requestId != _attendanceRequestId) return;
      setState(() {
        _attendance = result['attendance'] ?? [];
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted || requestId != _attendanceRequestId) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );

    if (!mounted) return;
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
      _loadAttendance();
    }
  }

  void _clearFilter() {
    setState(() {
      _selectedDate = null;
    });
    _loadAttendance();
  }

  Future<void> _editRecord(dynamic record) async {
    final timeInController = TextEditingController(
      text: _timeForEditing(record['time_in']?.toString()),
    );
    final timeOutController = TextEditingController(
      text: _timeForEditing(record['time_out']?.toString()),
    );
    String selectedStatus = record['status'] ?? 'present';
    final statuses = ['present', 'late', 'absent', 'timeout'];

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text('Edit: ${record['full_name'] ?? '--'}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatDate(record['attendance_date']),
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: timeInController,
                  decoration: const InputDecoration(
                    labelText: 'Time In (HH:MM)',
                    hintText: 'e.g. 07:30',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.login),
                  ),
                  keyboardType: TextInputType.datetime,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: timeOutController,
                  decoration: const InputDecoration(
                    labelText: 'Time Out (HH:MM)',
                    hintText: 'e.g. 17:00',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.logout),
                  ),
                  keyboardType: TextInputType.datetime,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Status:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: statuses.map((s) {
                    final isSelected = selectedStatus == s;
                    return ChoiceChip(
                      label: Text(s.toUpperCase()),
                      selected: isSelected,
                      selectedColor: _getStatusColor(s),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                      onSelected: (_) {
                        setStateDialog(() {
                          selectedStatus = s;
                        });
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);

                final date = record['attendance_date']?.toString().substring(
                  0,
                  10,
                );
                String? timeIn;
                String? timeOut;
                if (timeInController.text.isNotEmpty && date != null) {
                  timeIn = '${date}T${timeInController.text}:00';
                }
                if (timeOutController.text.isNotEmpty && date != null) {
                  timeOut = '${date}T${timeOutController.text}:00';
                }

                navigator.pop();

                try {
                  await ApiService.correctAttendance(
                    token: widget.token,
                    attendanceId: record['id'],
                    timeIn: timeIn,
                    timeOut: timeOut,
                    status: selectedStatus,
                  );
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Attendance record updated successfully.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  if (mounted) _loadAttendance();
                } catch (error) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        error.toString().replaceFirst('Exception: ', ''),
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF005A23),
                foregroundColor: Colors.white,
              ),
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );

    timeInController.dispose();
    timeOutController.dispose();
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
    final time = _timeForEditing(timeStr);
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(time);
    if (match == null) return '--';
    final hour24 = int.tryParse(match.group(1)!);
    final minute = match.group(2);
    if (hour24 == null || hour24 > 23) return '--';
    final hour = hour24 % 12 == 0 ? 12 : hour24 % 12;
    return '$hour:$minute ${hour24 >= 12 ? 'PM' : 'AM'}';
  }

  String _timeForEditing(String? value) {
    if (value == null || value.isEmpty) return '';
    final match = RegExp(r'(?:T|\s|^)(\d{2}):(\d{2})').firstMatch(value.trim());
    if (match == null) return '';
    final hour = int.tryParse(match.group(1)!);
    if (hour == null || hour > 23) return '';
    return '${match.group(1)}:${match.group(2)}';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Records'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadAttendance,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh attendance records',
          ),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      AdminStudentReportScreen(token: widget.token),
                ),
              );
            },
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Attendance Reports',
          ),
          if (_selectedDate != null)
            TextButton.icon(
              onPressed: _clearFilter,
              icon: const Icon(Icons.clear, color: Colors.red),
              label: const Text('Clear', style: TextStyle(color: Colors.red)),
            ),
          IconButton(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today),
            tooltip: 'Filter by date',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.filter_list, color: Color(0xFF005A23)),
                const SizedBox(width: 12),
                const Text(
                  'Show role:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedRole,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: _roles.map((role) {
                      return DropdownMenuItem(value: role, child: Text(role));
                    }).toList(),
                    onChanged: (role) {
                      if (role == null) return;
                      setState(() => _selectedRole = role);
                      _loadAttendance();
                    },
                  ),
                ),
              ],
            ),
          ),

          if (_selectedDate != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFF005A23).withValues(alpha: 0.1),
              child: Row(
                children: [
                  const Icon(
                    Icons.filter_list,
                    size: 16,
                    color: Color(0xFF005A23),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Date: ${_formatDate(_dateToString(_selectedDate!))}',
                    style: const TextStyle(
                      color: Color(0xFF005A23),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_attendance.length} record(s)',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: Colors.grey.withValues(alpha: 0.1),
            child: const Row(
              children: [
                Icon(Icons.touch_app, size: 14, color: Colors.grey),
                SizedBox(width: 6),
                Text(
                  'Tap a record to edit it',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error.isNotEmpty
                ? Center(child: Text(_error))
                : _attendance.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.list_alt,
                          size: 64,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _selectedDate != null
                              ? 'No attendance records for this date.'
                              : 'No attendance records found.',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadAttendance,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _attendance.length,
                      itemBuilder: (context, index) {
                        final record = _attendance[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: InkWell(
                            onTap: () => _editRecord(record),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          record['full_name'] ?? '--',
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
                                          color: _getStatusColor(
                                            record['status'],
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          record['status']?.toUpperCase() ??
                                              '--',
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
                                    '${record['id_number'] ?? '--'} • ${record['role'] ?? '--'}',
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 13,
                                    ),
                                  ),
                                  if (record['class_subject'] != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Class: ${record['class_subject']}',
                                      style: const TextStyle(
                                        color: Color(0xFF005A23),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatDate(record['attendance_date']),
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Campus: ${record['campus_name'] ?? '--'}',
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.login,
                                        size: 16,
                                        color: Colors.green,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'In: ${_formatTime(record['time_in'])}',
                                      ),
                                      const SizedBox(width: 16),
                                      const Icon(
                                        Icons.logout,
                                        size: 16,
                                        color: Colors.red,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Out: ${_formatTime(record['time_out'])}',
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
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

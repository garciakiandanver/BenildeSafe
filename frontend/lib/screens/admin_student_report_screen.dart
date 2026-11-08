import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/app_ui.dart';
import '../widgets/attendance_history_view.dart';

/// The students whose attendance an administrator can open.
///
/// Teachers are not listed. They stopped recording attendance when they became
/// viewers, so the old role filter had nothing left to choose between. Course
/// and year level took its place, which is how a school actually narrows a
/// list of students down.
class AdminStudentReportScreen extends StatefulWidget {
  final String token;

  const AdminStudentReportScreen({super.key, required this.token});

  @override
  State<AdminStudentReportScreen> createState() =>
      _AdminStudentReportScreenState();
}

class _AdminStudentReportScreenState extends State<AdminStudentReportScreen> {
  static const String _anyDepartment = 'All departments';
  static const String _anyCourse = 'All courses';
  static const String _anyYear = 'All year levels';

  bool _isLoading = true;
  String _error = '';
  List<dynamic> _users = [];
  String _searchQuery = '';
  String _selectedDepartment = _anyDepartment;
  String _selectedCourse = _anyCourse;
  String _selectedYear = _anyYear;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
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
      final result = await ApiService.getReportUsers(token: widget.token);
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

  /// The choices offered by a filter, taken from the students that were
  /// loaded, so it never offers a department, course or year that would show
  /// nothing. [within] narrows the list first, so choosing a department
  /// leaves only the courses that belong to it.
  List<String> _optionsFor(String field, {List<dynamic>? within}) {
    final values = (within ?? _users)
        .map((user) => (user[field] ?? '').toString().trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    values.sort((left, right) {
      final leftNumber = int.tryParse(left);
      final rightNumber = int.tryParse(right);
      if (leftNumber != null && rightNumber != null) {
        return leftNumber.compareTo(rightNumber);
      }
      return left.toUpperCase().compareTo(right.toUpperCase());
    });
    return values;
  }

  // A filter left over from an earlier load may no longer exist in the new
  // list, so it falls back to showing everything.
  String _safeValue(String selected, String fallback, List<String> options) =>
      options.contains(selected) ? selected : fallback;

  bool _matches(dynamic row, String field, String chosen, String any) =>
      chosen == any || (row[field] ?? '').toString().trim() == chosen;

  List<dynamic> _filteredUsers(String department, String course, String year) {
    return _users.where((user) {
      if (!_matches(user, 'department', department, _anyDepartment)) {
        return false;
      }
      if (!_matches(user, 'course', course, _anyCourse)) return false;
      if (!_matches(user, 'year_level', year, _anyYear)) return false;
      if (_searchQuery.isEmpty) return true;
      return (user['full_name'] ?? '').toLowerCase().contains(_searchQuery) ||
          (user['id_number'] ?? '').toLowerCase().contains(_searchQuery) ||
          (user['email'] ?? '').toLowerCase().contains(_searchQuery) ||
          (user['course'] ?? '').toLowerCase().contains(_searchQuery);
    }).toList();
  }

  /// "BSIT • Year 3", or as much of it as the record carries.
  String _classLabel(dynamic user) {
    final course = (user['course'] ?? '').toString().trim();
    final year = (user['year_level'] ?? '').toString().trim();
    return [
      course,
      if (year.isNotEmpty) 'Year $year',
    ].where((part) => part.isNotEmpty).join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final departmentOptions = _optionsFor('department');
    final department = _safeValue(
      _selectedDepartment,
      _anyDepartment,
      departmentOptions,
    );
    final inDepartment = _users
        .where((user) => _matches(user, 'department', department, _anyDepartment))
        .toList();

    final courseOptions = _optionsFor('course', within: inDepartment);
    final course = _safeValue(_selectedCourse, _anyCourse, courseOptions);
    final inCourse = inDepartment
        .where((user) => _matches(user, 'course', course, _anyCourse))
        .toList();

    final yearOptions = _optionsFor('year_level', within: inCourse);
    final year = _safeValue(_selectedYear, _anyYear, yearOptions);
    final filtered = _filteredUsers(department, course, year);

    return Scaffold(
      appBar: AppBar(title: const Text('Attendance Reports')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: FilterBar(
              children: [
                if (departmentOptions.isNotEmpty)
                  FilterDropdown(
                    value: department,
                    options: [_anyDepartment, ...departmentOptions],
                    icon: Icons.apartment_outlined,
                    onChanged: (chosen) => setState(() {
                      _selectedDepartment = chosen;
                      _selectedCourse = _anyCourse;
                      _selectedYear = _anyYear;
                    }),
                  ),
                FilterDropdown(
                  value: course,
                  options: [_anyCourse, ...courseOptions],
                  icon: Icons.school_outlined,
                  onChanged: (chosen) => setState(() {
                    _selectedCourse = chosen;
                    _selectedYear = _anyYear;
                  }),
                ),
                FilterDropdown(
                  value: year,
                  options: [_anyYear, ...yearOptions],
                  icon: Icons.format_list_numbered_rounded,
                  onChanged: (chosen) =>
                      setState(() => _selectedYear = chosen),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name, student number, or course...',
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
                ? const Center(child: Text('No students found.'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final user = filtered[index];
                      final classLabel = _classLabel(user);
                      return AppCard(
                        index: index,
                        child: ListTile(
                          leading: ProfileAvatar(
                            name: user['full_name']?.toString() ?? '',
                            radius: 20,
                          ),
                          title: Text(
                            user['full_name'] ?? '--',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            [
                              user['id_number']?.toString() ?? '--',
                              classLabel,
                            ].where((part) => part.isNotEmpty).join(' • '),
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
                                      classLabel: classLabel,
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

  /// "BSIT • Year 3". Empty when the record carries neither.
  final String classLabel;

  const AdminUserAttendanceReportScreen({
    super.key,
    required this.token,
    required this.userId,
    required this.userName,
    required this.idNumber,
    this.classLabel = '',
  });

  @override
  State<AdminUserAttendanceReportScreen> createState() =>
      _AdminUserAttendanceReportScreenState();
}

class _AdminUserAttendanceReportScreenState
    extends State<AdminUserAttendanceReportScreen> {
  @override
  Widget build(BuildContext context) {
    // The same list the student and the parent see, so the three can never
    // drift apart. The administrator's copy only adds the correction notes.
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance report')),
      body: AttendanceHistoryView(
        name: widget.userName,
        subtitle: [
          widget.idNumber,
          widget.classLabel,
        ].where((part) => part.trim().isNotEmpty).join(' · '),
        load: () async {
          final result = await ApiService.getUserAttendanceReport(
            token: widget.token,
            userId: widget.userId,
          );
          return result['attendance'] as List<dynamic>? ?? [];
        },
        loadPhotoDates: () => ApiService.getAdminUserPhotoDates(
          token: widget.token,
          userId: widget.userId,
        ),
        loadPhoto: (date) => ApiService.getAdminPhoto(
          token: widget.token,
          userId: widget.userId,
          date: date,
        ),
      ),
    );
  }
}

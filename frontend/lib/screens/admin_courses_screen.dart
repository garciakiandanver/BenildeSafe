import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../widgets/app_ui.dart';
import 'admin_course_students_screen.dart';
import 'admin_departments_screen.dart';

/// Admin: manage the courses (add, edit, delete). A course must exist before the
/// students of that course can be imported from the masterlist. Departments only
/// group the courses.
class AdminCoursesScreen extends StatefulWidget {
  final String token;

  const AdminCoursesScreen({super.key, required this.token});

  @override
  State<AdminCoursesScreen> createState() => _AdminCoursesScreenState();
}

class _AdminCoursesScreenState extends State<AdminCoursesScreen> {
  bool _isLoading = true;
  bool _isBusy = false;
  String _error = '';
  List<Map<String, dynamic>> _courses = [];
  List<Map<String, dynamic>> _departments = [];

  /// Students by course code (upper case), for the counts and the list.
  Map<String, List<Map<String, dynamic>>> _studentsByCourse = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final courses = await ApiService.getCourses(token: widget.token);
      final departments = await ApiService.getDepartments(token: widget.token);
      final byCourse = <String, List<Map<String, dynamic>>>{};
      try {
        final students = await ApiService.getAdminStudents(token: widget.token);
        for (final item in (students['students'] as List<dynamic>? ?? [])) {
          final student = Map<String, dynamic>.from(item as Map);
          final key = (student['course'] ?? '').toString().trim().toUpperCase();
          byCourse.putIfAbsent(key, () => []).add(student);
        }
      } catch (_) {
        // The courses still show without the student counts.
      }
      if (!mounted) return;
      setState(() {
        _studentsByCourse = byCourse;
        _courses = (courses['courses'] as List<dynamic>? ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        _departments = (departments['departments'] as List<dynamic>? ?? [])
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

  // Runs a save/delete call, then refreshes the list and shows the result.
  Future<void> _run(
    Future<Map<String, dynamic>> Function() action,
    String successMessage,
  ) async {
    setState(() => _isBusy = true);
    try {
      final result = await action();
      await _load();
      _showMessage(result['message']?.toString() ?? successMessage);
    } catch (error) {
      _showMessage(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _manageDepartments() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminDepartmentsScreen(token: widget.token),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _addCourse() async {
    if (_departments.isEmpty) {
      _showMessage('Add a department first, then add its courses.');
      await _manageDepartments();
      return;
    }
    final values = await showDialog<Map<String, String?>>(
      context: context,
      builder: (_) => _CourseFormDialog(departments: _departments),
    );
    if (!mounted || values == null) return;
    await _run(
      () => ApiService.addCourse(
        token: widget.token,
        courseCode: values['code']!,
        courseName: values['name']!,
        departmentId: values['department_id'],
      ),
      'Course added.',
    );
  }

  Future<void> _editCourse(Map<String, dynamic> course) async {
    final values = await showDialog<Map<String, String?>>(
      context: context,
      builder: (_) =>
          _CourseFormDialog(departments: _departments, existing: course),
    );
    if (!mounted || values == null) return;
    await _run(
      () => ApiService.updateCourse(
        token: widget.token,
        courseCode: course['course_code'].toString(),
        courseName: values['name']!,
        departmentId: values['department_id'],
      ),
      'Course updated.',
    );
  }

  Future<void> _deleteCourse(Map<String, dynamic> course) async {
    var answered = false; // ignore a second tap while the box is closing
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete course'),
        content: Text(
          'Delete ${course['course_name']} (${course['course_code']})? '
          'A course that still has students cannot be deleted.',
        ),
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              if (answered) return;
              answered = true;
              Navigator.pop(dialogContext, true);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await _run(
      () => ApiService.deleteCourse(
        token: widget.token,
        courseCode: course['course_code'].toString(),
      ),
      'Course deleted.',
    );
  }

  Widget _buildBody() {
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
    if (_courses.isEmpty) {
      return const EmptyState(
        icon: Icons.school_outlined,
        title: 'No courses yet',
        message: 'Add a department, then add its courses.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        itemCount: _courses.length,
        itemBuilder: (context, index) {
          final course = _courses[index];
          final department = course['department_name']?.toString() ?? '';
          final code = course['course_code']?.toString() ?? '';
          final students = _studentsByCourse[code.trim().toUpperCase()] ?? [];
          return AppCard(
            index: index,
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.school_outlined)),
              title: Text(course['course_name']?.toString() ?? ''),
              subtitle: Text(
                [
                  code,
                  if (department.isNotEmpty) department,
                  '${students.length} ${students.length == 1 ? 'student' : 'students'}',
                ].join(' • '),
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AdminCourseStudentsScreen(
                    token: widget.token,
                    courseCode: code,
                    courseName: course['course_name']?.toString() ?? '',
                    students: students,
                  ),
                ),
              ),
              trailing: PopupMenuButton<String>(
                tooltip: 'Course options',
                enabled: !_isBusy,
                onSelected: (value) {
                  if (value == 'edit') {
                    _editCourse(course);
                  } else {
                    _deleteCourse(course);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Courses'),
        actions: [
          TextButton.icon(
            onPressed: _isBusy ? null : _manageDepartments,
            icon: const Icon(Icons.apartment_outlined, size: 18),
            label: const Text('Departments'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isBusy ? null : _addCourse,
        icon: const Icon(Icons.add),
        label: const Text('Add course'),
      ),
      body: _buildBody(),
    );
  }
}

/// Add / edit form for a course. Returns {'code', 'name', 'department_id'}.
class _CourseFormDialog extends StatefulWidget {
  final List<Map<String, dynamic>> departments;
  final Map<String, dynamic>? existing;

  const _CourseFormDialog({required this.departments, this.existing});

  @override
  State<_CourseFormDialog> createState() => _CourseFormDialogState();
}

class _CourseFormDialogState extends State<_CourseFormDialog> {
  late final TextEditingController _codeController = TextEditingController(
    text: widget.existing?['course_code']?.toString() ?? '',
  );
  late final TextEditingController _nameController = TextEditingController(
    text: widget.existing?['course_name']?.toString() ?? '',
  );
  final _formKey = GlobalKey<FormState>();
  String? _departmentId;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    final wanted = widget.existing?['department_id']?.toString();
    // Only preselect a department that really exists in the list.
    _departmentId = widget.departments.any((d) => d['id']?.toString() == wanted)
        ? wanted
        : null;
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_submitted || !_formKey.currentState!.validate()) return;
    _submitted = true;
    Navigator.pop(context, {
      'code': _codeController.text.trim(),
      'name': _nameController.text.trim(),
      'department_id': _departmentId,
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit course' : 'Add course'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _codeController,
                enabled: !isEdit,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Course code',
                  hintText: 'e.g. BSIT',
                  helperText: isEdit
                      ? 'The course code cannot be changed.'
                      : null,
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a course code.'
                    : null,
              ),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Course name'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a course name.'
                    : null,
              ),
              DropdownButtonFormField<String>(
                initialValue: _departmentId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Department'),
                items: [
                  for (final item in widget.departments)
                    DropdownMenuItem<String>(
                      value: item['id'].toString(),
                      child: Text(
                        '${item['department_name']} (${item['department_code']})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => _departmentId = value,
                validator: (value) =>
                    value == null ? 'Choose a department.' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(isEdit ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}

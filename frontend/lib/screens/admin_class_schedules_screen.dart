import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'admin_departments_screen.dart';

class AdminClassSchedulesScreen extends StatefulWidget {
  final String token;
  final Map<String, dynamic>? course;
  final String? termId;

  const AdminClassSchedulesScreen({
    super.key,
    required this.token,
    this.course,
    this.termId,
  });

  @override
  State<AdminClassSchedulesScreen> createState() =>
      _AdminClassSchedulesScreenState();
}

class _AdminClassSchedulesScreenState extends State<AdminClassSchedulesScreen> {
  static const _weekdays = [
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  bool _isLoading = true;
  bool _isUploading = false;
  String _error = '';
  List<dynamic> _schedules = [];
  List<dynamic> _courses = [];
  List<dynamic> _departments = [];
  String _selectedDepartment = 'all'; // 'all', 'none' (no department) or an id
  List<dynamic> _terms = [];
  List<dynamic> _campuses = [];
  String? _selectedTermId;
  bool _selectedTermIsCurrent = false;
  String _selectedYear = 'all';
  final _lateAfterMinutesController = TextEditingController(text: '30');

  @override
  void initState() {
    super.initState();
    _loadSchedules();
  }

  @override
  void dispose() {
    _lateAfterMinutesController.dispose();
    super.dispose();
  }

  Future<void> _loadSchedules() async {
    try {
      final termsResult = await ApiService.getAcademicTerms(
        token: widget.token,
      );
      final campusesResult = await ApiService.getAdminCampuses(
        token: widget.token,
      );
      final terms = termsResult['terms'] as List<dynamic>? ?? [];
      final campuses = campusesResult['campuses'] as List<dynamic>? ?? [];
      final termMaps = terms
          .map((term) => Map<String, dynamic>.from(term as Map))
          .toList();
      final currentTerm = termMaps.firstWhere(
        (term) => term['is_current'] == true,
        orElse: () => <String, dynamic>{},
      );
      final selectedTermId =
          termMaps.any((term) => term['id']?.toString() == _selectedTermId)
          ? _selectedTermId
          : termMaps.any((term) => term['id']?.toString() == widget.termId)
          ? widget.termId
          : currentTerm['id']?.toString();
      final activeSelection = termMaps.firstWhere(
        (term) => term['id']?.toString() == selectedTermId,
        orElse: () => <String, dynamic>{},
      );
      final selectedIsCurrent = activeSelection['is_current'] == true;
      if (mounted) {
        setState(() {
          _terms = terms;
          _campuses = campuses;
          _selectedTermId = selectedTermId;
          _selectedTermIsCurrent = selectedIsCurrent;
        });
      }
      if (widget.course == null) {
        final result = await ApiService.getCourses(
          token: widget.token,
          termId: selectedTermId,
        );
        final departmentsResult = await ApiService.getDepartments(
          token: widget.token,
        );
        if (!mounted) return;
        setState(() {
          _courses = result['courses'] as List<dynamic>? ?? [];
          _departments =
              departmentsResult['departments'] as List<dynamic>? ?? [];
          // Keep the filter valid if its department was deleted.
          if (_selectedDepartment != 'all' &&
              _selectedDepartment != 'none' &&
              !_departments.any(
                (d) => d['id']?.toString() == _selectedDepartment,
              )) {
            _selectedDepartment = 'all';
          }
          _error = '';
          _isLoading = false;
        });
        return;
      }

      final result = await ApiService.getClassSchedules(
        token: widget.token,
        courseCode: widget.course!['course_code'].toString(),
        termId: selectedTermId,
      );
      if (!mounted) return;
      final availableYears = result['schedules'] as List<dynamic>? ?? [];
      setState(() {
        _schedules = availableYears;
        if (_selectedYear != 'all' &&
            !availableYears.any(
              (schedule) => schedule['year_level']?.toString() == _selectedYear,
            )) {
          _selectedYear = 'all';
        }
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

  Future<void> _selectTerm(String? termId) async {
    if (termId == null || termId == _selectedTermId) return;
    final selectedTerm = _terms
        .map((term) => Map<String, dynamic>.from(term as Map))
        .firstWhere(
          (term) => term['id']?.toString() == termId,
          orElse: () => <String, dynamic>{},
        );
    setState(() {
      _selectedTermId = termId;
      _selectedTermIsCurrent = selectedTerm['is_current'] == true;
      _isLoading = true;
    });
    await _loadSchedules();
  }

  Future<void> _createAcademicTerm() async {
    final schoolYearController = TextEditingController();
    final semesterController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    try {
      final values = await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Start a new semester'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: schoolYearController,
                  decoration: const InputDecoration(
                    labelText: 'School year',
                    hintText: '2025-2026',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a school year.'
                      : null,
                ),
                TextFormField(
                  controller: semesterController,
                  decoration: const InputDecoration(
                    labelText: 'Semester',
                    hintText: '1st Semester',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a semester.'
                      : null,
                ),
                const SizedBox(height: 8),
                const Text(
                  'This activates a new term. Existing schedules and attendance stay in the previous term.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(dialogContext, {
                  'school_year': schoolYearController.text.trim(),
                  'semester': semesterController.text.trim(),
                });
              },
              child: const Text('Activate'),
            ),
          ],
        ),
      );
      if (!mounted || values == null) return;
      setState(() => _isUploading = true);
      final result = await ApiService.createAcademicTerm(
        token: widget.token,
        schoolYear: values['school_year']!,
        semester: values['semester']!,
      );
      _selectedTermId = result['term']?['id']?.toString();
      await _loadSchedules();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ?? 'New semester activated.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      schoolYearController.dispose();
      semesterController.dispose();
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _editAcademicTerm() async {
    final termId = _selectedTermId;
    if (termId == null || _isLoading || _isUploading) return;
    final selectedTerm = _terms
        .map((term) => Map<String, dynamic>.from(term as Map))
        .firstWhere(
          (term) => term['id']?.toString() == termId,
          orElse: () => <String, dynamic>{},
        );
    if (selectedTerm.isEmpty) return;

    final schoolYearController = TextEditingController(
      text: selectedTerm['school_year']?.toString() ?? '',
    );
    final semesterController = TextEditingController(
      text: selectedTerm['semester']?.toString() ?? '',
    );
    final formKey = GlobalKey<FormState>();
    try {
      final values = await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Edit academic term'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: schoolYearController,
                  decoration: const InputDecoration(labelText: 'School year'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a school year.'
                      : null,
                ),
                TextFormField(
                  controller: semesterController,
                  decoration: const InputDecoration(labelText: 'Semester'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a semester.'
                      : null,
                ),
                const SizedBox(height: 8),
                const Text(
                  'This only changes the term label. Schedules and attendance history are kept.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(dialogContext, {
                  'school_year': schoolYearController.text.trim(),
                  'semester': semesterController.text.trim(),
                });
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (!mounted || values == null) return;
      setState(() => _isUploading = true);
      final result = await ApiService.updateAcademicTerm(
        token: widget.token,
        termId: termId,
        schoolYear: values['school_year']!,
        semester: values['semester']!,
      );
      await _loadSchedules();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']?.toString() ?? 'Term updated.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      schoolYearController.dispose();
      semesterController.dispose();
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _archiveAllSchedules() async {
    final termId = _selectedTermId;
    if (termId == null || _isLoading || _schedules.isEmpty) return;
    final courseName =
        widget.course?['course_name']?.toString() ?? 'this course';
    final term = _terms
        .map((item) => Map<String, dynamic>.from(item as Map))
        .firstWhere(
          (item) => item['id']?.toString() == termId,
          orElse: () => <String, dynamic>{},
        );
    final termName = '${term['school_year'] ?? ''} ${term['semester'] ?? ''}'
        .trim();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete all schedules?'),
        content: Text(
          'Archive all ${_schedules.length} schedules for $courseName in $termName? '
          'Attendance history will be preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Archive all'),
          ),
        ],
      ),
    );
    if (!mounted || confirm != true) return;
    setState(() => _isUploading = true);
    try {
      final result = await ApiService.archiveCourseTermSchedules(
        token: widget.token,
        courseCode: widget.course!['course_code'].toString(),
        termId: termId,
      );
      await _loadSchedules();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']?.toString() ?? 'Schedules archived.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  List<Map<String, dynamic>> get _campusesWithBoundaries => _campuses
      .map((campus) => Map<String, dynamic>.from(campus as Map))
      .where((campus) => campus['boundary_coordinates'] != null)
      .toList();

  Future<void> _downloadScheduleTemplate() async {
    try {
      final savedFile = await FilePicker.saveFile(
        fileName: 'class_schedule_template.csv',
        bytes: utf8.encode(
          'course,year_level,section,subject,weekday,start_time,late_after,end_time,teacher_email,campus_code\r\n',
        ),
        mimeType: 'text/csv',
        dialogTitle: 'Save class schedule template',
        type: FileType.custom,
        allowedExtensions: const ['csv'],
      );
      if (!mounted || savedFile == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Schedule template saved.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<String?> _chooseDefaultCampus() {
    final campuses = _campusesWithBoundaries;
    if (campuses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Configure a campus boundary before importing schedules.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return Future.value(null);
    }

    String? selectedCode = campuses.first['campus_code']?.toString();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Choose default class campus'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'This campus is used for timetable rows with no campus_code. Rows can set their own campus_code in the template.',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selectedCode,
                decoration: const InputDecoration(
                  labelText: 'Default campus',
                  border: OutlineInputBorder(),
                ),
                items: campuses.map((campus) {
                  final code = campus['campus_code'].toString();
                  return DropdownMenuItem(
                    value: code,
                    child: Text(
                      '${campus['campus_name']} ($code)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (value) =>
                    setDialogState(() => selectedCode = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selectedCode == null
                  ? null
                  : () => Navigator.pop(dialogContext, selectedCode),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }

  bool _isLegacyTimetableCsv(Uint8List bytes) {
    // Same rule as the server: any row that starts with
    // "Code, Subject Description" marks the original timetable format.
    final lines = utf8
        .decode(bytes.take(8192).toList(), allowMalformed: true)
        .replaceAll('\u0000', '')
        .replaceAll('\uFFFD', '')
        .replaceAll('\uFEFF', '')
        .split(RegExp(r'\r?\n'));
    return lines.any((line) {
      final cells = line
          .split(RegExp(r'[,;\t]'))
          .map((value) => value.trim().toLowerCase().replaceAll('"', ''))
          .toList();
      return cells.length >= 2 &&
          cells[0] == 'code' &&
          cells[1] == 'subject description';
    });
  }

  Future<void> _uploadSchedule() async {
    if (_isLoading || !_selectedTermIsCurrent) return;
    final lateAfterMinutes = int.tryParse(
      _lateAfterMinutesController.text.trim(),
    );
    if (lateAfterMinutes == null ||
        lateAfterMinutes < 1 ||
        lateAfterMinutes > 240) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Late cutoff must be a whole number from 1 to 240 minutes.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx'],
    );
    if (!mounted || file == null) return;

    setState(() => _isUploading = true);
    try {
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (bytes.isEmpty) {
        throw Exception('The selected file could not be read.');
      }
      final isLegacyTimetable =
          file.extension?.toLowerCase() == 'csv' &&
          _isLegacyTimetableCsv(bytes);
      if (isLegacyTimetable && widget.course == null) {
        throw Exception(
          'Original year-by-year timetables cover a single course. '
          'Open the course and upload it there, or use the template with a course column.',
        );
      }
      final defaultCampusCode = isLegacyTimetable
          ? await _chooseDefaultCampus()
          : '';
      if (!mounted || (isLegacyTimetable && defaultCampusCode == null)) return;
      final result = await ApiService.importClassSchedules(
        token: widget.token,
        fileName: file.name,
        bytes: bytes,
        lateAfterMinutes: lateAfterMinutes,
        courseCode: widget.course?['course_code']?.toString(),
        campusCode: defaultCampusCode ?? '',
      );
      await _loadSchedules();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']?.toString() ?? 'Schedule imported.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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

  Future<void> _manageDepartments() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminDepartmentsScreen(token: widget.token),
      ),
    );
    if (mounted) await _loadSchedules();
  }

  Future<void> _addCourse() async {
    if (_departments.isEmpty) {
      _showMessage('Add a department first, then add its courses.');
      await _manageDepartments();
      return;
    }
    final values = await showDialog<Map<String, String?>>(
      context: context,
      builder: (_) => _CourseFormDialog(
        departments: _departments,
        initialDepartmentId:
            _selectedDepartment == 'all' || _selectedDepartment == 'none'
            ? null
            : _selectedDepartment,
      ),
    );
    if (!mounted || values == null) return;
    setState(() => _isUploading = true);
    try {
      final result = await ApiService.addCourse(
        token: widget.token,
        courseCode: values['code']!,
        courseName: values['name']!,
        departmentId: values['department_id'],
      );
      await _loadSchedules();
      _showMessage(result['message']?.toString() ?? 'Course added.');
    } catch (error) {
      _showMessage(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _editCourse(Map<String, dynamic> course) async {
    final values = await showDialog<Map<String, String?>>(
      context: context,
      builder: (_) =>
          _CourseFormDialog(departments: _departments, existing: course),
    );
    if (!mounted || values == null) return;
    setState(() => _isUploading = true);
    try {
      final result = await ApiService.updateCourse(
        token: widget.token,
        courseCode: course['course_code'].toString(),
        courseName: values['name']!,
        departmentId: values['department_id'],
      );
      await _loadSchedules();
      _showMessage(result['message']?.toString() ?? 'Course updated.');
    } catch (error) {
      _showMessage(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _deleteCourse(Map<String, dynamic> course) async {
    final confirmed = await _confirm(
      title: 'Delete course',
      message:
          'Delete ${course['course_name']} (${course['course_code']})? '
          'A course that still has students or class schedules cannot be deleted.',
      confirmLabel: 'Delete',
    );
    if (!mounted || !confirmed) return;
    setState(() => _isUploading = true);
    try {
      final result = await ApiService.deleteCourse(
        token: widget.token,
        courseCode: course['course_code'].toString(),
      );
      await _loadSchedules();
      _showMessage(result['message']?.toString() ?? 'Course deleted.');
    } catch (error) {
      _showMessage(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  String _formatTime(dynamic value) {
    final text = value?.toString() ?? '';
    if (text.length < 5) return text;
    final hour = int.tryParse(text.substring(0, 2));
    if (hour == null) return text;
    final hour12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$hour12:${text.substring(3, 5)} ${hour < 12 ? 'AM' : 'PM'}';
  }

  Future<void> _editSchedule(Map<String, dynamic> schedule) async {
    final courseController = TextEditingController(
      text: schedule['course']?.toString() ?? '',
    );
    final yearController = TextEditingController(
      text: schedule['year_level']?.toString() ?? '',
    );
    final sectionController = TextEditingController(
      text: schedule['section']?.toString() ?? '',
    );
    final subjectController = TextEditingController(
      text: schedule['subject']?.toString() ?? '',
    );
    final startController = TextEditingController(
      text: _formatTime(schedule['start_time']),
    );
    final lateController = TextEditingController(
      text: _formatTime(schedule['late_after']),
    );
    final endController = TextEditingController(
      text: _formatTime(schedule['end_time']),
    );
    final teacherController = TextEditingController(
      text: schedule['teacher_name']?.toString() ?? '',
    );
    final emailController = TextEditingController(
      text: schedule['teacher_email']?.toString() ?? '',
    );
    final formKey = GlobalKey<FormState>();
    var selectedWeekday = (schedule['weekday'] as num?)?.toInt();
    final scheduleCampusCode = schedule['campus_code']?.toString();
    var selectedCampusCode =
        _campusesWithBoundaries.any(
          (campus) => campus['campus_code'] == scheduleCampusCode,
        )
        ? scheduleCampusCode
        : null;

    try {
      final values = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Edit class schedule'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _editField(courseController, 'Course'),
                      _editField(yearController, 'Year level'),
                      _editField(
                        sectionController,
                        'Section (leave blank if none)',
                        requiredField: false,
                      ),
                      _editField(subjectController, 'Subject'),
                      DropdownButtonFormField<int>(
                        initialValue: selectedWeekday,
                        decoration: const InputDecoration(labelText: 'Weekday'),
                        items: List.generate(
                          _weekdays.length,
                          (index) => DropdownMenuItem(
                            value: index,
                            child: Text(_weekdays[index]),
                          ),
                        ),
                        validator: (value) =>
                            value == null ? 'Select a weekday.' : null,
                        onChanged: (value) {
                          setDialogState(() => selectedWeekday = value);
                        },
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: selectedCampusCode,
                        decoration: const InputDecoration(
                          labelText: 'Class campus',
                        ),
                        items: _campusesWithBoundaries.map((campus) {
                          final code = campus['campus_code'].toString();
                          return DropdownMenuItem(
                            value: code,
                            child: Text(
                              '${campus['campus_name']} ($code)',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        validator: (value) =>
                            value == null ? 'Select the class campus.' : null,
                        onChanged: (value) {
                          setDialogState(() => selectedCampusCode = value);
                        },
                      ),
                      _editField(startController, 'Start time'),
                      _editField(lateController, 'Late after'),
                      _editField(endController, 'End time'),
                      _editField(
                        teacherController,
                        'Instructor name',
                        requiredField: false,
                      ),
                      _editField(
                        emailController,
                        'Teacher email (optional)',
                        requiredField: false,
                      ),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'An instructor without an active account remains unassigned for teacher attendance.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (!formKey.currentState!.validate()) return;
                  Navigator.pop(dialogContext, {
                    'course': courseController.text.trim(),
                    'year_level': yearController.text.trim(),
                    'section': sectionController.text.trim(),
                    'subject': subjectController.text.trim(),
                    'weekday': selectedWeekday,
                    'campus_code': selectedCampusCode,
                    'start_time': startController.text.trim(),
                    'late_after': lateController.text.trim(),
                    'end_time': endController.text.trim(),
                    'instructor_name': teacherController.text.trim(),
                    'teacher_email': emailController.text.trim(),
                  });
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );
      if (!mounted || values == null) return;

      setState(() => _isUploading = true);
      final result = await ApiService.updateClassSchedule(
        token: widget.token,
        scheduleId: schedule['id'].toString(),
        schedule: values,
      );
      await _loadSchedules();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ?? 'Class schedule updated.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      courseController.dispose();
      yearController.dispose();
      sectionController.dispose();
      subjectController.dispose();
      startController.dispose();
      lateController.dispose();
      endController.dispose();
      teacherController.dispose();
      emailController.dispose();
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _deleteSchedule(Map<String, dynamic> schedule) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete class schedule?'),
        content: Text(
          'Archive "${schedule['subject']}" for Year ${schedule['year_level']}? '
          'Attendance history will be preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted || confirm != true) return;

    setState(() => _isUploading = true);
    try {
      final result = await ApiService.deleteClassSchedule(
        token: widget.token,
        scheduleId: schedule['id'].toString(),
      );
      await _loadSchedules();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']?.toString() ?? 'Schedule deleted.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Widget _editField(
    TextEditingController controller,
    String label, {
    bool requiredField = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        validator: requiredField
            ? (value) =>
                  value == null || value.trim().isEmpty ? 'Enter $label.' : null
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final courseCode = widget.course?['course_code']?.toString();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.course == null
              ? 'Departments & courses'
              : '${widget.course!['course_name']} ($courseCode)',
        ),
      ),
      floatingActionButton: widget.course == null
          ? FloatingActionButton.extended(
              onPressed: _isUploading ? null : _addCourse,
              icon: const Icon(Icons.add),
              label: const Text('Add course'),
            )
          : FloatingActionButton.extended(
              onPressed: _isUploading || _isLoading || !_selectedTermIsCurrent
                  ? null
                  : _uploadSchedule,
              icon: _isUploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.upload_file),
              label: Text(_isUploading ? 'Uploading...' : 'Upload timetable'),
            ),
      body: widget.course == null ? _buildCoursesBody() : _buildSchedulesBody(),
    );
  }

  Widget _buildCoursesBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _loadSchedules,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadSchedules,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          _buildTermControls(),
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Whole-school timetable',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Upload one CSV or Excel file for every course. Fill the course and campus_code columns on every row. Each course must already be added below.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _isUploading || !_selectedTermIsCurrent
                            ? null
                            : _uploadSchedule,
                        icon: const Icon(Icons.upload_file),
                        label: Text(
                          _isUploading
                              ? 'Uploading...'
                              : 'Upload whole-school timetable',
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _isUploading || !_selectedTermIsCurrent
                            ? null
                            : _downloadScheduleTemplate,
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Download CSV template'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          _buildDepartmentFilter(),
          ..._buildCourseGroups(),
        ],
      ),
    );
  }

  Widget _buildDepartmentFilter() {
    final unassigned = _courses
        .where((course) => course['department_id'] == null)
        .length;

    Widget chip(String value, String label) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _selectedDepartment == value,
        onSelected: (_) => setState(() => _selectedDepartment = value),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Text(
                    'Filter by department',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _isUploading ? null : _manageDepartments,
                icon: const Icon(Icons.apartment_outlined, size: 18),
                label: const Text('Manage departments'),
              ),
            ],
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                chip('all', 'All (${_courses.length})'),
                for (final item in _departments)
                  chip(
                    item['id'].toString(),
                    '${item['department_code']} (${item['course_count'] ?? 0})',
                  ),
                if (unassigned > 0) chip('none', 'No department ($unassigned)'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Courses grouped under their department (filtered by the chips above).
  List<Widget> _buildCourseGroups() {
    final courses = _courses
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();

    if (_departments.isEmpty && courses.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: 48),
          child: Center(
            child: Text(
              'No departments or courses yet. Tap "Manage departments" to add a department, then add its courses.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ];
    }

    final widgets = <Widget>[];
    void addGroup(String title, List<Map<String, dynamic>> group) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
      );
      if (group.isEmpty) {
        widgets.add(
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              'No courses yet. Tap "Add course" to add one.',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        );
      } else {
        widgets.addAll(group.map(_buildCourseTile));
      }
    }

    for (final item in _departments) {
      final department = Map<String, dynamic>.from(item as Map);
      final id = department['id'].toString();
      if (_selectedDepartment != 'all' && _selectedDepartment != id) continue;
      addGroup(
        '${department['department_name']} (${department['department_code']})',
        courses.where((c) => c['department_id']?.toString() == id).toList(),
      );
    }

    if (_selectedDepartment == 'all' || _selectedDepartment == 'none') {
      final unassigned = courses
          .where((c) => c['department_id'] == null)
          .toList();
      if (unassigned.isNotEmpty) addGroup('No department', unassigned);
    }
    return widgets;
  }

  Widget _buildCourseTile(Map<String, dynamic> course) {
    final scheduleCount = course['schedule_count'] as num? ?? 0;
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.school)),
        title: Text(course['course_name']?.toString() ?? ''),
        subtitle: Text(
          '${course['course_code']} • $scheduleCount class schedules',
        ),
        trailing: PopupMenuButton<String>(
          tooltip: 'Course options',
          enabled: !_isUploading,
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
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AdminClassSchedulesScreen(
                token: widget.token,
                course: course,
                termId: _selectedTermId,
              ),
            ),
          );
          if (mounted) await _loadSchedules();
        },
      ),
    );
  }

  Widget _buildTermControls() {
    final selectedTerm = _terms
        .map((term) => Map<String, dynamic>.from(term as Map))
        .firstWhere(
          (term) => term['id']?.toString() == _selectedTermId,
          orElse: () => <String, dynamic>{},
        );
    final selectedLabel = selectedTerm.isEmpty
        ? 'No academic term'
        : '${selectedTerm['school_year']} • ${selectedTerm['semester']}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: _terms.isEmpty
                  ? Text(selectedLabel)
                  : DropdownButtonFormField<String>(
                      initialValue: _selectedTermId,
                      decoration: const InputDecoration(
                        labelText: 'Academic term',
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      items: _terms.map((item) {
                        final term = Map<String, dynamic>.from(item as Map);
                        final label =
                            '${term['school_year']} • ${term['semester']}'
                            '${term['is_current'] == true ? ' (Current)' : ''}';
                        return DropdownMenuItem(
                          value: term['id'].toString(),
                          child: Text(label, overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: _isUploading || _isLoading
                          ? null
                          : _selectTerm,
                    ),
            ),
            IconButton(
              tooltip: 'Edit selected term',
              onPressed: _terms.isEmpty || _isUploading || _isLoading
                  ? null
                  : _editAcademicTerm,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Start a new semester',
              onPressed: _isUploading || _isLoading
                  ? null
                  : _createAcademicTerm,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSchedulesBody() {
    final years =
        _schedules
            .map((schedule) => schedule['year_level']?.toString() ?? '')
            .where((year) => year.isNotEmpty)
            .toSet()
            .toList()
          ..sort((left, right) {
            final leftNumber = int.tryParse(left);
            final rightNumber = int.tryParse(right);
            if (leftNumber != null && rightNumber != null) {
              return leftNumber.compareTo(rightNumber);
            }
            return left.compareTo(right);
          });
    final filteredSchedules = _selectedYear == 'all'
        ? _schedules
        : _schedules
              .where(
                (schedule) =>
                    schedule['year_level']?.toString() == _selectedYear,
              )
              .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: _buildTermControls(),
        ),
        if (!_selectedTermIsCurrent)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Historical term — uploads and schedule edits are disabled.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ),
        Card(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            title: const Text('Upload instructions'),
            subtitle: const Text('CSV or Excel • weekly schedule'),
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  'course,year_level,section,subject,weekday,start_time,late_after,end_time,teacher_email,campus_code',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
              const SizedBox(height: 4),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Use one row per class and set campus_code on every template row. It must match a campus with a configured boundary.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _isUploading || !_selectedTermIsCurrent
                      ? null
                      : _downloadScheduleTemplate,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Download CSV template'),
                ),
              ),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Original year-by-year CSV timetables are also supported; only that format asks you to choose a default campus. JPG/PNG is not supported.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                enabled: _selectedTermIsCurrent,
                controller: _lateAfterMinutesController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Late cutoff (minutes)',
                  helperText: 'For original timetable CSVs; default 30.',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        if (years.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DropdownButtonFormField<String>(
              initialValue: years.contains(_selectedYear)
                  ? _selectedYear
                  : 'all',
              decoration: const InputDecoration(
                labelText: 'Filter by year level',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              items: [
                const DropdownMenuItem(
                  value: 'all',
                  child: Text('All year levels'),
                ),
                ...years.map(
                  (year) =>
                      DropdownMenuItem(value: year, child: Text('Year $year')),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _selectedYear = value);
              },
            ),
          ),
        if (_schedules.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _isUploading || _isLoading
                    ? null
                    : _archiveAllSchedules,
                icon: const Icon(Icons.delete_sweep, color: Colors.red),
                label: const Text(
                  'Delete all schedules',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ),
          ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _loadSchedules,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _schedules.isEmpty
              ? RefreshIndicator(
                  onRefresh: _loadSchedules,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 100),
                      Center(child: Text('No class schedules uploaded.')),
                    ],
                  ),
                )
              : filteredSchedules.isEmpty
              ? const Center(child: Text('No schedules for this year level.'))
              : RefreshIndicator(
                  onRefresh: _loadSchedules,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                    itemCount: filteredSchedules.length,
                    itemBuilder: (context, index) {
                      final schedule = Map<String, dynamic>.from(
                        filteredSchedules[index] as Map,
                      );
                      final weekday = schedule['weekday'] as num?;
                      final weekdayName =
                          weekday != null &&
                              weekday.toInt() >= 0 &&
                              weekday.toInt() < _weekdays.length
                          ? _weekdays[weekday.toInt()]
                          : 'Unknown day';
                      final section = schedule['section']?.toString().trim();
                      return Card(
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.menu_book),
                          ),
                          title: Text(
                            schedule['subject']?.toString() ?? 'Class',
                          ),
                          subtitle: Text(
                            '${schedule['course']} ${schedule['year_level']}${section == null || section.isEmpty ? ' (no section)' : '-$section'} • $weekdayName\n'
                            '${_formatTime(schedule['start_time'])} - ${_formatTime(schedule['end_time'])} '
                            '(late after ${_formatTime(schedule['late_after'])})\n'
                            'Campus: ${schedule['campus_name'] ?? 'Not assigned'}\n'
                            'Teacher: ${schedule['teacher_name'] ?? schedule['teacher_email'] ?? '--'}',
                          ),
                          isThreeLine: true,
                          trailing: PopupMenuButton<String>(
                            enabled:
                                !_isUploading &&
                                !_isLoading &&
                                _selectedTermIsCurrent,
                            onSelected: (action) {
                              if (action == 'edit') {
                                _editSchedule(schedule);
                              } else if (action == 'delete') {
                                _deleteSchedule(schedule);
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'edit',
                                child: ListTile(
                                  leading: Icon(Icons.edit),
                                  title: Text('Edit'),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: ListTile(
                                  leading: Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                  title: Text('Delete'),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

/// Add / edit form for a course. Returns {'code', 'name', 'department_id'}.
/// The course code can only be set when adding: schedules and students use it.
class _CourseFormDialog extends StatefulWidget {
  final List<dynamic> departments;
  final Map<String, dynamic>? existing;
  final String? initialDepartmentId;

  const _CourseFormDialog({
    required this.departments,
    this.existing,
    this.initialDepartmentId,
  });

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
    final wanted =
        widget.existing?['department_id']?.toString() ??
        widget.initialDepartmentId;
    // Only preselect a department that really exists in the list.
    _departmentId =
        widget.departments.any((d) => d['id']?.toString() == wanted)
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
                  helperText: isEdit ? 'The course code cannot be changed.' : null,
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
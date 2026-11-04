import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../widgets/app_ui.dart';
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

  // Finding one class among many, to edit it: words typed in the search
  // box, and the day and campus filters beside the year.
  final _scheduleSearchController = TextEditingController();
  String _scheduleSearch = '';
  static const _anyDay = 'Any day';
  static const _anyCampus = 'Any campus';
  String _selectedDay = _anyDay;
  String _selectedCampus = _anyCampus;

  @override
  void initState() {
    super.initState();
    _loadSchedules();
  }

  @override
  void dispose() {
    _lateAfterMinutesController.dispose();
    _scheduleSearchController.dispose();
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
          'course,year_level,subject,weekday,start_time,late_after,end_time,teacher_email,campus_code\r\n',
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
        // The code leads ("BSIT"), with the full name under it in small
        // type. The full name alone ran off the edge of a phone.
        title: widget.course == null
            ? const Text('Departments & courses')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    courseCode ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    widget.course!['course_name']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
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

  // ── Layout helpers ────────────────────────────────────────────────

  /// How many columns of cards fit: three on a wide laptop, two on a small
  /// window or tablet, one on a phone.
  int _columnsFor(double width) => width >= 1000
      ? 3
      : width >= 640
      ? 2
      : 1;

  /// Lays [items] out in [columns] equal columns, in reading order.
  Widget _grid(int columns, List<Widget> items) {
    if (columns == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: item,
            ),
        ],
      );
    }
    final lanes = List.generate(columns, (_) => <Widget>[]);
    for (var i = 0; i < items.length; i++) {
      lanes[i % columns].add(
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.md),
          child: items[i],
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var c = 0; c < columns; c++) ...[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: lanes[c],
            ),
          ),
          if (c != columns - 1) const SizedBox(width: AppSpace.md),
        ],
      ],
    );
  }

  /// Chips in one line that scrolls sideways on a narrow screen. Wrapped,
  /// "Year 3" and "Year 4" dropped to a second line on a phone.
  Widget _chipRow(List<Widget> chips) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (var i = 0; i < chips.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpace.sm),
          chips[i],
        ],
      ],
    ),
  );

  /// Keeps a page to a readable width on a laptop and centres it.
  Widget _page(Widget child) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1200),
      child: child,
    ),
  );

  static const _smallWords = {
    'a', 'an', 'and', 'as', 'at', 'by', 'for', 'in', 'of', 'on', 'or', 'the',
    'to', 'with', 'incl.', '(incl.',
  };
  static const _keepUpper = {
    'HCI', 'IT', 'PE', 'NSTP', 'MICE', 'ABM', 'UI', 'UX', 'NC', 'II', 'III',
    'IV', 'TPS', 'FOS', 'FO', 'HRM',
  };

  /// The stored subject is in capitals ("CC101 COMPUTER PROGRAMMING 1").
  /// Splits off the code and gives the name ordinary capitals:
  /// ("CC101", "Computer Programming 1").
  (String, String) _splitSubject(String subject) {
    final words = subject.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || words.first.isEmpty) return ('', subject);
    var codeLength = 0;
    if (RegExp(r'^[A-Z]{2,}[A-Z-]*\d+[A-Z]?$').hasMatch(words.first)) {
      codeLength = 1;
    } else if (words.length > 1 &&
        RegExp(r'^[A-Z]{2,}$').hasMatch(words[0]) &&
        RegExp(r'^\d+$').hasMatch(words[1])) {
      codeLength = 2; // "NSTP 1"
    }
    final code = words.take(codeLength).join(' ');
    final rest = words.skip(codeLength).toList();
    final name = [
      for (var i = 0; i < rest.length; i++) _niceWord(rest[i], i == 0),
    ].join(' ');
    return (code, name.isEmpty ? subject : name);
  }

  String _niceWord(String word, bool first) {
    final bare = word.replaceAll(RegExp(r'[^A-Za-z]'), '');
    if (_keepUpper.contains(bare.toUpperCase()) && bare == bare.toUpperCase()) {
      return word;
    }
    if (RegExp(r'\d').hasMatch(word)) return word.toUpperCase(); // "3D"
    final lower = word.toLowerCase();
    if (!first && _smallWords.contains(lower)) return lower;
    // The first letter, not the first character: "(MEETING," becomes
    // "(Meeting,", not "(meeting,".
    return lower
        .split('-')
        .map(
          (p) => p.replaceFirstMapped(
            RegExp('[a-z]'),
            (m) => m[0]!.toUpperCase(),
          ),
        )
        .join('-');
  }

  // ── Departments & courses ─────────────────────────────────────────

  Widget _buildCoursesBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load courses',
        message: _error,
        action: OutlinedButton(
          onPressed: _loadSchedules,
          child: const Text('Try again'),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadSchedules,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pad = constraints.maxWidth < 400 ? AppSpace.md : AppSpace.xl;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(pad, AppSpace.md, pad, 96),
            children: [
              _page(
                LayoutBuilder(
                  builder: (context, inner) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Reveal(order: 0, child: _buildTermControls()),
                      const SizedBox(height: AppSpace.md),
                      Reveal(order: 1, child: _wholeSchoolPanel()),
                      const SizedBox(height: AppSpace.lg),
                      Reveal(order: 2, child: _buildDepartmentFilter()),
                      ..._buildCourseGroups(inner.maxWidth),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _wholeSchoolPanel() {
    final theme = Theme.of(context);
    final canUpload = !_isUploading && _selectedTermIsCurrent;
    return AppPanel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.block),
            ),
            child: Icon(
              Icons.calendar_month_outlined,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Whole-school timetable',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'One file for every course. Each row needs its course and '
                  'campus code, and each course must be added below first.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                      onPressed: canUpload ? _uploadSchedule : null,
                      icon: _isUploading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.upload_file, size: 18),
                      label: Text(_isUploading ? 'Uploading...' : 'Upload'),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: canUpload ? _downloadScheduleTemplate : null,
                        icon: const Icon(Icons.download_outlined, size: 18),
                        label: const Text('Template'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDepartmentFilter() {
    final theme = Theme.of(context);
    final unassigned = _courses
        .where((course) => course['department_id'] == null)
        .length;

    Widget chip(String value, String label) => ChoiceChip(
      label: Text(label),
      selected: _selectedDepartment == value,
      onSelected: (_) => setState(() => _selectedDepartment = value),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Courses',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _isUploading ? null : _manageDepartments,
              icon: const Icon(Icons.apartment_outlined, size: 18),
              label: const Text('Departments'),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        _chipRow([
          chip('all', 'All (${_courses.length})'),
          for (final item in _departments)
            chip(
              item['id'].toString(),
              '${item['department_code']} (${item['course_count'] ?? 0})',
            ),
          if (unassigned > 0) chip('none', 'No department ($unassigned)'),
        ]),
      ],
    );
  }

  // Courses grouped under their department (filtered by the chips above).
  List<Widget> _buildCourseGroups(double width) {
    final theme = Theme.of(context);
    final courses = _courses
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();

    if (_departments.isEmpty && courses.isEmpty) {
      return const [
        SizedBox(height: AppSpace.xl),
        EmptyState(
          icon: Icons.apartment_outlined,
          title: 'No departments or courses yet',
          message: 'Tap "Departments" to add one, then add its courses.',
        ),
      ];
    }

    final columns = _columnsFor(width);
    final widgets = <Widget>[];
    var order = 3;
    void addGroup(String name, String code, List<Map<String, dynamic>> group) {
      final classes = group.fold<num>(
        0,
        (sum, c) => sum + (c['schedule_count'] as num? ?? 0),
      );
      widgets.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(0, AppSpace.xl, 0, AppSpace.md),
          child: Row(
            children: [
              if (code.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    code,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${group.length} ${group.length == 1 ? 'course' : 'courses'}'
                      '  ·  $classes ${classes == 1 ? 'class' : 'classes'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
      widgets.add(
        Reveal(
          order: order++,
          child: group.isEmpty
              ? Text(
                  'No courses yet. Tap "Add course" to add one.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : _grid(columns, group.map(_buildCourseTile).toList()),
        ),
      );
    }

    for (final item in _departments) {
      final department = Map<String, dynamic>.from(item as Map);
      final id = department['id'].toString();
      if (_selectedDepartment != 'all' && _selectedDepartment != id) continue;
      addGroup(
        department['department_name']?.toString() ?? '',
        department['department_code']?.toString() ?? '',
        courses.where((c) => c['department_id']?.toString() == id).toList(),
      );
    }

    if (_selectedDepartment == 'all' || _selectedDepartment == 'none') {
      final unassigned = courses
          .where((c) => c['department_id'] == null)
          .toList();
      if (unassigned.isNotEmpty) addGroup('No department', '', unassigned);
    }
    return widgets;
  }

  Widget _buildCourseTile(Map<String, dynamic> course) {
    final theme = Theme.of(context);
    final scheduleCount = (course['schedule_count'] as num? ?? 0).toInt();
    final code = course['course_code']?.toString() ?? '';
    Future<void> open() async {
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
    }

    final empty = scheduleCount == 0;
    return Hoverable(
      onTap: open,
      builder: (context, hovered) => AppPanel(
        hovered: hovered,
        padding: const EdgeInsets.fromLTRB(
          AppSpace.md,
          AppSpace.md,
          AppSpace.xs,
          AppSpace.md,
        ),
        child: Row(
          children: [
            // The code is what people say ("BSIT"), so it leads.
            Container(
              width: 64,
              height: 52,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadius.block),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  code,
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    course['course_name']?.toString() ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Row(
                    children: [
                      Icon(
                        empty
                            ? Icons.event_busy_outlined
                            : Icons.event_note_outlined,
                        size: 14,
                        color: empty
                            ? StatusTone.forLevel(
                                context,
                                StatusLevel.caution,
                              ).content
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        empty
                            ? 'No classes yet'
                            : '$scheduleCount ${scheduleCount == 1 ? 'class' : 'classes'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: empty
                              ? StatusTone.forLevel(
                                  context,
                                  StatusLevel.caution,
                                ).content
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
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
          ],
        ),
      ),
    );
  }

  /// "2026-2027 • 1st Semester (Current)".
  String _termLabel(Map<String, dynamic> term) =>
      '${term['school_year']} • ${term['semester']}'
      '${term['is_current'] == true ? ' (Current)' : ''}';

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
    return AppPanel(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, 6, AppSpace.xs, 6),
      child: Row(
        children: [
          Icon(
            Icons.school_outlined,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: _terms.isEmpty
                ? Text(
                    selectedLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : DropdownButtonFormField<String>(
                    initialValue: _selectedTermId,
                    // Without this the closed field takes the width of the
                    // longest term in the list, which on a phone runs under
                    // the two buttons beside it.
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Academic term',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    selectedItemBuilder: (context) => _terms.map((item) {
                      final term = Map<String, dynamic>.from(item as Map);
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _termLabel(term),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      );
                    }).toList(),
                    items: _terms.map((item) {
                      final term = Map<String, dynamic>.from(item as Map);
                      return DropdownMenuItem(
                        value: term['id'].toString(),
                        child: Text(
                          _termLabel(term),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: _isUploading || _isLoading ? null : _selectTerm,
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
            onPressed: _isUploading || _isLoading ? null : _createAcademicTerm,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }

  // ── One course's week ─────────────────────────────────────────────

  Future<void> _showUploadHelp() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('How to upload'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'A CSV or Excel file, one row per class, with these columns:',
                ),
                const SizedBox(height: AppSpace.sm),
                const SelectableText(
                  'course, year_level, subject, weekday, start_time, '
                  'late_after, end_time, teacher_email, campus_code',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                const SizedBox(height: AppSpace.md),
                const Text(
                  'campus_code must match a campus that has a boundary. The '
                  'registrar\'s year-by-year timetable can also be uploaded '
                  'as it is; then the late cutoff below is used.',
                  style: TextStyle(height: 1.4),
                ),
                const SizedBox(height: AppSpace.lg),
                TextField(
                  enabled: _selectedTermIsCurrent,
                  controller: _lateAfterMinutesController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Late cutoff (minutes)',
                    helperText: 'For the registrar\'s timetable; default 30.',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: _isUploading || !_selectedTermIsCurrent
                ? null
                : () {
                    Navigator.pop(dialogContext);
                    _downloadScheduleTemplate();
                  },
            icon: const Icon(Icons.download_outlined),
            label: const Text('CSV template'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  /// One class in a day: the time on the left, the subject and its details
  /// on the right.
  Widget _classRow(Map<String, dynamic> schedule, {required bool showYear}) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final (code, name) = _splitSubject(schedule['subject']?.toString() ?? '');
    final campus = schedule['campus_name']?.toString() ?? 'No campus';
    final teacher =
        schedule['teacher_name']?.toString() ??
        schedule['teacher_email']?.toString() ??
        '';
    final caution = StatusTone.forLevel(context, StatusLevel.caution).content;

    Widget detail(IconData icon, String text) => Row(
      children: [
        Icon(icon, size: 13, color: muted),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatTime(schedule['start_time']),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  _formatTime(schedule['end_time']),
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
          Container(
            width: 3,
            height: 72,
            margin: const EdgeInsets.only(right: AppSpace.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (code.isNotEmpty)
                  Text(
                    showYear
                        ? '$code  ·  Year ${schedule['year_level']}'
                        : code,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 4),
                // One detail per line, in the same order for every class.
                // Wrapped side by side, they broke at different places on
                // each card and nothing lined up.
                detail(Icons.location_on_outlined, campus),
                const SizedBox(height: 2),
                detail(
                  Icons.person_outline_rounded,
                  teacher.isEmpty ? 'No teacher yet' : teacher,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.schedule_rounded, size: 13, color: caution),
                    const SizedBox(width: 4),
                    Text(
                      'Late after ${_formatTime(schedule['late_after'])}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: caution,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Class options',
            enabled: !_isUploading && !_isLoading && _selectedTermIsCurrent,
            padding: EdgeInsets.zero,
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
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Edit'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline, color: Colors.red),
                  title: Text('Delete'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// One day of the week as a panel: its name, how many classes, and the
  /// classes in time order.
  Widget _dayPanel(
    String day,
    List<Map<String, dynamic>> classes, {
    required bool showYear,
  }) {
    final theme = Theme.of(context);
    return AppPanel(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.md,
        AppSpace.xs,
        AppSpace.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpace.md),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    day,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    '${classes.length} ${classes.length == 1 ? 'class' : 'classes'}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          for (var i = 0; i < classes.length; i++) ...[
            if (i > 0) Divider(height: 1, color: theme.dividerColor),
            _classRow(classes[i], showYear: showYear),
          ],
        ],
      ),
    );
  }

  Widget _buildSchedulesBody() {
    final theme = Theme.of(context);
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
    final selectedYear = years.contains(_selectedYear) ? _selectedYear : 'all';
    String dayName(dynamic value) {
      final day = (value as num?)?.toInt() ?? -1;
      return day >= 0 && day < _weekdays.length ? _weekdays[day] : '';
    }

    final dayOptions = [
      for (final day in [1, 2, 3, 4, 5, 6, 0])
        if (_schedules.any((s) => (s['weekday'] as num?)?.toInt() == day))
          _weekdays[day],
    ];
    final campusOptions = {
      for (final s in _schedules)
        if ((s['campus_name']?.toString() ?? '').isNotEmpty)
          s['campus_name'].toString(),
    }.toList()..sort();
    final selectedDay = dayOptions.contains(_selectedDay)
        ? _selectedDay
        : _anyDay;
    final selectedCampus = campusOptions.contains(_selectedCampus)
        ? _selectedCampus
        : _anyCampus;
    final query = _scheduleSearch.trim().toLowerCase();

    // A class is shown when it passes every filter and, if something is
    // typed, its subject, code, teacher or campus contains it.
    final filtered = _schedules.where((s) {
      if (selectedYear != 'all' && s['year_level']?.toString() != selectedYear) {
        return false;
      }
      if (selectedDay != _anyDay && dayName(s['weekday']) != selectedDay) {
        return false;
      }
      if (selectedCampus != _anyCampus &&
          s['campus_name']?.toString() != selectedCampus) {
        return false;
      }
      if (query.isEmpty) return true;
      final haystack = [
        s['subject'],
        s['teacher_name'],
        s['teacher_email'],
        s['campus_name'],
        dayName(s['weekday']),
      ].map((v) => (v ?? '').toString().toLowerCase()).join(' ');
      return haystack.contains(query);
    }).toList();

    // Monday first, Sunday last, the way a school week is read.
    final byDay = <int, List<Map<String, dynamic>>>{};
    for (final item in filtered) {
      final schedule = Map<String, dynamic>.from(item as Map);
      final day = (schedule['weekday'] as num?)?.toInt() ?? -1;
      byDay.putIfAbsent(day, () => []).add(schedule);
    }
    for (final list in byDay.values) {
      list.sort(
        (a, b) => (a['start_time']?.toString() ?? '').compareTo(
          b['start_time']?.toString() ?? '',
        ),
      );
    }
    final dayOrder = [1, 2, 3, 4, 5, 6, 0, -1]
        .where(byDay.containsKey)
        .toList();

    final search = TextField(
      controller: _scheduleSearchController,
      onChanged: (value) => setState(() => _scheduleSearch = value),
      decoration: InputDecoration(
        hintText: 'Search subject, code or teacher',
        prefixIcon: const Icon(Icons.search),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.block),
        ),
        suffixIcon: _scheduleSearch.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.clear),
                onPressed: () => setState(() {
                  _scheduleSearch = '';
                  _scheduleSearchController.clear();
                }),
              ),
      ),
    );

    // The same filters as User Management: all in one line on a laptop; on
    // a phone the year stays out and the rest open from "Filters".
    final yearOptions = ['All years', for (final year in years) 'Year $year'];
    final filters = years.isEmpty && dayOptions.isEmpty
        ? const SizedBox.shrink()
        : FilterBar(
            // Folded on a laptop too, the same as on a phone.
            foldOnWide: true,
            children: [
              FilterDropdown(
                value: selectedYear == 'all' ? 'All years' : 'Year $selectedYear',
                options: yearOptions,
                icon: Icons.school_outlined,
                onChanged: (chosen) => setState(
                  () => _selectedYear = chosen == 'All years'
                      ? 'all'
                      : chosen.replaceFirst('Year ', ''),
                ),
              ),
              FilterDropdown(
                value: selectedDay,
                options: [_anyDay, ...dayOptions],
                icon: Icons.calendar_today_outlined,
                onChanged: (chosen) => setState(() => _selectedDay = chosen),
              ),
              FilterDropdown(
                value: selectedCampus,
                options: [_anyCampus, ...campusOptions],
                icon: Icons.location_on_outlined,
                onChanged: (chosen) => setState(() => _selectedCampus = chosen),
              ),
            ],
          );

    final actions = Wrap(
          spacing: AppSpace.xs,
          children: [
            TextButton.icon(
              onPressed: _showUploadHelp,
              icon: const Icon(Icons.help_outline_rounded, size: 18),
              label: const Text('How to upload'),
            ),
            if (_schedules.isNotEmpty)
              TextButton.icon(
                onPressed: _isUploading || _isLoading
                    ? null
                    : _archiveAllSchedules,
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('Delete all'),
              ),
          ],
        );
    // Laptop: the search and the two actions on one line, the filters
    // under them. Phone: search, filters, then the actions.
    final toolbar = LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= 640
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: search),
                    const SizedBox(width: AppSpace.md),
                    actions,
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
                filters,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                const SizedBox(height: AppSpace.sm),
                filters,
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            ),
    );

    Widget content;
    if (_isLoading) {
      content = const Padding(
        padding: EdgeInsets.only(top: 80),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_error.isNotEmpty) {
      content = EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load the classes',
        message: _error,
        action: OutlinedButton(
          onPressed: _loadSchedules,
          child: const Text('Try again'),
        ),
      );
    } else if (_schedules.isEmpty) {
      content = const EmptyState(
        icon: Icons.event_note_outlined,
        title: 'No classes yet',
        message: 'Tap "Upload timetable" to add this course\'s week.',
      );
    } else if (filtered.isEmpty) {
      content = EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No classes match',
        message: query.isEmpty
            ? 'Try other filters.'
            : 'Nothing matches "${_scheduleSearch.trim()}". Check the '
                  'spelling or clear the filters.',
      );
    } else {
      content = LayoutBuilder(
        builder: (context, constraints) => _grid(
          _columnsFor(constraints.maxWidth),
          [
            for (final day in dayOrder)
              _dayPanel(
                day >= 0 && day < _weekdays.length
                    ? _weekdays[day]
                    : 'Unknown day',
                byDay[day]!,
                showYear: selectedYear == 'all',
              ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSchedules,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pad = constraints.maxWidth < 400 ? AppSpace.md : AppSpace.xl;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(pad, AppSpace.md, pad, 96),
            children: [
              _page(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Reveal(order: 0, child: _buildTermControls()),
                    if (!_selectedTermIsCurrent)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpace.sm),
                        child: Text(
                          'An earlier term: uploads and edits are turned off.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    const SizedBox(height: AppSpace.md),
                    Reveal(order: 1, child: toolbar),
                    const SizedBox(height: AppSpace.md),
                    Reveal(order: 2, child: content),
                  ],
                ),
              ),
            ],
          );
        },
      ),
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
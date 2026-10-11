import 'package:flutter/material.dart';

import '../services/api_service.dart';

/// Admin: manage the departments that group the courses (add, edit, delete).
class AdminDepartmentsScreen extends StatefulWidget {
  final String token;

  const AdminDepartmentsScreen({super.key, required this.token});

  @override
  State<AdminDepartmentsScreen> createState() => _AdminDepartmentsScreenState();
}

class _AdminDepartmentsScreenState extends State<AdminDepartmentsScreen> {
  bool _isLoading = true;
  bool _isBusy = false;
  String _error = '';
  List<Map<String, dynamic>> _departments = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await ApiService.getDepartments(token: widget.token);
      if (!mounted) return;
      setState(() {
        _departments = (result['departments'] as List<dynamic>? ?? [])
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

  Future<void> _addDepartment() async {
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _DepartmentFormDialog(),
    );
    if (!mounted || values == null) return;
    await _run(
      () => ApiService.addDepartment(
        token: widget.token,
        departmentCode: values['code']!,
        departmentName: values['name']!,
      ),
      'Department added.',
    );
  }

  Future<void> _editDepartment(Map<String, dynamic> department) async {
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _DepartmentFormDialog(existing: department),
    );
    if (!mounted || values == null) return;
    await _run(
      () => ApiService.updateDepartment(
        token: widget.token,
        departmentId: department['id'].toString(),
        departmentCode: values['code']!,
        departmentName: values['name']!,
      ),
      'Department updated.',
    );
  }

  Future<void> _deleteDepartment(Map<String, dynamic> department) async {
    var answered = false; // ignore a second tap while the box is closing
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete department'),
        content: Text(
          'Delete ${department['department_name']} (${department['department_code']})? '
          'A department that still has courses cannot be deleted.',
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
      () => ApiService.deleteDepartment(
        token: widget.token,
        departmentId: department['id'].toString(),
      ),
      'Department deleted.',
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
    if (_departments.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No departments yet. Add a department, then add its courses.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        itemCount: _departments.length,
        itemBuilder: (context, index) {
          final department = _departments[index];
          final courseCount = (department['course_count'] as num?)?.toInt() ?? 0;
          return Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.apartment)),
              title: Text(department['department_name']?.toString() ?? ''),
              subtitle: Text(
                '${department['department_code']} • $courseCount ${courseCount == 1 ? 'course' : 'courses'}',
              ),
              trailing: PopupMenuButton<String>(
                tooltip: 'Department options',
                enabled: !_isBusy,
                onSelected: (value) {
                  if (value == 'edit') {
                    _editDepartment(department);
                  } else {
                    _deleteDepartment(department);
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
      appBar: AppBar(title: const Text('Departments')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isBusy ? null : _addDepartment,
        icon: const Icon(Icons.add),
        label: const Text('Add department'),
      ),
      body: _buildBody(),
    );
  }
}

/// Add / edit form for a department. Returns {'code': ..., 'name': ...}.
class _DepartmentFormDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;

  const _DepartmentFormDialog({this.existing});

  @override
  State<_DepartmentFormDialog> createState() => _DepartmentFormDialogState();
}

class _DepartmentFormDialogState extends State<_DepartmentFormDialog> {
  late final TextEditingController _codeController = TextEditingController(
    text: widget.existing?['department_code']?.toString() ?? '',
  );
  late final TextEditingController _nameController = TextEditingController(
    text: widget.existing?['department_name']?.toString() ?? '',
  );
  final _formKey = GlobalKey<FormState>();
  bool _submitted = false;

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
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit department' : 'Add department'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Department code',
                hintText: 'e.g. CCS',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a department code.'
                  : null,
            ),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Department name',
                hintText: 'e.g. College of Computer Studies',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a department name.'
                  : null,
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
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
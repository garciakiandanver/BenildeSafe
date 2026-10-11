import 'package:flutter/material.dart';
import '../services/api_service.dart';

class AdminUsersScreen extends StatefulWidget {
  final String token;

  const AdminUsersScreen({super.key, required this.token});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _isLoading = true;
  String _error = '';

  List<dynamic> _students = [];
  List<dynamic> _teachers = [];
  List<dynamic> _parents = [];

  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _searchQuery = '';
        _searchController.clear();
      });
    });
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    try {
      final students = await ApiService.getAdminStudents(token: widget.token);
      final teachers = await ApiService.getAdminTeachers(token: widget.token);
      final parents = await ApiService.getAdminParents(token: widget.token);

      if (!mounted) return;
      setState(() {
        _students = students['students'] ?? [];
        _teachers = teachers['teachers'] ?? [];
        _parents = parents['parents'] ?? [];
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

  Future<void> _editUser(Map<String, dynamic> user, String role) async {
    final fields = <({String key, String label, bool required})>[
      (key: 'email', label: 'Email', required: true),
      (key: 'first_name', label: 'First name', required: true),
      (key: 'middle_name', label: 'Middle name', required: false),
      (key: 'last_name', label: 'Last name', required: true),
      if (role == 'Student') ...[
        (key: 'student_number', label: 'Student number', required: true),
        (key: 'course', label: 'Course', required: true),
        (key: 'year_level', label: 'Year level', required: true),
        (key: 'section', label: 'Section', required: false),
      ] else if (role == 'Teacher')
        (key: 'employee_number', label: 'Employee number', required: true)
      else
        (key: 'contact_number', label: 'Contact number', required: false),
    ];
    final controllers = {
      for (final field in fields)
        field.key: TextEditingController(
          text: user[field.key]?.toString() ?? '',
        ),
    };
    final formKey = GlobalKey<FormState>();
    try {
      final values = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Edit $role'),
          content: SizedBox(
            width: 440,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: fields.map((field) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextFormField(
                        controller: controllers[field.key],
                        keyboardType: field.key == 'email'
                            ? TextInputType.emailAddress
                            : TextInputType.text,
                        decoration: InputDecoration(labelText: field.label),
                        validator: (value) {
                          final text = value?.trim() ?? '';
                          if (field.required && text.isEmpty) {
                            return '${field.label} is required.';
                          }
                          if (field.key == 'email' &&
                              !RegExp(
                                r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                              ).hasMatch(text)) {
                            return 'Enter a valid email address.';
                          }
                          return null;
                        },
                      ),
                    );
                  }).toList(),
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
                  for (final field in fields)
                    field.key: controllers[field.key]!.text.trim(),
                });
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (!mounted || values == null) return;
      setState(() => _isLoading = true);
      final result = await ApiService.updateManagedUser(
        token: widget.token,
        userId: user['user_id'].toString(),
        user: values,
      );
      await _loadAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']?.toString() ?? 'User updated.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      for (final controller in controllers.values) {
        controller.dispose();
      }
    }
  }

  Future<void> _changeUserStatus(Map<String, dynamic> user) async {
    final isActive = user['status'] == 'active';
    final nextStatus = isActive ? 'inactive' : 'active';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isActive ? 'Deactivate account?' : 'Reactivate account?'),
        content: Text(
          isActive
              ? 'Deactivate ${_getFullName(user)}? Their attendance and profile history will be preserved.'
              : 'Reactivate ${_getFullName(user)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(isActive ? 'Deactivate' : 'Reactivate'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    try {
      setState(() => _isLoading = true);
      final result = await ApiService.setManagedUserStatus(
        token: widget.token,
        userId: user['user_id'].toString(),
        status: nextStatus,
      );
      await _loadAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ??
                (isActive ? 'Account deactivated.' : 'Account reactivated.'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _manageParentChildren(Map<String, dynamic> parent) async {
    final studentNumberController = TextEditingController();
    var isSaving = false;
    var message = '';
    var hasError = false;

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, dialogSetState) {
            final linkedStudents = _students
                .where((student) => student['parent_id'] == parent['id'])
                .toList();

            Future<void> refresh() async {
              await _loadAll();
              if (dialogContext.mounted) dialogSetState(() {});
            }

            Future<void> linkStudent() async {
              final studentNumber = studentNumberController.text.trim();
              if (studentNumber.isEmpty) {
                dialogSetState(() {
                  message = 'Enter the student ID.';
                  hasError = true;
                });
                return;
              }
              dialogSetState(() {
                isSaving = true;
                message = '';
              });
              try {
                final result = await ApiService.linkParentChild(
                  token: widget.token,
                  parentId: parent['id'].toString(),
                  studentNumber: studentNumber,
                );
                await refresh();
                if (!dialogContext.mounted) return;
                studentNumberController.clear();
                dialogSetState(() {
                  message = result['message']?.toString() ??
                      'Student linked successfully.';
                  hasError = false;
                });
              } catch (error) {
                if (!dialogContext.mounted) return;
                dialogSetState(() {
                  message = error.toString().replaceFirst('Exception: ', '');
                  hasError = true;
                });
              } finally {
                if (dialogContext.mounted) {
                  dialogSetState(() => isSaving = false);
                }
              }
            }

            Future<void> unlinkStudent(Map<String, dynamic> student) async {
              dialogSetState(() {
                isSaving = true;
                message = '';
              });
              try {
                final result = await ApiService.unlinkParentChild(
                  token: widget.token,
                  parentId: parent['id'].toString(),
                  studentId: student['id'].toString(),
                );
                await refresh();
                if (!dialogContext.mounted) return;
                dialogSetState(() {
                  message = result['message']?.toString() ??
                      'Student unlinked successfully.';
                  hasError = false;
                });
              } catch (error) {
                if (!dialogContext.mounted) return;
                dialogSetState(() {
                  message = error.toString().replaceFirst('Exception: ', '');
                  hasError = true;
                });
              } finally {
                if (dialogContext.mounted) {
                  dialogSetState(() => isSaving = false);
                }
              }
            }

            return AlertDialog(
              title: Text('Children of ${_getFullName(parent)}'),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (linkedStudents.isEmpty)
                        const Text('No children are linked to this parent yet.')
                      else ...[
                        const Text(
                          'Linked students',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        ...linkedStudents.map(
                          (student) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(_getFullName(student)),
                            subtitle: Text(
                              student['student_number']?.toString() ?? '',
                            ),
                            trailing: IconButton(
                              tooltip: 'Unlink student',
                              onPressed: isSaving
                                  ? null
                                  : () => unlinkStudent(
                                      Map<String, dynamic>.from(student as Map),
                                    ),
                              icon: const Icon(
                                Icons.link_off,
                                color: Colors.red,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const Divider(height: 24),
                      TextField(
                        controller: studentNumberController,
                        enabled: !isSaving,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Student ID',
                          hintText: 'e.g. BSIT-2023-01-00001',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Student ID matching ignores letter case.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      if (message.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          message,
                          style: TextStyle(
                            color: hasError ? Colors.red : Colors.green,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: const Text('Close'),
                ),
                FilledButton.icon(
                  onPressed: isSaving ? null : linkStudent,
                  icon: const Icon(Icons.link),
                  label: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Link student'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      studentNumberController.dispose();
    }
  }

  Widget _buildUserActions(Map<String, dynamic> user, String role) {
    final isActive = user['status'] == 'active';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildStatusBadge(user['status']?.toString()),
        if (role == 'Parent')
          IconButton(
            tooltip: 'Manage linked children',
            onPressed: () => _manageParentChildren(user),
            icon: const Icon(Icons.family_restroom),
          ),
        PopupMenuButton<String>(
          tooltip: 'Manage user',
          onSelected: (action) {
            if (action == 'edit') {
              _editUser(user, role);
            } else {
              _changeUserStatus(user);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: ListTile(
                leading: Icon(Icons.edit_outlined),
                title: Text('Edit profile'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: isActive ? 'deactivate' : 'activate',
              child: ListTile(
                leading: Icon(
                  isActive ? Icons.person_off_outlined : Icons.person_outlined,
                ),
                title: Text(isActive ? 'Deactivate' : 'Reactivate'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _getFullName(dynamic user) {
    final first = user['first_name'] ?? '';
    final middle = user['middle_name'] ?? '';
    final last = user['last_name'] ?? '';
    if (middle.isEmpty) return '$first $last';
    return '$first $middle $last';
  }

  Widget _buildStatusBadge(String? status) {
    final isActive = status == 'active';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isActive ? Colors.green : Colors.red,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status?.toUpperCase() ?? '--',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search...',
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
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
    );
  }

  List<dynamic> _filterStudents() {
    if (_searchQuery.isEmpty) return _students;
    return _students.where((s) {
      return _getFullName(s).toLowerCase().contains(_searchQuery) ||
          (s['student_number'] ?? '').toLowerCase().contains(_searchQuery) ||
          (s['email'] ?? '').toLowerCase().contains(_searchQuery) ||
          (s['course'] ?? '').toLowerCase().contains(_searchQuery);
    }).toList();
  }

  List<dynamic> _filterTeachers() {
    if (_searchQuery.isEmpty) return _teachers;
    return _teachers.where((t) {
      return _getFullName(t).toLowerCase().contains(_searchQuery) ||
          (t['employee_number'] ?? '').toLowerCase().contains(_searchQuery) ||
          (t['email'] ?? '').toLowerCase().contains(_searchQuery);
    }).toList();
  }

  List<dynamic> _filterParents() {
    if (_searchQuery.isEmpty) return _parents;
    return _parents.where((p) {
      return _getFullName(p).toLowerCase().contains(_searchQuery) ||
          (p['contact_number'] ?? '').toLowerCase().contains(_searchQuery) ||
          (p['email'] ?? '').toLowerCase().contains(_searchQuery);
    }).toList();
  }

  Widget _buildStudentsTab() {
    final filtered = _filterStudents();
    return Column(
      children: [
        _buildSearchBar(),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No students found.'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final s = filtered[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.school)),
                        title: Text(
                          _getFullName(s),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${s['student_number']} • ${s['course']} ${s['year_level']}-${s['section']}\n${s['email']}',
                        ),
                        trailing: _buildUserActions(
                          Map<String, dynamic>.from(s as Map),
                          'Student',
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTeachersTab() {
    final filtered = _filterTeachers();
    return Column(
      children: [
        _buildSearchBar(),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No teachers found.'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final t = filtered[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(
                          _getFullName(t),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${t['employee_number']}\n${t['email']}',
                        ),
                        trailing: _buildUserActions(
                          Map<String, dynamic>.from(t as Map),
                          'Teacher',
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildParentsTab() {
    final filtered = _filterParents();
    return Column(
      children: [
        _buildSearchBar(),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No parents found.'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final p = filtered[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.family_restroom),
                        ),
                        title: Text(
                          _getFullName(p),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${p['contact_number'] ?? 'No contact'} • ${p['children_count']} child(ren)\n${p['email']}',
                        ),
                        trailing: _buildUserActions(
                          Map<String, dynamic>.from(p as Map),
                          'Parent',
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Management'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Students (${_students.length})'),
            Tab(text: 'Teachers (${_teachers.length})'),
            Tab(text: 'Parents (${_parents.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? Center(child: Text(_error))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildStudentsTab(),
                _buildTeachersTab(),
                _buildParentsTab(),
              ],
            ),
    );
  }
}

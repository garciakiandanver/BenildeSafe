import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/app_ui.dart';

class AdminUsersScreen extends StatefulWidget {
  final String token;

  /// Which tab to open on: 0 students, 1 teachers, 2 parents.
  ///
  /// The dashboard sends the reader straight to the people they pressed on,
  /// rather than to the students tab and a second press.
  final int initialTab;

  const AdminUsersScreen({
    super.key,
    required this.token,
    this.initialTab = 0,
  });

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

  // Filtering and sorting happen here, on the accounts already loaded, so
  // changing one costs no round trip. They reset when the tab changes, the
  // same way the search box already did.
  static const String _anyStatus = 'Any status';
  static const String _anyDepartment = 'All departments';
  static const String _anyCourse = 'All courses';
  static const String _anyYear = 'All year levels';

  static const String _sortNameAZ = 'Name A–Z';
  static const String _sortNameZA = 'Name Z–A';
  static const String _sortStatus = 'Active first';

  // Each tab calls its number by its own name. "ID number" meant nothing in
  // particular on any of the three.
  static const String _sortStudentNumber = 'Student number';
  static const String _sortEmployeeNumber = 'Employee number';

  static const List<String> _studentSortModes = [
    _sortNameAZ,
    _sortNameZA,
    _sortStudentNumber,
    _sortStatus,
  ];

  static const List<String> _teacherSortModes = [
    _sortNameAZ,
    _sortNameZA,
    _sortEmployeeNumber,
    _sortStatus,
  ];

  // A parent has neither, so that way of sorting is left out here rather than
  // offered and quietly doing nothing.
  static const List<String> _parentSortModes = [
    _sortNameAZ,
    _sortNameZA,
    _sortStatus,
  ];

  String _statusFilter = _anyStatus;
  String _departmentFilter = _anyDepartment;
  String _courseFilter = _anyCourse;
  String _yearFilter = _anyYear;
  String _sortMode = _sortNameAZ;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2),
    );
    _tabController.addListener(() {
      setState(() {
        _searchQuery = '';
        _searchController.clear();
        _statusFilter = _anyStatus;
        _departmentFilter = _anyDepartment;
        _courseFilter = _anyCourse;
        _yearFilter = _anyYear;
        _sortMode = _sortNameAZ;
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


  // Teachers are added one at a time here. Students and parents come from the
  // registrar's master list through the bulk import, and nobody can create an
  // account for themselves any more.
  Future<void> _addTeacher() async {
    final fields = <({String key, String label, bool required})>[
      (key: 'first_name', label: 'First name', required: true),
      (key: 'middle_name', label: 'Middle name', required: false),
      (key: 'last_name', label: 'Last name', required: true),
      (key: 'email', label: 'Email', required: true),
      (key: 'employee_number', label: 'Employee number', required: true),
    ];
    final controllers = {
      for (final field in fields) field.key: TextEditingController(),
    };
    final formKey = GlobalKey<FormState>();
    try {
      final values = await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Add teacher'),
          content: SizedBox(
            width: 440,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...fields.map(
                      (field) => Padding(
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
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'The teacher receives an email with a temporary password '
                      'and is asked to set their own password the first time '
                      'they sign in.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
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
                  for (final field in fields)
                    field.key: controllers[field.key]!.text.trim(),
                });
              },
              child: const Text('Add teacher'),
            ),
          ],
        ),
      );
      if (!mounted || values == null) return;
      setState(() => _isLoading = true);
      final result = await ApiService.addTeacher(
        token: widget.token,
        firstName: values['first_name']!,
        middleName: values['middle_name']!,
        lastName: values['last_name']!,
        email: values['email']!,
        employeeNumber: values['employee_number']!,
      );
      await _loadAll();
      if (!mounted) return;
      final emailFailed = result['email_sent'] == false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            [
              result['message']?.toString() ?? 'Teacher added.',
              if (emailFailed) result['email_error']?.toString() ?? '',
            ].where((line) => line.isNotEmpty).join(' '),
          ),
          backgroundColor: emailFailed ? Colors.orange.shade800 : null,
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
              // Unlinking takes the child away from the parent's app at once
              // and stops their notifications, so it is asked about first,
              // the same as deactivating an account.
              final studentName = _getFullName(student).trim();
              final parentName = _getFullName(parent).trim();
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (confirmContext) {
                  final scheme = Theme.of(confirmContext).colorScheme;
                  return AlertDialog(
                    title: const Text('Unlink student?'),
                    content: Text(
                      '$parentName will no longer see $studentName\'s '
                      'attendance or get notifications about them. You can '
                      'link them again later.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(confirmContext, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: scheme.error,
                          foregroundColor: scheme.onError,
                        ),
                        onPressed: () => Navigator.pop(confirmContext, true),
                        child: const Text('Unlink'),
                      ),
                    ],
                  );
                },
              );
              if (confirmed != true || !dialogContext.mounted) return;

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

  /// One menu button per user. Everything else that used to sit beside it
  /// (the status badge, and for a parent the children button) took the
  /// width the name needed, so on a phone a parent's name broke over three
  /// lines and their email over three more.
  Widget _buildUserActions(Map<String, dynamic> user, String role) {
    final isActive = user['status'] == 'active';
    return PopupMenuButton<String>(
      tooltip: 'Manage user',
      onSelected: (action) {
        if (action == 'edit') {
          _editUser(user, role);
        } else if (action == 'children') {
          _manageParentChildren(user);
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
        if (role == 'Parent')
          const PopupMenuItem(
            value: 'children',
            child: ListTile(
              leading: Icon(Icons.family_restroom_outlined),
              title: Text('Linked children'),
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
    );
  }

  /// One person: avatar, name and a few short lines, then their status and
  /// the menu at the right.
  Widget _userTile({
    required int index,
    required dynamic user,
    required String role,
    required List<String> lines,
  }) {
    final theme = Theme.of(context);
    final data = Map<String, dynamic>.from(user as Map);
    final name = _getFullName(data).trim();
    final active = data['status'] == 'active';
    return AppCard(
      index: index,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.md,
          AppSpace.md,
          AppSpace.xs,
          AppSpace.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProfileAvatar(name: name, radius: 20),
            const SizedBox(width: AppSpace.md),
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
                  const SizedBox(height: 2),
                  for (final line in lines.where((l) => l.trim().isNotEmpty))
                    Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            // The status sits at the right, level with the name, the same
            // place on every card on a phone and on a laptop.
            const SizedBox(width: AppSpace.sm),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: StatusBadge(
                label: active ? 'Active' : 'Inactive',
                tone: StatusTone.forLevel(
                  context,
                  active ? StatusLevel.good : StatusLevel.stop,
                ),
              ),
            ),
            _buildUserActions(data, role),
          ],
        ),
      ),
    );
  }

  /// The list of people: one column on a phone, two side by side on a
  /// laptop, where one card per row stretched across the whole screen.
  Widget _userList({
    required int count,
    required Widget Function(int index) itemBuilder,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 2 : 1;
        final rows = (count / columns).ceil();
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          itemCount: rows,
          itemBuilder: (context, row) {
            if (columns == 1) return itemBuilder(row);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var c = 0; c < columns; c++) ...[
                  Expanded(
                    child: row * columns + c < count
                        ? itemBuilder(row * columns + c)
                        : const SizedBox.shrink(),
                  ),
                  if (c != columns - 1) const SizedBox(width: AppSpace.md),
                ],
              ],
            );
          },
        );
      },
    );
  }

  /// Keeps the search, filters and list to a readable width on a laptop.
  Widget _tabFrame(Widget child) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: child,
      ),
    );
  }

  String _getFullName(dynamic user) {
    final first = user['first_name'] ?? '';
    final middle = user['middle_name'] ?? '';
    final last = user['last_name'] ?? '';
    if (middle.isEmpty) return '$first $last';
    return '$first $middle $last';
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

  // ── filtering and sorting ──────────────────────────────────────────

  bool _matchesStatus(dynamic user) {
    if (_statusFilter == _anyStatus) return true;
    final status = (user['status'] ?? '').toString().toLowerCase();
    return _statusFilter == 'Active' ? status == 'active' : status != 'active';
  }

  /// The choices a filter offers, taken from the accounts that were loaded, so
  /// it never offers a department, course or year that would show nothing.
  List<String> _optionsFor(List<dynamic> users, String field) {
    final values = users
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

  // A filter left over from an earlier load may no longer exist, so it falls
  // back to showing everything.
  String _safeValue(String selected, String fallback, List<String> options) =>
      options.contains(selected) ? selected : fallback;

  /// Sorts a copy, never the loaded list itself.
  List<dynamic> _sorted(List<dynamic> users, String idField) {
    final sorted = [...users];
    int byName(dynamic left, dynamic right) => _getFullName(
      left,
    ).toUpperCase().compareTo(_getFullName(right).toUpperCase());

    if (_sortMode == _sortNameZA) {
      sorted.sort((left, right) => byName(right, left));
    } else if (_sortMode == _sortStudentNumber ||
        _sortMode == _sortEmployeeNumber) {
      sorted.sort((left, right) {
        final leftId = (left[idField] ?? '').toString();
        final rightId = (right[idField] ?? '').toString();
        // An account with no number yet goes last rather than first.
        if (leftId.isEmpty != rightId.isEmpty) return leftId.isEmpty ? 1 : -1;
        final byId = leftId.toUpperCase().compareTo(rightId.toUpperCase());
        return byId != 0 ? byId : byName(left, right);
      });
    } else if (_sortMode == _sortStatus) {
      sorted.sort((left, right) {
        final leftActive = (left['status'] ?? '') == 'active';
        final rightActive = (right['status'] ?? '') == 'active';
        if (leftActive != rightActive) return leftActive ? -1 : 1;
        return byName(left, right);
      });
    } else {
      sorted.sort(byName);
    }
    return sorted;
  }

  bool _matchesField(dynamic row, String field, String chosen, String any) =>
      chosen == any || (row[field] ?? '').toString().trim() == chosen;

  List<dynamic> _filterStudents(
    String department,
    String course,
    String year,
  ) {
    final kept = _students.where((s) {
      if (!_matchesStatus(s)) return false;
      if (!_matchesField(s, 'department', department, _anyDepartment)) {
        return false;
      }
      if (!_matchesField(s, 'course', course, _anyCourse)) return false;
      if (!_matchesField(s, 'year_level', year, _anyYear)) return false;
      if (_searchQuery.isEmpty) return true;
      return _getFullName(s).toLowerCase().contains(_searchQuery) ||
          (s['student_number'] ?? '').toLowerCase().contains(_searchQuery) ||
          (s['email'] ?? '').toLowerCase().contains(_searchQuery) ||
          (s['course'] ?? '').toLowerCase().contains(_searchQuery);
    }).toList();
    return _sorted(kept, 'student_number');
  }

  List<dynamic> _filterTeachers() {
    final kept = _teachers.where((t) {
      if (!_matchesStatus(t)) return false;
      if (_searchQuery.isEmpty) return true;
      return _getFullName(t).toLowerCase().contains(_searchQuery) ||
          (t['employee_number'] ?? '').toLowerCase().contains(_searchQuery) ||
          (t['email'] ?? '').toLowerCase().contains(_searchQuery);
    }).toList();
    return _sorted(kept, 'employee_number');
  }

  List<dynamic> _filterParents() {
    final kept = _parents.where((p) {
      if (!_matchesStatus(p)) return false;
      if (_searchQuery.isEmpty) return true;
      return _getFullName(p).toLowerCase().contains(_searchQuery) ||
          (p['contact_number'] ?? '').toLowerCase().contains(_searchQuery) ||
          (p['email'] ?? '').toLowerCase().contains(_searchQuery);
    }).toList();
    return _sorted(kept, 'contact_number');
  }

  /// The row of filters under the search box.
  ///
  /// It lays itself out for the screen it is on: all in one row on a laptop,
  /// two to a row on a small window, one to a row on a phone. Fixed widths
  /// were what pushed the last filter off the edge of a narrow screen.
  Widget _buildToolbar({
    required List<String> sortModes,
    List<String> departmentOptions = const [],
    List<String> courseOptions = const [],
    List<String> yearOptions = const [],
    String department = _anyDepartment,
    String course = _anyCourse,
    String year = _anyYear,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: FilterBar(
        children: [
          FilterDropdown(
            value: _sortMode,
            options: sortModes,
            icon: Icons.sort_rounded,
            onChanged: (chosen) => setState(() => _sortMode = chosen),
          ),
          FilterDropdown(
            value: _statusFilter,
            options: const [_anyStatus, 'Active', 'Inactive'],
            icon: Icons.toggle_on_outlined,
            onChanged: (chosen) => setState(() => _statusFilter = chosen),
          ),
          if (departmentOptions.isNotEmpty)
            FilterDropdown(
              value: department,
              options: [_anyDepartment, ...departmentOptions],
              icon: Icons.apartment_outlined,
              onChanged: (chosen) => setState(() {
                _departmentFilter = chosen;
                // The course below may not belong to the new department.
                _courseFilter = _anyCourse;
                _yearFilter = _anyYear;
              }),
            ),
          if (courseOptions.isNotEmpty)
            FilterDropdown(
              value: course,
              options: [_anyCourse, ...courseOptions],
              icon: Icons.school_outlined,
              onChanged: (chosen) => setState(() {
                _courseFilter = chosen;
                _yearFilter = _anyYear;
              }),
            ),
          if (yearOptions.isNotEmpty)
            FilterDropdown(
              value: year,
              options: [_anyYear, ...yearOptions],
              icon: Icons.format_list_numbered_rounded,
              onChanged: (chosen) => setState(() => _yearFilter = chosen),
            ),
        ],
      ),
    );
  }

  Widget _buildStudentsTab() {
    // Each filter is built from what the one before it leaves, so a course
    // outside the chosen department is never offered.
    final departmentOptions = _optionsFor(_students, 'department');
    final department = _safeValue(
      _departmentFilter,
      _anyDepartment,
      departmentOptions,
    );
    final inDepartment = _students
        .where((s) => _matchesField(s, 'department', department, _anyDepartment))
        .toList();

    final courseOptions = _optionsFor(inDepartment, 'course');
    final course = _safeValue(_courseFilter, _anyCourse, courseOptions);
    final inCourse = inDepartment
        .where((s) => _matchesField(s, 'course', course, _anyCourse))
        .toList();

    final yearOptions = _optionsFor(inCourse, 'year_level');
    final year = _safeValue(_yearFilter, _anyYear, yearOptions);
    final filtered = _filterStudents(department, course, year);
    return _tabFrame(Column(
      children: [
        _buildSearchBar(),
        _buildToolbar(
          sortModes: _studentSortModes,
          departmentOptions: departmentOptions,
          courseOptions: courseOptions,
          yearOptions: yearOptions,
          department: department,
          course: course,
          year: year,
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No students found.'))
              : _userList(
                  count: filtered.length,
                  itemBuilder: (index) {
                    final s = filtered[index];
                    final course = s['course']?.toString() ?? '';
                    final year = s['year_level']?.toString() ?? '';
                    return _userTile(
                      index: index,
                      user: s,
                      role: 'Student',
                      lines: [
                        s['student_number']?.toString() ?? '',
                        [
                          course,
                          if (year.isNotEmpty) 'Year $year',
                        ].where((p) => p.isNotEmpty).join('  ·  '),
                        s['email']?.toString() ?? '',
                      ],
                    );
                  },
                ),
        ),
      ],
    ));
  }

  Widget _buildTeachersTab() {
    final filtered = _filterTeachers();
    return _tabFrame(Column(
      children: [
        _buildSearchBar(),
        _buildToolbar(sortModes: _teacherSortModes),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No teachers found.'))
              : _userList(
                  count: filtered.length,
                  itemBuilder: (index) {
                    final t = filtered[index];
                    return _userTile(
                      index: index,
                      user: t,
                      role: 'Teacher',
                      lines: [
                        t['employee_number']?.toString() ?? '',
                        t['email']?.toString() ?? '',
                      ],
                    );
                  },
                ),
        ),
      ],
    ));
  }

  Widget _buildParentsTab() {
    final filtered = _filterParents();
    return _tabFrame(Column(
      children: [
        _buildSearchBar(),
        // A parent has no student or employee number, so that way of sorting
        // is left out here rather than offered and quietly doing nothing.
        _buildToolbar(sortModes: _parentSortModes),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No parents found.'))
              : _userList(
                  count: filtered.length,
                  itemBuilder: (index) {
                    final p = filtered[index];
                    final children =
                        int.tryParse('${p['children_count'] ?? 0}') ?? 0;
                    final contact = p['contact_number']?.toString() ?? '';
                    return _userTile(
                      index: index,
                      user: p,
                      role: 'Parent',
                      lines: [
                        [
                          contact.isEmpty ? 'No contact number' : contact,
                          '$children ${children == 1 ? 'child' : 'children'}',
                        ].join('  ·  '),
                        p['email']?.toString() ?? '',
                      ],
                    );
                  },
                ),
        ),
      ],
    ));
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
      floatingActionButton: _tabController.index == 1 && !_isLoading
          ? FloatingActionButton.extended(
              onPressed: _addTeacher,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add teacher'),
            )
          : null,
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

import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../widgets/app_ui.dart';

enum _Stage { pick, checking, preview, importing, done }

class _ResendNote {
  final bool ok;
  final String text;
  const _ResendNote(this.ok, this.text);
}

/// Admin screen for creating many student and parent accounts from one Excel
/// file. Each new account is emailed a temporary password and must set its own
/// password at the first sign-in.
class AdminBulkAccountsScreen extends StatefulWidget {
  final String token;

  const AdminBulkAccountsScreen({super.key, required this.token});

  @override
  State<AdminBulkAccountsScreen> createState() =>
      _AdminBulkAccountsScreenState();
}

class _AdminBulkAccountsScreenState extends State<AdminBulkAccountsScreen>
    with SingleTickerProviderStateMixin {
  // Small groups keep every server call short.
  static const _batchSize = 5;
  static const _resendBatchSize = 10;
  static const _maxListed = 100;

  static const _requiredColumns = [
    'Student Number',
    'Student First Name',
    'Student Last Name',
    'Course',
    'Year Level',
    'Student Email',
    'Parent First Name',
    'Parent Last Name',
    'Parent Email',
  ];
  static const _optionalColumns = [
    'Student Middle Name',
    'Section',
    'Parent Middle Name',
    'Parent Contact Number',
  ];

  late final TabController _tabs = TabController(length: 2, vsync: this);

  _Stage _stage = _Stage.pick;
  String _error = '';
  String _fileName = '';
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _rows = [];

  int _processed = 0;
  int _totalToImport = 0;
  bool _cancelRequested = false;
  String _stoppedMessage = '';
  List<Map<String, dynamic>> _results = [];

  bool _pendingLoaded = false;
  bool _pendingLoading = false;
  String _pendingError = '';
  List<Map<String, dynamic>> _pending = [];
  bool _resendBusy = false;
  String _resendProgress = '';
  final Map<String, _ResendNote> _resendNotes = {};

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (_tabs.index == 1 && !_pendingLoaded && !_pendingLoading) {
        _loadPending();
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ helpers

  String _text(dynamic value) => value?.toString() ?? '';

  int _int(dynamic value) => (value as num?)?.toInt() ?? 0;

  String _friendly(Object error) {
    if (error is FormatException) {
      return 'The server took too long or sent an unexpected reply. Please try again.';
    }
    return error.toString().replaceFirst('Exception: ', '');
  }

  List<String> _stringList(dynamic value) =>
      (value as List<dynamic>? ?? []).map((item) => item.toString()).toList();

  void _snack(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  String _capitalize(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

  // -------------------------------------------------------------- import flow

  Future<void> _chooseFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'csv'],
    );
    if (!mounted || file == null) return;

    setState(() {
      _stage = _Stage.checking;
      _error = '';
      _fileName = file.name;
    });
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        throw Exception('The selected file could not be read.');
      }
      final result = await ApiService.previewBulkAccounts(
        token: widget.token,
        fileName: file.name,
        bytes: bytes,
      );
      if (!mounted) return;
      setState(() {
        _summary = Map<String, dynamic>.from(result['summary'] as Map);
        _rows = (result['rows'] as List<dynamic>? ?? [])
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
        _stage = _Stage.preview;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _friendly(error);
        _stage = _Stage.pick;
      });
    }
  }

  void _reset() {
    setState(() {
      _stage = _Stage.pick;
      _error = '';
      _fileName = '';
      _summary = {};
      _rows = [];
      _results = [];
      _stoppedMessage = '';
    });
  }

  Future<void> _confirmImport() async {
    final students = _int(_summary['students_to_create']);
    final parents = _int(_summary['parents_to_create']);
    final emails = _int(_summary['emails_to_send']);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create the accounts?'),
        content: Text(
          'This creates $students student account${students == 1 ? '' : 's'} '
          'and $parents new parent account${parents == 1 ? '' : 's'}, then '
          'emails $emails ${emails == 1 ? 'person' : 'people'} a temporary '
          'password.\n\nRows with problems are skipped. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Create accounts'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _startImport();
  }

  Future<void> _startImport() async {
    final ready = _rows
        .where((row) => row['status'] == 'ok')
        .map((row) => Map<String, dynamic>.from(row['data'] as Map))
        .toList();
    if (ready.isEmpty) return;

    setState(() {
      _stage = _Stage.importing;
      _processed = 0;
      _totalToImport = ready.length;
      _cancelRequested = false;
      _stoppedMessage = '';
      _results = [];
      _pendingLoaded = false;
    });

    for (var i = 0; i < ready.length; i += _batchSize) {
      if (_cancelRequested) {
        _stoppedMessage =
            'Stopped. ${ready.length - i} row${ready.length - i == 1 ? ' was' : 's were'} not processed. '
            'Upload the same file again to continue: rows that were already created are skipped.';
        break;
      }
      final batch = ready.sublist(i, math.min(i + _batchSize, ready.length));
      try {
        final result = await ApiService.commitBulkAccounts(
          token: widget.token,
          rows: batch,
        );
        _results.addAll(
          (result['results'] as List<dynamic>? ?? []).map(
            (item) => Map<String, dynamic>.from(item as Map),
          ),
        );
      } catch (error) {
        _stoppedMessage =
            'The import stopped at row ${batch.first['row']}: ${_friendly(error)} '
            'Some accounts in that last group may already have been created. '
            'Check the "Not signed in yet" tab, then upload the same file again: '
            'rows that were already created are skipped.';
        break;
      }
      if (!mounted) return;
      setState(() => _processed = i + batch.length);
    }

    if (!mounted) return;
    setState(() => _stage = _Stage.done);
  }

  // ------------------------------------------------------------- pending list

  Future<void> _loadPending() async {
    setState(() {
      _pendingLoading = true;
      _pendingError = '';
    });
    try {
      final result = await ApiService.getPendingAccounts(token: widget.token);
      if (!mounted) return;
      setState(() {
        _pending = (result['accounts'] as List<dynamic>? ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        _pendingLoaded = true;
        _pendingLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _pendingError = _friendly(error);
        _pendingLoading = false;
      });
    }
  }

  Future<void> _resend(List<String> emails) async {
    if (_resendBusy || emails.isEmpty) return;
    setState(() {
      _resendBusy = true;
      _resendProgress = '';
    });
    var sent = 0;
    var failed = 0;
    try {
      for (var i = 0; i < emails.length; i += _resendBatchSize) {
        final batch = emails.sublist(
          i,
          math.min(i + _resendBatchSize, emails.length),
        );
        final result = await ApiService.resendAccountEmails(
          token: widget.token,
          emails: batch,
        );
        for (final item in (result['results'] as List<dynamic>? ?? [])) {
          final map = Map<String, dynamic>.from(item as Map);
          final ok = map['sent'] == true;
          _resendNotes[_text(map['email']).toLowerCase()] = _ResendNote(
            ok,
            ok ? 'A new temporary password was emailed.' : _text(map['message']),
          );
          if (ok) {
            sent++;
          } else {
            failed++;
          }
        }
        if (!mounted) return;
        setState(
          () => _resendProgress = 'Processed ${i + batch.length} of ${emails.length}...',
        );
      }
      _snack('Emails sent: $sent. Not sent: $failed.', isError: failed > 0);
    } catch (error) {
      _snack(_friendly(error), isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _resendBusy = false;
          _resendProgress = '';
        });
      }
    }
  }

  Future<void> _confirmResendAll() async {
    final emails = _pending.map((a) => _text(a['email'])).toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resend to everyone?'),
        content: Text(
          'Each of the ${emails.length} accounts gets a NEW temporary password '
          'by email. Their old temporary password stops working.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Resend'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _resend(emails);
  }

  // -------------------------------------------------------------- shared UI

  Widget _page(List<Widget> children) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
  }

  Widget _notice(String text, {bool isError = false, IconData? icon}) {
    final scheme = Theme.of(context).colorScheme;
    final color = isError ? scheme.error : scheme.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon ?? (isError ? Icons.error_outline : Icons.info_outline),
            color: color,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
        ],
      ),
    );
  }

  Widget _stat(String label, int value, {Color? color}) {
    final theme = Theme.of(context);
    final accent = color ?? theme.colorScheme.primary;
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    );
  }

  // A row of the problem lists: "Row 4 • BSIT-... • Name" and its messages.
  Widget _problemCard({
    required String title,
    required List<String> messages,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            ...messages.map(
              (message) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 8),
                      child: Icon(Icons.circle, size: 6, color: color),
                    ),
                    Expanded(
                      child: Text(
                        message,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: color,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _rowTitle(Map<String, dynamic> row) {
    final data = row['data'] is Map
        ? Map<String, dynamic>.from(row['data'] as Map)
        : <String, dynamic>{};
    final name = [
      _text(data['student_first_name']),
      _text(data['student_last_name']),
    ].where((part) => part.isNotEmpty).join(' ');
    return [
      'Row ${_text(row['row'])}',
      if (_text(data['student_number']).isNotEmpty) _text(data['student_number']),
      if (name.isNotEmpty) name,
    ].join(' • ');
  }

  // ----------------------------------------------------------------- Import tab

  Widget _buildImportTab() {
    switch (_stage) {
      case _Stage.pick:
        return _buildPick();
      case _Stage.checking:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('Checking $_fileName...'),
            ],
          ),
        );
      case _Stage.preview:
        return _buildPreview();
      case _Stage.importing:
        return _buildImporting();
      case _Stage.done:
        return _buildDone();
    }
  }

  Widget _buildPick() {
    final theme = Theme.of(context);
    Widget step(String number, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              number,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
        ],
      ),
    );

    return _page([
      if (_error.isNotEmpty) _notice(_error, isError: true),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Create student and parent accounts from Excel',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              step('1', 'Fill in the BenildeSafe template. One row is one student and that student\'s parent.'),
              step('2', 'Upload the file. Every row is checked first and nothing is created yet.'),
              step('3', 'Review the result and confirm. Each new account is emailed a temporary password, with the web and app links.'),
              step('4', 'Everyone sets their own password the first time they sign in.'),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Columns (the first row of the file)',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final name in _requiredColumns)
                    Chip(
                      label: Text(name),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: theme.colorScheme.primaryContainer,
                    ),
                  for (final name in _optionalColumns)
                    Chip(
                      label: Text('$name (optional)'),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'A parent with several children: repeat the same parent email on '
                'each child\'s row. The parent gets one account linked to all of '
                'the children. A student can only have one parent.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 18),
      FilledButton.icon(
        onPressed: _chooseFile,
        icon: const Icon(Icons.upload_file_rounded),
        label: const Text('Choose Excel file'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      ),
      const SizedBox(height: 8),
      Center(
        child: Text(
          '.xlsx or .csv, up to 2 MB',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ]);
  }

  Widget _buildPreview() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ready = _int(_summary['ready_rows']);
    final problems = _int(_summary['error_rows']);
    final emails = _int(_summary['emails_to_send']);

    final problemRows = _rows.where((row) => row['status'] == 'error').toList();
    final warningRows = _rows
        .where(
          (row) =>
              row['status'] == 'ok' && _stringList(row['warnings']).isNotEmpty,
        )
        .toList();

    return _page([
      Row(
        children: [
          Icon(Icons.description_outlined, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _stat('Rows in file', _int(_summary['total_rows'])),
          _stat('Ready', ready, color: const Color(0xFF248A5A)),
          _stat(
            'With problems',
            problems,
            color: problems > 0 ? scheme.error : null,
          ),
          _stat('New students', _int(_summary['students_to_create'])),
          _stat('New parents', _int(_summary['parents_to_create'])),
          _stat('Parents with an account', _int(_summary['existing_parents'])),
          _stat('Emails to send', emails),
        ],
      ),
      const SizedBox(height: 14),
      if (_summary['courses_checked'] != true)
        _notice('The courses could not be checked against your course list.'),
      if (emails > 100)
        _notice(
          'This sends $emails emails. Check your email provider\'s daily '
          'sending limit first (a regular Gmail account allows about 500 a day). '
          'Emails that cannot be sent can be resent from the "Not signed in yet" tab.',
        ),
      if (problemRows.isNotEmpty) ...[
        _sectionTitle('ROWS WITH PROBLEMS (SKIPPED)'),
        ...problemRows
            .take(_maxListed)
            .map(
              (row) => _problemCard(
                title: _rowTitle(row),
                messages: _stringList(row['errors']),
                color: scheme.error,
              ),
            ),
        if (problemRows.length > _maxListed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'And ${problemRows.length - _maxListed} more rows with problems.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 4),
        Text(
          'Fix these rows in the file and upload it again. Rows that were '
          'already created are skipped, so it is safe to upload the same file twice.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ],
      if (warningRows.isNotEmpty) ...[
        _sectionTitle('WARNINGS (STILL IMPORTED)'),
        Card(
          child: ExpansionTile(
            title: Text(
              '${warningRows.length} row${warningRows.length == 1 ? '' : 's'} with warnings',
            ),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: warningRows
                .take(_maxListed)
                .map(
                  (row) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _rowTitle(row),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        ..._stringList(row['warnings']).map(
                          (message) => Text(
                            message,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFFB7791F),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
      const SizedBox(height: 22),
      FilledButton.icon(
        onPressed: ready > 0 ? _confirmImport : null,
        icon: const Icon(Icons.group_add_rounded),
        label: Text(
          ready > 0
              ? 'Create $ready student account${ready == 1 ? '' : 's'} and send emails'
              : 'Nothing to import',
        ),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      ),
      const SizedBox(height: 10),
      OutlinedButton(
        onPressed: _reset,
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: const Text('Choose another file'),
      ),
    ]);
  }

  Widget _buildImporting() {
    final theme = Theme.of(context);
    final fraction = _totalToImport == 0 ? 0.0 : _processed / _totalToImport;
    return _page([
      const SizedBox(height: 40),
      Icon(Icons.forward_to_inbox_rounded, size: 48, color: theme.colorScheme.primary),
      const SizedBox(height: 18),
      Text(
        'Creating accounts and sending emails...',
        textAlign: TextAlign.center,
        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 18),
      LinearProgressIndicator(value: fraction, minHeight: 8),
      const SizedBox(height: 10),
      Text(
        '$_processed of $_totalToImport rows',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: 8),
      Text(
        'Keep this screen open until it finishes.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 22),
      OutlinedButton(
        onPressed: _cancelRequested
            ? null
            : () => setState(() => _cancelRequested = true),
        child: Text(
          _cancelRequested ? 'Stopping after this group...' : 'Stop after this group',
        ),
      ),
    ]);
  }

  Widget _buildDone() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final created = _results.where((r) => r['status'] == 'created').toList();
    final rejected = _results.where((r) => r['status'] != 'created').toList();
    final emailFailed = created
        .where(
          (r) => r['student_email_sent'] != true || r['parent_email_sent'] == false,
        )
        .toList();

    return _page([
      if (_stoppedMessage.isNotEmpty) _notice(_stoppedMessage, isError: true),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _stat('Rows created', created.length, color: const Color(0xFF248A5A)),
          _stat(
            'Rejected by the server',
            rejected.length,
            color: rejected.isNotEmpty ? scheme.error : null,
          ),
          _stat('Skipped (problems)', _int(_summary['error_rows'])),
          _stat(
            'Rows with an email not sent',
            emailFailed.length,
            color: emailFailed.isNotEmpty ? scheme.error : null,
          ),
        ],
      ),
      if (emailFailed.isNotEmpty) ...[
        const SizedBox(height: 14),
        _notice(
          'The accounts exist, but some emails could not be sent. Open the '
          '"Not signed in yet" tab and resend them.',
          icon: Icons.mark_email_unread_outlined,
        ),
        ...emailFailed
            .take(_maxListed)
            .map(
              (r) => _problemCard(
                title: 'Row ${_text(r['row'])} • ${_text(r['student_number'])} • ${_text(r['student_name'])}',
                messages: [_text(r['email_message'])],
                color: scheme.error,
              ),
            ),
      ],
      if (rejected.isNotEmpty) ...[
        _sectionTitle('NOT CREATED'),
        ...rejected
            .take(_maxListed)
            .map(
              (r) => _problemCard(
                title: 'Row ${_text(r['row'])} • ${_text(r['student_number'])} • ${_text(r['student_name'])}',
                messages: [_text(r['message'])],
                color: scheme.error,
              ),
            ),
      ],
      const SizedBox(height: 22),
      FilledButton.icon(
        onPressed: () {
          _tabs.animateTo(1);
          _loadPending();
        },
        icon: const Icon(Icons.pending_actions_rounded),
        label: const Text('View accounts not signed in yet'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      ),
      const SizedBox(height: 10),
      OutlinedButton(
        onPressed: _reset,
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: const Text('Import another file'),
      ),
    ]);
  }

  // ---------------------------------------------------------------- Pending tab

  Widget _buildPendingTab() {
    final theme = Theme.of(context);

    if (_pendingError.isNotEmpty) {
      return Center(
        child: EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load the accounts',
          message: _pendingError,
          action: FilledButton.icon(
            onPressed: _loadPending,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ),
      );
    }
    if (!_pendingLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadPending,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_pending.isEmpty)
                    const EmptyState(
                      icon: Icons.verified_user_outlined,
                      title: 'Everyone has signed in',
                      message:
                          'No account is waiting on a temporary password.',
                    )
                  else ...[
                    Text(
                      '${_pending.length} account${_pending.length == 1 ? '' : 's'} '
                      'with a temporary password that ${_pending.length == 1 ? 'has' : 'have'} not signed in yet.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: _resendBusy ? null : _confirmResendAll,
                      icon: _resendBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.forward_to_inbox_rounded),
                      label: Text(
                        _resendBusy
                            ? (_resendProgress.isEmpty ? 'Sending...' : _resendProgress)
                            : 'Resend to all (${_pending.length})',
                      ),
                    ),
                    const SizedBox(height: 14),
                    ..._pending.map(_buildPendingTile),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingTile(Map<String, dynamic> account) {
    final theme = Theme.of(context);
    final email = _text(account['email']);
    final name = _text(account['full_name']);
    final role = _text(account['role']);
    final studentNumber = _text(account['student_number']);
    final note = _resendNotes[email.toLowerCase()];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? email : name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      email,
                      if (studentNumber.isNotEmpty) studentNumber,
                    ].join(' • '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (note != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      note.text,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: note.ok
                            ? const Color(0xFF248A5A)
                            : theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (role.isNotEmpty) StatusBadge(label: _capitalize(role)),
            TextButton(
              onPressed: _resendBusy ? null : () => _resend([email]),
              child: const Text('Resend'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bulk accounts'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Import'),
            Tab(text: 'Not signed in yet'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_buildImportTab(), _buildPendingTab()],
      ),
    );
  }
}

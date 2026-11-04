import 'package:flutter/material.dart';

import 'admin_child_link_requests_tab.dart';

/// Parents asking to link another child to their account.
///
/// This used to sit beside a tab for self-registration requests. Accounts are
/// now created by the school — students and parents from the registrar's
/// master list, teachers one at a time in User Management — so the only thing
/// left for the administrator to approve here is a child link.
class AdminChildLinkRequestsScreen extends StatelessWidget {
  final String token;

  const AdminChildLinkRequestsScreen({super.key, required this.token});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Child link requests')),
      body: AdminChildLinkRequestsTab(token: token),
    );
  }
}

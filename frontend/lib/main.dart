import 'package:flutter/material.dart';

import 'screens/admin_dashboard_screen.dart';
import 'screens/attendance_screen.dart';
import 'screens/login_screen.dart';
import 'screens/parent_dashboard_screen.dart';
import 'services/app_preferences.dart';
import 'services/session_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPreferences.instance.load();
  final session = await SessionService.load();
  runApp(MyApp(session: session));
}

/// Opens the dashboard that matches a saved session's role.
Widget homeForSession(Session session) {
  switch (session.role) {
    case 'student':
      return AttendanceScreen(
        token: session.token,
        email: session.email,
        fullName: session.fullName,
        firstName: session.firstName,
      );
    case 'teacher':
      return AttendanceScreen(
        token: session.token,
        email: session.email,
        fullName: session.fullName,
        firstName: session.firstName,
        isTeacher: true,
      );
    case 'admin':
      return AdminDashboardScreen(
        token: session.token,
        email: session.email,
        fullName: session.fullName,
      );
    case 'parent':
      return ParentDashboardScreen(
        token: session.token,
        email: session.email,
        fullName: session.fullName,
      );
    default:
      return const LoginScreen();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.session});

  final Session? session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppPreferences.instance,
      builder: (context, _) => MaterialApp(
        title: 'BenildeSafe',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: AppPreferences.instance.isDarkMode
            ? ThemeMode.dark
            : ThemeMode.light,
        home: session == null ? const LoginScreen() : homeForSession(session!),
      ),
    );
  }
}
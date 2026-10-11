import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'services/app_preferences.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPreferences.instance.load();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
        home: const LoginScreen(),
      ),
    );
  }
}
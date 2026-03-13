import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'screens/auth/login_screen.dart';

void main() {
  runApp(const UrbappApp());
}

class UrbappApp extends StatelessWidget {
  const UrbappApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Urbapp',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const LoginScreen(),
    );
  }
}

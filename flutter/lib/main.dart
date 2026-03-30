import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/app_theme.dart';
import 'screens/auth/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://mqdbakhsfmzghhliedhi.supabase.co',
    anonKey: 'sb_publishable_mxbGnr12no0d1BJApPPSkw_4_JZ9gNA',
  );

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

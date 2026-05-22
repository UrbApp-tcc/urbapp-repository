import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/auth/auth_gate.dart';
import 'theme/app_theme.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

void main() async {
  assert(_supabaseUrl.isNotEmpty, 'SUPABASE_URL não definida. Rode com --dart-define-from-file=dart_defines/dev.json');
  assert(_supabaseAnonKey.isNotEmpty, 'SUPABASE_ANON_KEY não definida. Rode com --dart-define-from-file=dart_defines/dev.json');

  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: _supabaseUrl,
    anonKey: _supabaseAnonKey,
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
      home: const AuthGate(),
    );
  }
}

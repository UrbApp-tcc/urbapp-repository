import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/auth/auth_gate.dart';
import 'theme/app_theme.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const _legacyAnonKey = String.fromEnvironment('ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final resolvedAnonKey = _supabaseAnonKey.isNotEmpty ? _supabaseAnonKey : _legacyAnonKey;
  final missingValues = <String>[
    if (_supabaseUrl.isEmpty) 'SUPABASE_URL',
    if (resolvedAnonKey.isEmpty) 'SUPABASE_ANON_KEY (ou ANON_KEY)',
  ];

  if (missingValues.isNotEmpty || _looksLikePlaceholder(_supabaseUrl) || _looksLikePlaceholder(resolvedAnonKey)) {
    runApp(
      ConfigurationErrorApp(
        message: [
          if (missingValues.isNotEmpty) 'Faltam as variáveis: ${missingValues.join(', ')}.',
          if (_looksLikePlaceholder(_supabaseUrl) || _looksLikePlaceholder(resolvedAnonKey))
            'O arquivo de configuração ainda está com valores de exemplo.',
          'Crie flutter/dart_defines/dev.json a partir de dev.json.example e rode com '
              '--dart-define-from-file=dart_defines/dev.json.',
        ].join('\n\n'),
      ),
    );
    return;
  }

  final validationError = await _validateSupabasePublicConfig(
    url: _supabaseUrl,
    anonKey: resolvedAnonKey,
  );
  if (validationError != null) {
    runApp(ConfigurationErrorApp(message: validationError));
    return;
  }

  try {
    await Supabase.initialize(
      url: _supabaseUrl,
      anonKey: resolvedAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
  } catch (error) {
    runApp(
      ConfigurationErrorApp(
        message: 'Não foi possível inicializar o Supabase.\n\n$error',
      ),
    );
    return;
  }

  runApp(const UrbappApp());
}

bool _looksLikePlaceholder(String value) {
  if (value.isEmpty) return false;

  final normalized = value.toLowerCase();
  return normalized.contains('seu_projeto') ||
      normalized.contains('sua_anon_key') ||
      normalized.contains('example');
}

Future<String?> _validateSupabasePublicConfig({
  required String url,
  required String anonKey,
}) async {
  try {
    final response = await http.get(
      Uri.parse('$url/auth/v1/settings'),
      headers: {
        'apikey': anonKey,
        'Authorization': 'Bearer $anonKey',
      },
    );

    if (response.statusCode == 200) return null;

    final body = response.body.toLowerCase();
    if (response.statusCode == 401 && body.contains('unregistered api key')) {
      return [
        'A SUPABASE_ANON_KEY configurada no flutter/dart_defines/dev.json não pertence mais a este projeto.',
        'Atualize esse valor com a Publishable key atual em Supabase > Project Settings > API Keys.',
        'Depois rode novamente com --dart-define-from-file=dart_defines/dev.json.',
      ].join('\n\n');
    }

    return [
      'A configuração do Supabase foi carregada, mas a validação da API falhou.',
      'Status: ${response.statusCode}',
      'Resposta: ${response.body}',
    ].join('\n\n');
  } catch (error) {
    return [
      'Não foi possível validar a configuração pública do Supabase.',
      '$error',
    ].join('\n\n');
  }
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

class ConfigurationErrorApp extends StatelessWidget {
  const ConfigurationErrorApp({
    super.key,
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF7F8FA),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.settings_input_component_rounded,
                          color: Color(0xFF8F6FE8),
                          size: 28,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Configuração do app pendente',
                            style: TextStyle(
                              color: Color(0xFF141E28),
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'O app abriu, mas não conseguiu ler a configuração local do Supabase.',
                      style: TextStyle(
                        color: Color(0xFF4B5563),
                        fontSize: 15,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SelectableText(
                      message,
                      style: const TextStyle(
                        color: Color(0xFF141E28),
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F4FF),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE5DBFF)),
                      ),
                      child: const SelectableText(
                        'flutter run --dart-define-from-file=dart_defines/dev.json',
                        style: TextStyle(
                          color: Color(0xFF5B43B5),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

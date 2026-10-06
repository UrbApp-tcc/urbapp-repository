import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/auth/auth_gate.dart';
import 'theme/app_theme.dart';
import 'widgets/urb/urb_components.dart';

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
      title: 'UrbApp',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => _PhoneFrame(child: child ?? const SizedBox.shrink()),
      home: const AuthGate(),
    );
  }
}

/// Em telas largas (web/desktop), mantém a composição mobile do protótipo
/// centralizada com 430px, como no Figma.
class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 700) return child;
    return ColoredBox(
      color: const Color(0xFFE9EDE9),
      child: Center(
        child: Container(
          width: 430,
          decoration: const BoxDecoration(
            color: UrbColors.canvas,
            boxShadow: [BoxShadow(color: Color(0x1A11233D), blurRadius: 50)],
          ),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(size: Size(430, MediaQuery.sizeOf(context).height)),
            child: child,
          ),
        ),
      ),
    );
  }
}

class ConfigurationErrorApp extends StatelessWidget {
  const ConfigurationErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const UrbBrand(compact: true),
                  const SizedBox(height: 24),
                  const UrbEyebrow('Configuração pendente'),
                  const SizedBox(height: 8),
                  Text('O app não encontrou a configuração do Supabase', style: UrbText.h2),
                  const SizedBox(height: 12),
                  SelectableText(message, style: UrbText.bodySmall),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: UrbColors.blueSoft, borderRadius: BorderRadius.circular(12)),
                    child: SelectableText(
                      'flutter run --dart-define-from-file=dart_defines/dev.json',
                      style: UrbText.label.copyWith(color: UrbColors.blue),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

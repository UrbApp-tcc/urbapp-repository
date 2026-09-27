import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Chave gravada nos metadados do usuário no Supabase.
const String onboardingMetadataKey = 'onboarding_completed';

/// O usuário já viu o primeiro acesso, segundo os metadados da conta?
bool onboardingDoneInMetadata(Map<String, dynamic>? metadata) {
  return metadata?[onboardingMetadataKey] == true;
}

/// Guarda se cada usuário já viu o primeiro acesso.
///
/// O registro principal fica na conta (metadados do Supabase), então vale
/// em qualquer aparelho. Uma cópia local evita mostrar de novo se a
/// internet falhar na hora de salvar.
class OnboardingStorage {
  OnboardingStorage({GoTrueClient? auth}) : _auth = auth;

  final GoTrueClient? _auth;

  GoTrueClient get _client => _auth ?? Supabase.instance.client.auth;

  static String _localKey(String userId) => 'onboarding_completed_v2_$userId';

  Future<bool> isCompleted({
    required String userId,
    Map<String, dynamic>? metadata,
  }) async {
    if (onboardingDoneInMetadata(metadata)) return true;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_localKey(userId)) ?? false;
  }

  Future<void> markCompleted({required String userId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_localKey(userId), true);

    try {
      await _client.updateUser(
        UserAttributes(data: {onboardingMetadataKey: true}),
      );
    } catch (_) {
      // Sem internet: a cópia local já impede de mostrar de novo aqui.
    }
  }

  /// Faz o primeiro acesso aparecer de novo para este usuário
  /// (útil para testar e para a apresentação do TCC).
  Future<void> reset({required String userId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_localKey(userId));

    try {
      await _client.updateUser(
        UserAttributes(data: {onboardingMetadataKey: false}),
      );
    } catch (_) {}
  }
}

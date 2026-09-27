import 'package:shared_preferences/shared_preferences.dart';

/// Guarda no aparelho se o usuário já viu o primeiro acesso.
class OnboardingStorage {
  static const String _key = 'onboarding_completed_v1';

  Future<bool> isCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }

  /// Faz o primeiro acesso aparecer de novo (útil para testar e apresentar).
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

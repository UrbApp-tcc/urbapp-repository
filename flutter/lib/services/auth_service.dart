import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final GoTrueClient _auth = Supabase.instance.client.auth;

  Stream<AuthState> get onAuthStateChange => _auth.onAuthStateChange;
  Session? get currentSession => _auth.currentSession;
  User? get currentUser => _auth.currentUser;

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
    } on AuthException catch (error) {
      throw Exception(_mapAuthError(error));
    } catch (_) {
      throw Exception('Erro inesperado ao entrar na conta.');
    }
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String username,
    String? phone,
  }) async {
    try {
      return await _auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          'username': username.trim(),
          'full_name': username.trim(),
          if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        },
      );
    } on AuthException catch (error) {
      throw Exception(_mapAuthError(error));
    } catch (_) {
      throw Exception('Erro inesperado ao criar a conta.');
    }
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } on AuthException catch (error) {
      throw Exception(_mapAuthError(error));
    } catch (_) {
      throw Exception('Erro inesperado ao sair da conta.');
    }
  }

  String _mapAuthError(AuthException error) {
    final message = error.message.toLowerCase();

    if (message.contains('invalid login credentials')) {
      return 'E-mail ou senha invalidos.';
    }

    if (message.contains('email not confirmed')) {
      return 'Confirme seu e-mail antes de entrar.';
    }

    if (message.contains('user already registered')) {
      return 'Ja existe uma conta cadastrada com este e-mail.';
    }

    if (message.contains('password should be at least')) {
      return 'A senha precisa ter pelo menos 6 caracteres.';
    }

    if (message.contains('signup is disabled')) {
      return 'O cadastro de novos usuarios esta desabilitado no momento.';
    }

    return error.message;
  }
}

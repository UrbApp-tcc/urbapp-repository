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
    required int cityId,
    String? phone,
  }) async {
    try {
      return await _auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          'username': username.trim(),
          'full_name': username.trim(),
          'city_id': cityId,
          if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        },
      );
    } on AuthException catch (error) {
      throw Exception(_mapAuthError(error));
    } catch (_) {
      throw Exception('Erro inesperado ao criar a conta.');
    }
  }

  Future<void> updatePassword(String newPassword) async {
    try {
      await _auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (error) {
      throw Exception(_mapAuthError(error));
    } catch (_) {
      throw Exception('Erro inesperado ao atualizar a senha.');
    }
  }

  Future<void> resetPassword(String email) async {
    try {
      await _auth.resetPasswordForEmail(email.trim());
    } on AuthException catch (error) {
      throw Exception(_mapAuthError(error));
    } catch (_) {
      throw Exception('Erro inesperado ao solicitar redefinição de senha.');
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
      return 'E-mail ou senha inválidos.';
    }

    if (message.contains('email not confirmed')) {
      return 'Confirme seu e-mail antes de entrar.';
    }

    if (message.contains('user already registered')) {
      return 'Já existe uma conta cadastrada com este e-mail.';
    }

    if (message.contains('password should be at least')) {
      return 'A senha precisa ter pelo menos 6 caracteres.';
    }

    if (message.contains('signup is disabled')) {
      return 'O cadastro de novos usuários está desabilitado no momento.';
    }

    return 'Erro de autenticação: ${error.message}';
  }
}
